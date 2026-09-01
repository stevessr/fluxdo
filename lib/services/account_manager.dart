import 'dart:async';
import 'dart:convert';

import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:flutter/foundation.dart';

import 'account_browser_session_policy.dart';
import 'auth_session.dart';
import '../constants.dart';
import 'discourse/discourse_service.dart';
import 'network/cookie/cookie_full_info.dart';
import 'network/cookie/cookie_jar_service.dart';
import 'network/cookie/raw_cookie_writer.dart';
import 'network/cookie/webview_cookie_priming.dart';
import 'preloaded_data_service.dart';
import 'storage/resilient_secure_storage.dart';

/// 已保存账号的元数据（会话快照单独存储，不进注册表）
class SavedAccount {
  final String username;
  final String? avatarTemplate;
  final DateTime savedAt;

  const SavedAccount({
    required this.username,
    this.avatarTemplate,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    if (avatarTemplate != null) 'avatar_template': avatarTemplate,
    'saved_at': savedAt.toIso8601String(),
  };

  factory SavedAccount.fromJson(Map<String, dynamic> json) => SavedAccount(
    username: json['username'] as String,
    avatarTemplate: json['avatar_template'] as String?,
    savedAt:
        DateTime.tryParse(json['saved_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// 切换失败：目标账号的本机快照缺失或已过期，需要重新登录
class AccountSessionExpiredException implements Exception {
  final String username;
  AccountSessionExpiredException(this.username);

  @override
  String toString() => 'AccountSessionExpiredException($username)';
}

/// 多账号管理服务。
///
/// 账号会话、内置浏览器 cookie、LDC/CDK 配置都必须以账号为边界。这里的
/// [_operationTail] 还负责把切换、登录前清场、后台快照串起来，避免旧账号
/// 的异步收尾在新账号上继续写状态。
class AccountManager {
  AccountManager._();
  static final AccountManager _instance = AccountManager._();
  factory AccountManager() => _instance;

  static const _registryKey = 'multi_account_registry';
  static const _snapshotPrefix = 'multi_account_snapshot_';
  static const _currentUsernameKey = 'linux_do_username';
  static const _pendingNewLoginKey = 'multi_account_pending_new_login';
  static const _guestModeKey = 'multi_account_guest_mode';

  /// 没有登录账号时使用的默认 profile。它不展示在账号列表中，只用于
  /// 保证「添加账号」开始前拥有一个干净、可恢复的 cookie/config 边界。
  static const String guestAccountId = 'guest';

  /// LDC/CDK、打赏凭证等账号级 SharedPreferences key 的统一命名规则。
  static String accountScopedKey(String key, String accountId) {
    return '$key::${Uri.encodeComponent(accountId)}';
  }

  static const Set<String> _deviceCookieNames = {'cf_clearance', '__cf_bm'};

  final _storage = ResilientSecureStorage();
  Future<void> _operationTail = Future<void>.value();

  // Storage calls are asynchronous. Keep the in-process value in sync with
  // the auth boundary so a login-success notification cannot race the guest
  // flag deletion and make CurrentUserNotifier briefly return null.
  bool? _guestModeOverride;

  /// 让所有会改动当前认证上下文的操作严格串行。
  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  // ========== 注册表 ==========

  Future<List<SavedAccount>> listAccounts() async {
    final raw = await _storage.read(key: _registryKey);
    return _decodeRegistry(raw);
  }

  List<SavedAccount> _decodeRegistry(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((e) => SavedAccount.fromJson(Map<String, dynamic>.from(e)))
          // guest 是隐藏 profile，历史版本即使写进 registry 也不能展示。
          .where((account) => account.username != guestAccountId)
          .toList(growable: false);
    } catch (e) {
      debugPrint('[AccountManager] 注册表解析失败,重置: $e');
      return const [];
    }
  }

  Future<void> _saveRegistry(List<SavedAccount> accounts) async {
    await _storage.write(
      key: _registryKey,
      value: jsonEncode(
        accounts
            .where((account) => account.username != guestAccountId)
            .map((a) => a.toJson())
            .toList(),
      ),
    );
  }

  /// 当前登录用户名（来自 DiscourseService 的存储键）。
  Future<String?> getCurrentUsername() =>
      _storage.read(key: _currentUsernameKey);

  /// 添加账号流程是否处在 guest profile。
  Future<bool> isGuestSession() async {
    final override = _guestModeOverride;
    if (override != null) return override;
    final value = await _storage.read(key: _guestModeKey);
    return value == '1';
  }

  /// 登录成功后清掉 guest 标记。幂等，冷启动 API key 回调也可以调用。
  Future<void> markLoginSucceeded() async {
    // This assignment intentionally happens before the first await. The
    // auth-state event is emitted synchronously by DiscourseService, while
    // the secure-storage cleanup below may still be in flight.
    _guestModeOverride = false;
    await _exclusive(() async {
      await Future.wait([
        _storage.delete(key: _guestModeKey),
        _storage.delete(key: _pendingNewLoginKey),
      ]);
    });
  }

  // ====== 快照 ======

  Future<Map<String, dynamic>?> _readSnapshot(String username) async {
    final raw = await _storage.read(key: '$_snapshotPrefix$username');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSnapshot(String username, Map<String, dynamic> snapshot) {
    return _storage.write(
      key: '$_snapshotPrefix$username',
      value: jsonEncode(snapshot),
    );
  }

  Future<void> _deleteSnapshot(String username) {
    return _storage.delete(key: '$_snapshotPrefix$username');
  }

  bool _isDeviceCookie(String name) {
    final lower = name.toLowerCase();
    return _deviceCookieNames.contains(lower) ||
        lower.startsWith('cf_') ||
        lower.startsWith('__cf');
  }

  /// 抓取当前 CookieJar 中所有应用域 cookie，而不是只维护几个已知名字。
  /// 这样 credit/LDC 新增的 session cookie 也会自动隔离。
  Future<List<Map<String, dynamic>>> _captureSessionCookies() async {
    final jar = CookieJarService();
    final all = await jar.loadAllCanonicalCookies();
    final captured = <Map<String, dynamic>>[];
    for (final cookie in all) {
      if (_isDeviceCookie(cookie.name) ||
          cookie.value.isEmpty ||
          cookie.value == 'del' ||
          cookie.isExpired ||
          !CookieJarService.matchesAppHost(cookie.normalizedDomain)) {
        continue;
      }
      captured.add(cookie.toJson());
    }
    return captured;
  }

  /// 抓取内置 WebView 的原始 cookie store。WebView cookie 不能依赖 jar
  /// 回读：某些 LDC/credit/AnyRouter cookie 只存在于子域或 HttpOnly store 中。
  Future<List<Map<String, dynamic>>> _captureBrowserCookies() async {
    final writer = RawCookieWriter.instance;
    if (!writer.isSupported) return const [];

    final origins = AccountBrowserSessionPolicy.snapshotOrigins.toList(
      growable: false,
    );
    final infosByOrigin = await Future.wait(
      origins.map((origin) async {
        try {
          return await writer.getAllCookieInfos(origin);
        } catch (e) {
          debugPrint('[AccountManager] 读取 $origin WebView cookie 失败: $e');
          return const <CookieFullInfo>[];
        }
      }),
    );

    final captured = <Map<String, dynamic>>[];
    final identities = <String>{};
    for (var index = 0; index < origins.length; index++) {
      final origin = origins[index];
      final infos = infosByOrigin[index];
      for (final info in infos) {
        if (_isDeviceCookie(info.name) ||
            info.name.isEmpty ||
            info.value.isEmpty ||
            _isExpired(info.expiresMillis)) {
          continue;
        }
        final originHost = Uri.parse(origin).host.toLowerCase();
        final cookieDomain = info.domain?.trim().toLowerCase();
        final identityDomain = cookieDomain == null || cookieDomain.isEmpty
            ? originHost
            : cookieDomain.startsWith('.')
            ? cookieDomain.substring(1)
            : cookieDomain;
        final identity = [
          info.name,
          identityDomain,
          info.path ?? '/',
          info.isPartitioned == true ? '1' : '0',
        ].join('|');
        if (!identities.add(identity)) continue;
        captured.add({
          'url': origin,
          'name': info.name,
          'value': info.value,
          'domain': info.domain,
          'path': info.path,
          'secure': info.isSecure,
          'http_only': info.isHttpOnly,
          'expires_at_ms': info.expiresMillis,
          'same_site': info.sameSite,
          'partitioned': info.isPartitioned,
        });
      }
    }
    return captured;
  }

  bool _isExpired(int? expiresMillis) {
    return expiresMillis != null &&
        expiresMillis > 0 &&
        expiresMillis <= DateTime.now().millisecondsSinceEpoch;
  }

  bool _cookieBelongsToOrigin(CookieFullInfo info, String origin) {
    final host = Uri.parse(origin).host.toLowerCase();
    final rawDomain = info.domain?.trim().toLowerCase();
    if (rawDomain == null || rawDomain.isEmpty) return true;
    final domain = rawDomain.startsWith('.')
        ? rawDomain.substring(1)
        : rawDomain;
    return host == domain || host.endsWith('.$domain');
  }

  /// 清掉外部账号绑定站点的用户态 cookie，再回灌目标账号快照。
  /// Cloudflare 等设备 cookie 必须保留，避免账号切换同时触发重新过盾。
  Future<void> _clearExternalBrowserSessionCookies() async {
    final writer = RawCookieWriter.instance;
    if (!writer.isSupported) return;

    for (final origin in AccountBrowserSessionPolicy.externalAccountOrigins) {
      List<CookieFullInfo> infos;
      try {
        infos = await writer.getAllCookieInfos(origin);
      } catch (e) {
        debugPrint('[AccountManager] 清理 $origin WebView cookie 前读取失败: $e');
        continue;
      }

      for (final info in infos) {
        if (_isDeviceCookie(info.name) ||
            info.name.isEmpty ||
            !_cookieBelongsToOrigin(info, origin)) {
          continue;
        }
        try {
          final deleted = await writer.deleteExactCookie(
            url: origin,
            name: info.name,
            domain: info.domain,
            path: info.path ?? '/',
          );
          if (!deleted) {
            debugPrint(
              '[AccountManager] 清理 $origin WebView cookie 失败: ${info.name}',
            );
          }
        } catch (e) {
          debugPrint(
            '[AccountManager] 清理 $origin WebView cookie ${info.name} 失败: $e',
          );
        }
      }
    }
  }

  /// 把快照里的 Cookie 写回 CookieJar。兼容旧版本的简化字段格式。
  Future<void> _restoreSessionCookies(
    List<dynamic> cookies,
    String username,
  ) async {
    final restored = <CanonicalCookie>[];
    for (final raw in cookies) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      try {
        CanonicalCookie cookie;
        if (map.containsKey('expiresAt') || map.containsKey('hostOnly')) {
          cookie = CanonicalCookie.fromJson(map);
        } else {
          final name = map['name']?.toString();
          final value = map['value']?.toString();
          if (name == null || value == null || value.isEmpty) continue;
          final expiresMs = map['expires_at_ms'];
          final expires = expiresMs is int && expiresMs > 0
              ? DateTime.fromMillisecondsSinceEpoch(expiresMs).toUtc()
              : null;
          cookie = CanonicalCookie(
            name: name,
            value: value,
            domain: map['domain']?.toString(),
            path: map['path']?.toString() ?? '/',
            expiresAt: expires,
            secure: map['secure'] != false,
            httpOnly: map['http_only'] == true,
            hostOnly: map['host_only'] == true,
            originUrl: AppConstants.baseUrl,
            source: CookieSource.manualRestore,
          );
        }
        if (_isDeviceCookie(cookie.name) ||
            cookie.value.isEmpty ||
            cookie.isExpired ||
            !CookieJarService.matchesAppHost(cookie.normalizedDomain)) {
          continue;
        }
        if (cookie.originUrl == null || cookie.originUrl!.isEmpty) {
          cookie = cookie.copyWith(originUrl: AppConstants.baseUrl);
        }
        restored.add(cookie);
      } catch (e) {
        debugPrint('[AccountManager] $username 的 cookie 解析失败: $e');
      }
    }
    await CookieJarService().restoreCanonicalCookies(restored, trusted: true);
  }

  String? _rawCookieHeader(Map<String, dynamic> cookie) {
    final name = cookie['name']?.toString();
    final value = cookie['value']?.toString();
    if (name == null || name.isEmpty || value == null || value.isEmpty) {
      return null;
    }
    final buffer = StringBuffer('$name=$value');
    final domain = cookie['domain']?.toString();
    if (domain != null && domain.isNotEmpty) buffer.write('; Domain=$domain');
    final path = cookie['path']?.toString();
    buffer.write('; Path=${path == null || path.isEmpty ? '/' : path}');
    final expires = cookie['expires_at_ms'];
    if (expires is int && expires > 0) {
      buffer.write('; Expires=${_formatHttpDate(expires)}');
    }
    if (cookie['secure'] == true) buffer.write('; Secure');
    if (cookie['http_only'] == true) buffer.write('; HttpOnly');
    final sameSite = cookie['same_site']?.toString();
    if (sameSite != null && sameSite.isNotEmpty) {
      buffer.write('; SameSite=$sameSite');
    }
    if (cookie['partitioned'] == true) buffer.write('; Partitioned');
    return buffer.toString();
  }

  String _formatHttpDate(int expiresMillis) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final date = DateTime.fromMillisecondsSinceEpoch(
      expiresMillis,
      isUtc: true,
    );
    return '${weekdays[date.weekday - 1]}, '
        '${date.day.toString().padLeft(2, '0')} '
        '${months[date.month - 1]} ${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}:'
        '${date.second.toString().padLeft(2, '0')} GMT';
  }

  Future<void> _restoreBrowserCookies(
    dynamic rawCookies,
    String username,
  ) async {
    if (rawCookies is! List) return;
    final writer = RawCookieWriter.instance;
    if (!writer.isSupported) return;
    for (final raw in rawCookies) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final url = map['url']?.toString();
      if (url == null || !_isAllowedBrowserOrigin(url)) continue;
      final header = _rawCookieHeader(map);
      if (header == null) continue;
      final ok = await writer.setRawCookie(url, header);
      if (!ok) {
        debugPrint('[AccountManager] $username 的 WebView cookie 写入失败');
      }
    }
  }

  bool _isAllowedBrowserOrigin(String url) {
    return AccountBrowserSessionPolicy.isAllowedRestoreOrigin(url);
  }

  bool _snapshotHasSessionCookie(dynamic cookies) {
    if (cookies is! List) return false;
    return cookies.any((raw) {
      if (raw is! Map) return false;
      final name = raw['name']?.toString();
      final value = raw['value']?.toString();
      return name == '_t' && value != null && value.isNotEmpty;
    });
  }

  String? _currentAvatarFor(String username) {
    final preloaded = PreloadedDataService().currentUserSync;
    if (preloaded?['username']?.toString() != username) return null;
    final avatar = preloaded?['avatar_template'];
    return avatar is String && avatar.isNotEmpty ? avatar : null;
  }

  Future<Map<String, dynamic>?> _syncCurrentAccountLocked({
    bool captureBrowserCookies = false,
  }) async {
    final generation = AuthSession().generation;
    final username = await getCurrentUsername();
    if (username == null || username.isEmpty || username == guestAccountId) {
      return null;
    }

    // 三项都是只读操作，可以同时进行。尤其完整 WebView 快照通常比
    // CookieJar/安全存储读取慢，不应让它们首尾串行阻塞切换入口。
    final cookiesFuture = _captureSessionCookies();
    final oldSnapshotFuture = _readSnapshot(username);
    final browserCookiesFuture = captureBrowserCookies
        ? _captureBrowserCookies()
        : Future<List<Map<String, dynamic>>>.value(const []);

    final cookies = await cookiesFuture;
    final oldSnapshot = await oldSnapshotFuture;
    final capturedBrowserCookies = await browserCookiesFuture;
    final browserCookies = captureBrowserCookies
        ? capturedBrowserCookies
        : oldSnapshot?['webview_cookies'];

    if (!AuthSession().isValid(generation) ||
        await getCurrentUsername() != username ||
        !_snapshotHasSessionCookie(cookies)) {
      return null;
    }

    final avatarTemplate =
        _currentAvatarFor(username) ??
        oldSnapshot?['avatar_template'] as String?;
    final savedAt = DateTime.now();
    final refreshedSnapshot = <String, dynamic>{
      'version': 2,
      'profile': username,
      'cookies': cookies,
      if (browserCookies is List) 'webview_cookies': browserCookies,
      'avatar_template': ?avatarTemplate,
      'saved_at': savedAt.toIso8601String(),
    };

    // registry 是另一把安全存储 key；读取可与 snapshot 写入重叠。
    final registryRawFuture = _storage.read(key: _registryKey);
    await _writeSnapshot(username, refreshedSnapshot);

    final accounts = [
      ..._decodeRegistry(await registryRawFuture),
    ];
    final index = accounts.indexWhere((a) => a.username == username);
    final entry = SavedAccount(
      username: username,
      avatarTemplate: avatarTemplate,
      savedAt: savedAt,
    );
    if (index >= 0) {
      accounts[index] = entry;
    } else {
      accounts.insert(0, entry);
    }
    await _saveRegistry(accounts);
    debugPrint(
      '[AccountManager] 已同步账号快照: $username '
      '(${cookies.length} jar cookies, '
      '${browserCookies is List ? browserCookies.length : 0} WebView cookies)',
    );
    return refreshedSnapshot;
  }

  // ========== 对外操作 ==========

  /// 登录成功 / 会话自愈后调用：登记当前账号并刷新快照。
  Future<void> syncCurrentAccount({bool captureBrowserCookies = false}) async {
    try {
      await _exclusive(
        () => _syncCurrentAccountLocked(
          captureBrowserCookies: captureBrowserCookies,
        ),
      );
    } catch (e) {
      debugPrint('[AccountManager] 同步当前账号失败(忽略): $e');
    }
  }

  /// 开始「添加账号」：先把当前账号快照保存下来，再切到隐藏 guest profile。
  /// pending username 写入安全存储，支持系统浏览器 API key 回调期间进程被重建。
  Future<void> prepareForNewLogin() async {
    await _exclusive(() async {
      _guestModeOverride = true;
      final current = await getCurrentUsername();
      if (current != null && current.isNotEmpty && current != guestAccountId) {
        await _storage.write(key: _pendingNewLoginKey, value: current);
        try {
          await _syncCurrentAccountLocked(captureBrowserCookies: true);
        } catch (e) {
          // 快照失败不能阻塞添加账号；guest 仍必须建立，登录完成后新账号
          // 可正常落盘，取消时则按已有快照尽力恢复。
          debugPrint('[AccountManager] 添加账号前同步快照失败(继续): $e');
        }
      } else {
        await _storage.delete(key: _pendingNewLoginKey);
      }
      await _storage.write(key: _guestModeKey, value: '1');
      await _writeSnapshot(guestAccountId, {
        'version': 2,
        'profile': guestAccountId,
        'cookies': const [],
        'webview_cookies': const [],
        'saved_at': DateTime.now().toIso8601String(),
      });

      // 这一步必须发生在打开 LoginPage / 系统浏览器之前，不能让旧 _t
      // 被 API key callback 误判成「当前账号补授权」。外部账号站点也必须
      // 清到 guest 边界，否则新账号会继承旧账号的 AnyRouter 登录态。
      await DiscourseService().detachSessionLocally();
      await _clearExternalBrowserSessionCookies();
      WebViewCookiePriming.instance.invalidate();
    });
  }

  /// 添加账号页面退出时收口。取消/失败则恢复进入添加流程前的账号。
  Future<void> completeNewLogin({required bool success}) async {
    _guestModeOverride = false;
    await _exclusive(() async {
      final previous = await _storage.read(key: _pendingNewLoginKey);
      await _storage.delete(key: _pendingNewLoginKey);
      await _storage.delete(key: _guestModeKey);
      if (success) return;

      if (previous != null && previous.isNotEmpty) {
        try {
          await _switchToAccountLocked(previous);
          return;
        } on AccountSessionExpiredException {
          await _removeAccountLocked(previous);
        }
      }
      // 登录失败可能已经留下部分 cookie，恢复 guest 的干净边界。
      await DiscourseService().detachSessionLocally();
      await _clearExternalBrowserSessionCookies();
    });
  }

  // ========== 后台快照刷新 ==========

  Timer? _autoSnapshotTimer;
  bool _autoSnapshotInFlight = false;

  /// 启动周期性后台快照刷新。
  void ensureAutoSnapshot({Duration interval = const Duration(minutes: 15)}) {
    if (_autoSnapshotTimer != null) return;
    _autoSnapshotTimer = Timer.periodic(interval, (_) {
      if (_autoSnapshotInFlight) return;
      _autoSnapshotInFlight = true;
      unawaited(
        syncCurrentAccount().whenComplete(() => _autoSnapshotInFlight = false),
      );
    });
  }

  /// 移除某个账号的本机记录与快照（登出/主动删除时调用）。
  Future<void> removeAccount(String username) async {
    if (username == guestAccountId || username.isEmpty) return;
    await _exclusive(() => _removeAccountLocked(username));
  }

  Future<void> _removeAccountLocked(String username) async {
    final accounts = [
      ..._decodeRegistry(await _storage.read(key: _registryKey)),
    ];
    accounts.removeWhere((a) => a.username == username);
    await _saveRegistry(accounts);
    await _deleteSnapshot(username);
  }

  Future<Map<String, dynamic>> _readRequiredSnapshot(String username) async {
    final snapshot = await _readSnapshot(username);
    final cookies = snapshot?['cookies'];
    if (snapshot == null ||
        cookies is! List ||
        cookies.isEmpty ||
        !_snapshotHasSessionCookie(cookies)) {
      throw AccountSessionExpiredException(username);
    }
    return snapshot;
  }

  /// 从快照恢复一个完整会话，并在提交前确认服务端返回的确实是目标账号。
  ///
  /// [detachSessionLocally] 会清空当前会话且不可逆，因此切换流程必须把
  /// 「摘除 → 回灌 → 校验 → finalize」包在可回滚的事务里。校验时禁止
  /// [DiscourseService.isLoggedIn] 直接 logout；否则一次切换窗口内的 401
  /// 会把刚保存的旧账号也一起清掉。
  Future<void> _restoreAccountSnapshotLocked(
    String username,
    Map<String, dynamic> snapshot, {
    required bool notifyAuthState,
  }) async {
    final cookies = snapshot['cookies'];
    if (cookies is! List ||
        cookies.isEmpty ||
        !_snapshotHasSessionCookie(cookies)) {
      throw AccountSessionExpiredException(username);
    }

    await DiscourseService().detachSessionLocally();
    final restoreGeneration = AuthSession().generation;

    // 外部 WebView 清理与 CookieJar 恢复分属不同存储，可以重叠执行；
    // 但目标 WebView cookie 仍必须等外部旧态清完后才能回灌，避免竞态。
    await Future.wait<void>([
      _clearExternalBrowserSessionCookies(),
      _restoreSessionCookies(cookies, username),
    ]);

    final restoredToken = await CookieJarService().getTToken();
    if (restoredToken == null || restoredToken.isEmpty) {
      throw AccountSessionExpiredException(username);
    }

    // RawCookieWriter 与 Dio 首请求触发的 WebView 会话同步共用浏览器
    // cookie store。先完整回灌再做服务端校验，避免两条写链并发造成竞态。
    await _restoreBrowserCookies(snapshot['webview_cookies'], username);

    final sessionIsValid = await DiscourseService().isLoggedIn(
      requestGeneration: restoreGeneration,
      logoutOnInvalid: false,
      expectedUsername: username,
    );
    if (!sessionIsValid) {
      throw AccountSessionExpiredException(username);
    }

    WebViewCookiePriming.instance.invalidate();
    await DiscourseService().finalizeNativeLoginSuccess(
      username,
      notifyAuthState: notifyAuthState,
    );

    // finalize 期间可能被旧请求/服务端失效信号打断；不要让这种半恢复
    // 状态提交给 UI，交给上层 catch 回滚到切换前的快照。
    final activeUsernameFuture = getCurrentUsername();
    final activeTokenFuture = CookieJarService().getTToken();
    final activeUsername = await activeUsernameFuture;
    final activeToken = await activeTokenFuture;
    if (activeUsername != username ||
        activeToken == null ||
        activeToken.isEmpty) {
      throw AccountSessionExpiredException(username);
    }
  }

  Future<void> _switchToAccountLocked(
    String username, {
    bool notifyAuthState = true,
  }) async {
    late final Map<String, dynamic> snapshot;
    try {
      snapshot = await _readRequiredSnapshot(username);
    } on AccountSessionExpiredException {
      await _removeAccountLocked(username);
      rethrow;
    }

    final current = await getCurrentUsername();
    Map<String, dynamic>? previousSnapshot;
    if (current != null && current.isNotEmpty && current != username) {
      // 先把旧账号固化到最新快照，确保目标恢复失败时仍有可回滚边界。
      // 正常路径直接复用刚写入的 Map，避免立刻再走一次安全存储读取+JSON。
      final refreshedPreviousSnapshot = await _syncCurrentAccountLocked(
        captureBrowserCookies: true,
      );
      previousSnapshot =
          refreshedPreviousSnapshot ?? await _readSnapshot(current);
    }

    var transitionStarted = false;
    try {
      transitionStarted = true;
      await _restoreAccountSnapshotLocked(
        username,
        snapshot,
        notifyAuthState: notifyAuthState,
      );
      // 目标账号已经完成服务端校验并提交；完整 WebView 快照无需阻塞切换。
      // 轻量快照排在当前事务尾部，保留 cookie/头像刷新而不延长 UI 等待。
      unawaited(syncCurrentAccount());
    } catch (error, stackTrace) {
      if (transitionStarted &&
          current != null &&
          current.isNotEmpty &&
          current != username &&
          previousSnapshot != null) {
        try {
          await _restoreAccountSnapshotLocked(
            current,
            previousSnapshot,
            // 普通切换失败时 UI 仍处于旧账号，不再额外广播一次 authState；
            // 这样不会在回滚完成前触发第二轮 currentUser 清空/刷新。
            notifyAuthState: false,
          );
        } catch (rollbackError, rollbackStackTrace) {
          debugPrint(
            '[AccountManager] 切换失败后回滚 $current 也失败: '
            '$rollbackError\n$rollbackStackTrace',
          );
        }
      }

      if (error is AccountSessionExpiredException) {
        try {
          await _removeAccountLocked(username);
        } catch (removeError) {
          debugPrint('[AccountManager] 清理过期账号 $username 失败: $removeError');
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// 切换到目标账号。
  Future<void> switchToAccount(String username) async {
    await _exclusive(
      () => _switchToAccountLocked(username, notifyAuthState: false),
    );
  }
}
