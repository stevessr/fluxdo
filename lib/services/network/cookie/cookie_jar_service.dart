import 'dart:convert';
import 'dart:io' as io;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:crypto/crypto.dart';
import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../../../config/discourse_instance_runtime.dart';
import '../../../constants.dart';
import '../../windows_webview_environment_service.dart';
import 'cookie_logger.dart';
import 'cookie_value_codec.dart';
import 'strategy/platform_cookie_strategy.dart';

export 'cookie_value_codec.dart';

/// 统一的 Cookie 管理服务。
///
/// CookieJar 是 cookie 的唯一存储：
/// - Dio Set-Cookie 响应直接写入（hostOnly 100% 正确）
/// - WebView 边界同步通过 [BoundarySyncService] 写入
/// - Dio 请求通过 [loadForRequest] 加载
class CookieJarService {
  static final CookieJarService _instance = CookieJarService._internal();
  factory CookieJarService() => _instance;
  CookieJarService._internal();

  CookieJar? _cookieJar;
  bool _initialized = false;
  Future<void>? _initializeFuture;
  late final PlatformCookieStrategy _strategy;

  /// Discourse 论坛登录 session(仅 _t / _forum_session)。
  /// 这些是 Discourse 内核约定的 cookie 名,
  /// 用于 boundary_sync_service / webview_login_page / 诊断接口的
  /// "Discourse 登录态"判断, 不应混入其他业务 cookie。
  static const Set<String> sessionCookieNames = {'_t', '_forum_session'};

  /// 登录收口需要同步的核心 cookie 集合。
  ///
  /// 额外由页面脚本/服务端风控产生的 cookie 不在这里按名字维护，
  /// 由 WebViewSessionCookieRefreshService 加载页面后统一同步。
  static const Set<String> authCookieNames = {...sessionCookieNames};

  /// 主域 host-only cookie。
  static const Set<String> hostOnlyCookieNames = {...authCookieNames};

  /// WV 必须保持与 jar 同步的关键 cookie 集合。
  ///
  /// 标准 Discourse 仅包含登录 cookie + cf_clearance。linux.do 的 LDC session
  /// 是站点私有扩展，不能泄漏到其他实例的同步/诊断策略中。
  static Set<String> get criticalCookieNames => {
    ...authCookieNames,
    'cf_clearance',
    if (DiscourseInstanceRuntime.isDefaultInstance)
      'linux_do_credit_session_id',
  };

  CookieManager get webViewCookieManager =>
      WindowsWebViewEnvironmentService.instance.cookieManager;

  /// 获取 CookieJar 实例（用于 Dio CookieManager）
  CookieJar get cookieJar {
    if (_cookieJar == null) {
      throw StateError(
        'CookieJarService not initialized. Call initialize() first.',
      );
    }
    return _cookieJar!;
  }

  bool get isInitialized => _initialized;

  /// 初始化 CookieJar（应用启动时调用）。
  ///
  /// 默认 linux.do 继续使用历史 `.cookies` 目录；自定义实例使用独立目录，
  /// 因而即使两个 Discourse 共用 host、只靠 relative-url-root 区分，也不会
  /// 在磁盘层互相覆盖 `_t` / `_forum_session`。初始化本身也做 Future 去重，
  /// 避免 main isolate / 后台任务并发创建两个 store。
  Future<void> initialize() {
    return _initializeFuture ??= _initializeInternal();
  }

  Future<void> _initializeInternal() async {
    if (_initialized) return;

    // main() 会并行启动 User-Agent / Cookie / CSRF。先恢复实例再决定存储路径，
    // 否则自定义实例冷启动存在偶发打开 linux.do cookie 仓库的竞态。
    await AppConstants.initDiscourseInstanceRuntime();

    try {
      final directory = await getApplicationDocumentsDirectory();
      final cookiePath = _cookieStoragePath(directory.path);

      final cookieDir = io.Directory(cookiePath);
      if (!await cookieDir.exists()) {
        await cookieDir.create(recursive: true);
      }

      _cookieJar = EnhancedPersistCookieJar(
        ignoreExpires: false,
        store: FileCookieStore(cookiePath),
      );

      _initialized = true;
      _strategy = PlatformCookieStrategy.create();
      debugPrint('[CookieJar] Initialized with path: $cookiePath');
    } catch (e) {
      debugPrint(
        '[CookieJar] Failed to create persistent storage, using memory: $e',
      );
      _cookieJar = CookieJar();
      _initialized = true;
      _strategy = PlatformCookieStrategy.create();
    }

    await _migrateSessionCookiesToHostOnly();
  }

  static String _cookieStoragePath(String documentsPath) {
    if (DiscourseInstanceRuntime.isDefaultInstance) {
      return path.join(documentsPath, '.cookies');
    }
    final namespace = sha256
        .convert(
          utf8.encode(
            '${DiscourseInstanceRuntime.instanceId}\n${AppConstants.baseUrl}',
          ),
        )
        .toString();
    return path.join(documentsPath, '.cookies_instances', namespace);
  }

  @visibleForTesting
  static String debugCookieStoragePath(String documentsPath) =>
      _cookieStoragePath(documentsPath);

  /// 历史脏数据迁移: 把 authCookieNames 收敛成主域 host-only 单副本。
  Future<void> _migrateSessionCookiesToHostOnly() async {
    await enforceAuthCookiePolicy(reason: 'legacy_migration');
  }

  /// 强制登录态 cookie 的站点单例策略。
  ///
  /// `_t` / `_forum_session` 在当前实例仓库内只保留一份 canonical cookie。
  /// root-mounted linux.do 继续固定 path=/；relative-url-root 实例则固定到自身
  /// base path，避免 WebView 中同 host 的其他 Discourse 子目录共享认证 cookie。
  Future<int> enforceAuthCookiePolicy({
    String reason = 'unknown',
    Iterable<String>? names,
  }) async {
    if (!_initialized) await initialize();

    final jar = _cookieJar;
    if (jar is! EnhancedPersistCookieJar) return 0;

    try {
      final baseUri = Uri.parse(AppConstants.baseUrl);
      final baseHost = baseUri.host.toLowerCase();
      final targetNames = (names ?? hostOnlyCookieNames)
          .where(hostOnlyCookieNames.contains)
          .toSet();
      if (targetNames.isEmpty) return 0;

      final all = await jar.readAllCookies();
      var changed = 0;

      for (final name in targetNames) {
        final candidates = all
            .where(
              (cookie) =>
                  cookie.name == name &&
                  matchesAppHost(cookie.normalizedDomain ?? cookie.domain),
            )
            .toList(growable: false);
        if (candidates.isEmpty) continue;

        final active = candidates
            .where(_isActiveAuthCookieCandidate)
            .toList(growable: false);
        if (active.isEmpty) {
          final removed = await jar.replaceByNameForSite(
            baseUri,
            name,
            const [],
          );
          if (removed > 0) {
            changed++;
            debugPrint(
              '[CookieJar] Auth cookie policy removed $name variants: '
              'reason=$reason removed=$removed',
            );
          }
          continue;
        }

        final winner = _selectBestAuthCookie(active, baseHost);
        final normalized = _normalizeAuthCookie(winner, baseUri);

        if (candidates.length == 1 &&
            _isCanonicalAuthCookie(candidates.single, normalized, baseHost)) {
          continue;
        }

        final removed = await jar.replaceByNameForSite(baseUri, name, [
          normalized,
        ]);
        changed++;
        debugPrint(
          '[CookieJar] Auth cookie policy normalized $name: '
          'reason=$reason candidates=${candidates.length} removed=$removed '
          'domain=${normalized.domain} path=${normalized.path} '
          'hostOnly=${normalized.hostOnly} len=${normalized.value.length}',
        );
      }

      return changed;
    } catch (e) {
      debugPrint('[CookieJar] Auth cookie policy failed: $e');
      return 0;
    }
  }

  bool _isActiveAuthCookieCandidate(CanonicalCookie cookie) {
    if (cookie.value.isEmpty || cookie.value == 'del') return false;
    return !cookie.isExpired;
  }

  CanonicalCookie _selectBestAuthCookie(
    List<CanonicalCookie> cookies,
    String baseHost,
  ) {
    final sorted = [...cookies]
      ..sort((a, b) => _compareAuthCookie(a, b, baseHost));
    return sorted.first;
  }

  int _compareAuthCookie(
    CanonicalCookie a,
    CanonicalCookie b,
    String baseHost,
  ) {
    final scoreDiff = _authCookieScore(
      b,
      baseHost,
    ).compareTo(_authCookieScore(a, baseHost));
    if (scoreDiff != 0) return scoreDiff;

    final versionDiff = b.version.compareTo(a.version);
    if (versionDiff != 0) return versionDiff;

    final aExpires = a.expiresAt;
    final bExpires = b.expiresAt;
    if (aExpires != null && bExpires != null && aExpires != bExpires) {
      return bExpires.compareTo(aExpires);
    }
    if (aExpires != null || bExpires != null) {
      return aExpires == null ? 1 : -1;
    }

    final createdDiff = b.creationTime.compareTo(a.creationTime);
    if (createdDiff != 0) return createdDiff;

    return b.value.length.compareTo(a.value.length);
  }

  int _authCookieScore(CanonicalCookie cookie, String baseHost) {
    var score = 0;
    final normalizedDomain = cookie.normalizedDomain;
    if (normalizedDomain == baseHost) score += 100000;
    if (cookie.hostOnly) score += 50000;
    if (cookie.path == _canonicalAuthPath(Uri.parse(AppConstants.baseUrl))) {
      score += 25000;
    }
    if (cookie.secure) score += 5000;
    if (cookie.httpOnly) score += 5000;
    return score;
  }

  static String _canonicalAuthPath(Uri baseUri) {
    final raw = baseUri.path;
    if (raw.isEmpty || raw == '/') return '/';
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  CanonicalCookie _normalizeAuthCookie(CanonicalCookie source, Uri baseUri) {
    final baseHost = baseUri.host.toLowerCase();
    return CanonicalCookie(
      name: source.name,
      value: source.value,
      domain: baseHost,
      path: _canonicalAuthPath(baseUri),
      expiresAt: source.expiresAt,
      maxAge: source.maxAge,
      secure: source.secure || baseUri.scheme == 'https',
      httpOnly: source.httpOnly || authCookieNames.contains(source.name),
      sameSite: source.sameSite,
      hostOnly: true,
      persistent: source.persistent,
      creationTime: source.creationTime,
      lastAccessTime: source.lastAccessTime,
      priority: source.priority,
      sameParty: source.sameParty,
      sourceScheme: source.sourceScheme,
      sourcePort: source.sourcePort,
      partitionKey: source.partitionKey,
      partitioned: source.partitioned,
      originUrl: AppConstants.baseUrl,
      source: source.source,
      version: source.version,
      lastSyncedToWebViewAt: source.lastSyncedToWebViewAt,
      lastSyncedFromWebViewAt: source.lastSyncedFromWebViewAt,
      rawSetCookie: null,
    );
  }

  bool _isCanonicalAuthCookie(
    CanonicalCookie cookie,
    CanonicalCookie normalized,
    String baseHost,
  ) {
    return cookie.value == normalized.value &&
        cookie.hostOnly &&
        cookie.normalizedDomain == baseHost &&
        cookie.path == normalized.path &&
        cookie.secure == normalized.secure &&
        cookie.httpOnly == normalized.httpOnly &&
        cookie.rawSetCookie == null;
  }

  // ---------------------------------------------------------------------------
  // 单个 Cookie 操作
  // ---------------------------------------------------------------------------

  Future<String?> getCookieValue(String name) async {
    if (!_initialized) await initialize();

    try {
      final uri = Uri.parse(AppConstants.baseUrl);
      final cookies = await _cookieJar!.loadForRequest(uri);
      for (final cookie in cookies) {
        if (cookie.name == name) {
          final value = CookieValueCodec.decode(cookie.value);
          if (value.isNotEmpty) return value;
        }
      }
    } catch (e) {
      debugPrint('[CookieJar] Failed to get cookie $name: $e');
    }
    return null;
  }

  Future<List<CanonicalCookie>> loadCanonicalCookiesForRequest(Uri uri) async {
    if (!_initialized) await initialize();
    final jar = _cookieJar;
    if (jar is EnhancedPersistCookieJar) {
      return jar.loadCanonicalForRequest(uri);
    }
    final cookies = await _cookieJar!.loadForRequest(uri);
    return cookies
        .map(
          (cookie) => CanonicalCookie(
            name: cookie.name,
            value: CookieValueCodec.decode(cookie.value),
            domain: cookie.domain,
            path: cookie.path ?? '/',
            expiresAt: cookie.expires?.toUtc(),
            maxAge: cookie.maxAge,
            secure: cookie.secure,
            httpOnly: cookie.httpOnly,
            hostOnly: cookie.domain == null || cookie.domain!.trim().isEmpty,
            persistent: cookie.expires != null || cookie.maxAge != null,
            originUrl: uri.toString(),
          ),
        )
        .toList(growable: false);
  }

  Future<CanonicalCookie?> getCanonicalCookie(String name) async {
    if (!_initialized) await initialize();
    final uri = Uri.parse(AppConstants.baseUrl);
    final cookies = await loadCanonicalCookiesForRequest(uri);
    for (final cookie in cookies) {
      if (cookie.name == name) return cookie;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getCookieDiagnosticsForRequest(
    Uri uri, {
    Iterable<String>? names,
  }) async {
    final normalizedNames = names
        ?.map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    final cookies = await loadCanonicalCookiesForRequest(uri);
    final diagnostics = cookies
        .where(
          (cookie) =>
              normalizedNames == null || normalizedNames.contains(cookie.name),
        )
        .map(
          (cookie) => {
            'name': cookie.name,
            'domain': cookie.domain,
            'normalizedDomain': cookie.normalizedDomain,
            'path': cookie.path,
            'hostOnly': cookie.hostOnly,
            'valueLength': cookie.value.length,
            'secure': cookie.secure,
            'httpOnly': cookie.httpOnly,
            'persistent': cookie.persistent,
            'source': cookie.source.name,
            'originUrl': cookie.originUrl,
            'originHost': Uri.tryParse(cookie.originUrl ?? '')?.host,
          },
        )
        .toList(growable: false);

    diagnostics.sort((a, b) {
      final nameA = a['name']?.toString() ?? '';
      final nameB = b['name']?.toString() ?? '';
      final nameCompare = nameA.compareTo(nameB);
      if (nameCompare != 0) return nameCompare;
      final pathA = a['path']?.toString().length ?? 0;
      final pathB = b['path']?.toString().length ?? 0;
      return pathB.compareTo(pathA);
    });
    return diagnostics;
  }

  Future<List<Map<String, dynamic>>> getSessionCookieDiagnosticsForRequest({
    Uri? uri,
  }) {
    return getCookieDiagnosticsForRequest(
      uri ?? Uri.parse(AppConstants.baseUrl),
      names: sessionCookieNames,
    );
  }

  Future<List<Map<String, dynamic>>> getAuthCookieDiagnosticsForRequest({
    Uri? uri,
  }) {
    return getCookieDiagnosticsForRequest(
      uri ?? Uri.parse(AppConstants.baseUrl),
      names: authCookieNames,
    );
  }

  Future<List<CanonicalCookie>> loadAllCanonicalCookies() async {
    if (!_initialized) await initialize();
    final jar = _cookieJar;
    if (jar is EnhancedPersistCookieJar) return jar.readAllCookies();
    return const [];
  }

  Future<void> restoreCanonicalCookies(
    Iterable<CanonicalCookie> cookies, {
    bool trusted = true,
  }) async {
    if (!_initialized) await initialize();
    final jar = _cookieJar;
    if (jar is! EnhancedPersistCookieJar) {
      for (final cookie in cookies) {
        final uri =
            Uri.tryParse(cookie.originUrl ?? '') ??
            Uri.parse(AppConstants.baseUrl);
        await jar?.saveFromResponse(uri, [cookie.toIoCookie()]);
      }
      return;
    }

    final grouped = <Uri, List<CanonicalCookie>>{};
    for (final cookie in cookies) {
      final uri =
          Uri.tryParse(cookie.originUrl ?? '') ??
          Uri.parse(AppConstants.baseUrl);
      grouped.putIfAbsent(uri, () => []).add(cookie);
    }
    for (final entry in grouped.entries) {
      await jar.saveCanonicalCookies(entry.key, entry.value, trusted: trusted);
    }
    await enforceAuthCookiePolicy(reason: 'account_snapshot_restore');
  }

  Future<void> setCookie(
    String name,
    String value, {
    String? url,
    String? domain,
    String? path,
    DateTime? expires,
    bool secure = true,
    bool httpOnly = false,
    bool trusted = false,
  }) async {
    if (!_initialized) await initialize();

    try {
      final uri =
          Uri.tryParse(url ?? AppConstants.baseUrl) ??
          Uri.parse(AppConstants.baseUrl);
      final cookie = io.Cookie(name, value)
        ..path = path ?? '/'
        ..secure = secure
        ..httpOnly = httpOnly;
      final normalizedDomain = domain?.trim();
      if (normalizedDomain != null && normalizedDomain.isNotEmpty) {
        cookie.domain = normalizedDomain;
      }
      if (expires != null) cookie.expires = expires;

      final jar = _cookieJar;
      if (trusted && jar is EnhancedPersistCookieJar) {
        await jar.saveFromResponseTrusted(uri, [cookie], trusted: true);
      } else {
        await _cookieJar!.saveFromResponse(uri, [cookie]);
      }
      if (hostOnlyCookieNames.contains(name)) {
        await enforceAuthCookiePolicy(reason: 'setCookie', names: {name});
      }
    } catch (e) {
      debugPrint('[CookieJar] Failed to set cookie $name: $e');
    }
  }

  Future<void> deleteCookie(String name) async {
    if (!_initialized) await initialize();

    try {
      final uri = Uri.parse(AppConstants.baseUrl);
      final jar = _cookieJar;
      if (jar is EnhancedPersistCookieJar) {
        await jar.deleteByName(uri, name);
      } else {
        final expired = DateTime.now().subtract(const Duration(days: 1));
        final hosts = await getKnownHostsForDomain(uri.host);
        for (final host in hosts) {
          final hostUri = uri.replace(host: host, path: '/');
          final cookies = await _cookieJar!.loadForRequest(hostUri);
          final expiredCookies = <io.Cookie>[];
          for (final cookie in cookies) {
            if (cookie.name == name) {
              final expired0 = io.Cookie(name, '')
                ..path = cookie.path ?? '/'
                ..expires = expired;
              if (cookie.domain != null) expired0.domain = cookie.domain;
              expiredCookies.add(expired0);
            }
          }
          if (expiredCookies.isNotEmpty) {
            await _cookieJar!.saveFromResponse(hostUri, expiredCookies);
          }
        }
      }
      CookieLogger.delete(name: name, source: 'deleteCookie');
    } catch (e) {
      debugPrint('[CookieJar] Failed to delete cookie $name: $e');
    }
  }

  Future<void> reloadPersistedCookies() async {
    if (!_initialized) return;
    final jar = _cookieJar;
    if (jar is! EnhancedPersistCookieJar) return;
    try {
      await jar.reloadPersistedCookies();
    } catch (e) {
      debugPrint('[CookieJar] Failed to reload cookies from disk: $e');
    }
  }

  Future<void> clearAll() async {
    if (!_initialized) await initialize();
    try {
      final baseHost = Uri.parse(AppConstants.baseUrl).host;
      final knownHosts = await getKnownHostsForDomain(baseHost);
      await _cookieJar!.deleteAll();
      await _strategy.clearWebViewCookies(webViewCookieManager, knownHosts);
      for (final name in authCookieNames) {
        await _deleteWebViewCookieVariants(name, knownHosts);
      }
      CookieLogger.delete(name: '*', source: 'clearAll');
    } catch (e) {
      debugPrint('[CookieJar] Failed to clear cookies: $e');
    }
  }

  Future<void> deleteWebViewCookie(String name) async {
    if (!_initialized) await initialize();
    try {
      final baseHost = Uri.parse(AppConstants.baseUrl).host;
      final hosts = await getKnownHostsForDomain(baseHost);
      await _deleteWebViewCookieVariants(name, hosts);
    } catch (e) {
      debugPrint('[CookieJar] Failed to delete WebView cookie $name: $e');
    }
  }

  Future<void> _deleteWebViewCookieVariants(
    String name,
    Set<String> hosts,
  ) async {
    final base = Uri.parse(AppConstants.baseUrl);
    final cookiePaths = <String>{'/', _canonicalAuthPath(base)};
    for (final host in hosts) {
      final url = WebUri(base.replace(host: host, path: '/').toString());
      for (final domain in <String?>{null, host, '.$host'}) {
        for (final cookiePath in cookiePaths) {
          try {
            await webViewCookieManager.deleteCookie(
              url: url,
              name: name,
              domain: domain,
              path: cookiePath,
            );
          } catch (e) {
            debugPrint(
              '[CookieJar] Failed to delete WebView cookie $name for host=$host domain=$domain path=$cookiePath: $e',
            );
          }
        }
      }
    }
  }

  Future<String?> getTToken() => getCookieValue('_t');

  Future<Map<String, dynamic>> getTTokenDiagnostics() async {
    if (!_initialized) await initialize();
    try {
      final uri = Uri.parse(AppConstants.baseUrl);
      final cookies = await _cookieJar!.loadForRequest(uri);
      final tCookies = cookies.where((c) => c.name == '_t').toList();
      return {
        'count': tCookies.length,
        'variants': tCookies
            .map(
              (c) => {
                'domain': c.domain,
                'path': c.path,
                'len': c.value.length,
                'hasPrefix': c.value.startsWith(CookieValueCodec.prefix),
              },
            )
            .toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<String?> getCfClearance() => getCookieValue('cf_clearance');

  Future<io.Cookie?> getCfClearanceCookie() async {
    if (!_initialized) await initialize();
    try {
      final uri = Uri.parse(AppConstants.baseUrl);
      final cookies = await _cookieJar!.loadForRequest(uri);
      for (final cookie in cookies) {
        if (cookie.name == 'cf_clearance') return cookie;
      }
    } catch (e) {
      debugPrint('[CookieJar] Failed to get cf_clearance cookie: $e');
    }
    return null;
  }

  Future<void> restoreCfClearance(io.Cookie cookie) async {
    if (!_initialized) await initialize();
    try {
      final uri = Uri.parse(AppConstants.baseUrl);
      await _cookieJar!.saveFromResponse(uri, [cookie]);
    } catch (e) {
      debugPrint('[CookieJar] Failed to restore cf_clearance: $e');
    }
  }

  Future<String?> getCookieHeader() async {
    return getCookieHeaderForRequest(Uri.parse(AppConstants.baseUrl));
  }

  Future<String?> getCookieHeaderForRequest(Uri uri) async {
    if (!_initialized) await initialize();
    try {
      final cookies = await _cookieJar!.loadForRequest(uri);
      return buildCookieHeaderForRequest(cookies, uri);
    } catch (e) {
      debugPrint('[CookieJar] Failed to get cookie header for $uri: $e');
      return null;
    }
  }

  @visibleForTesting
  static String? buildCookieHeaderForRequest(List<io.Cookie> cookies, Uri uri) {
    if (cookies.isEmpty) return null;
    final header = _selectCookiesForHeader(
      cookies,
      uri,
    ).map((c) => '${c.name}=${CookieValueCodec.decode(c.value)}').join('; ');
    return header.isEmpty ? null : header;
  }

  static List<io.Cookie> _selectCookiesForHeader(
    List<io.Cookie> cookies,
    Uri uri,
  ) {
    final requestHost = uri.host.toLowerCase();
    final selected = <String, io.Cookie>{};
    for (final cookie in cookies) {
      final isHostOnlyAuth = hostOnlyCookieNames.contains(cookie.name);
      if (isHostOnlyAuth && requestHost != appBaseHost) continue;
      final key = isHostOnlyAuth
          ? cookie.name
          : '${cookie.name}|${cookie.path ?? '/'}';
      final existing = selected[key];
      if (existing == null ||
          _compareHeaderCookiePriority(cookie, existing, requestHost) > 0) {
        selected[key] = cookie;
      }
    }
    return selected.values.toList()..sort((a, b) {
      final pathCompare = (b.path?.length ?? 0).compareTo(a.path?.length ?? 0);
      if (pathCompare != 0) return pathCompare;
      return _compareHeaderCookiePriority(b, a, requestHost);
    });
  }

  static int _compareHeaderCookiePriority(
    io.Cookie candidate,
    io.Cookie existing,
    String requestHost,
  ) {
    final scoreDiff =
        _headerCookiePriorityScore(candidate, requestHost) -
        _headerCookiePriorityScore(existing, requestHost);
    if (scoreDiff != 0) return scoreDiff;

    final candidateExpires = candidate.expires;
    final existingExpires = existing.expires;
    if (candidateExpires != null &&
        existingExpires != null &&
        candidateExpires != existingExpires) {
      return candidateExpires.compareTo(existingExpires);
    }
    if ((candidateExpires == null) != (existingExpires == null)) {
      return candidateExpires != null ? 1 : -1;
    }
    return candidate.value.length.compareTo(existing.value.length);
  }

  static int _headerCookiePriorityScore(io.Cookie cookie, String requestHost) {
    final normalizedDomain = cookie.domain?.trim().toLowerCase().replaceFirst(
      RegExp(r'^\.'),
      '',
    );
    final isHostOnlyAuth = hostOnlyCookieNames.contains(cookie.name);
    final canonicalPath = _canonicalAuthPath(Uri.parse(AppConstants.baseUrl));
    final isCanonicalPath = cookie.path == null
        ? canonicalPath == '/'
        : cookie.path == canonicalPath;

    var score = 0;
    if (normalizedDomain == null || normalizedDomain.isEmpty) {
      score = 10000;
    } else if (normalizedDomain == requestHost) {
      score = 9000 + normalizedDomain.length;
    } else if (requestHost.endsWith('.$normalizedDomain')) {
      score = 1000 + normalizedDomain.length;
    } else {
      score = normalizedDomain.length;
    }

    if (isHostOnlyAuth) {
      if (requestHost == appBaseHost) score += 2000;
      if (isCanonicalPath) score += 1500;
      if (cookie.httpOnly) score += 250;
      if (cookie.secure) score += 250;
    }
    return score;
  }

  Future<Set<String>> getKnownHostsForDomain(String baseDomain) async {
    if (!_initialized) await initialize();
    final rootDomain = baseDomain.toLowerCase().replaceFirst(
      RegExp(r'^\.'),
      '',
    );
    final hosts = <String>{rootDomain};

    // 这些是 linux.do 私有子服务；通用 Discourse 不能凭命名猜测并清理
    // credit./cdk./connect.，否则可能误伤用户同域下完全无关的应用。
    if (DiscourseInstanceRuntime.isDefaultInstance) {
      hosts.addAll({
        'credit.$rootDomain',
        'cdk.$rootDomain',
        'connect.$rootDomain',
      });
    }

    final jar = _cookieJar;
    if (jar is EnhancedPersistCookieJar) {
      try {
        final cookies = await jar.readAllCookies();
        for (final cookie in cookies) {
          final d = cookie.normalizedDomain;
          if (d != null &&
              d.isNotEmpty &&
              (d == rootDomain ||
                  (DiscourseInstanceRuntime.isDefaultInstance &&
                      d.endsWith('.$rootDomain')))) {
            hosts.add(d);
          }
        }
      } catch (e) {
        debugPrint('[CookieJar] Failed to scan related hosts: $e');
      }
    }

    return hosts;
  }

  static String? normalizeWebViewCookieDomain(String? rawDomain) {
    final trimmed = rawDomain?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.startsWith('.') ? trimmed.substring(1) : trimmed;
  }

  static DateTime? parseWebViewCookieExpires(int? rawExpiresDate) {
    if (rawExpiresDate == null || rawExpiresDate <= 0) return null;
    final normalizedMillis = rawExpiresDate < 100000000000
        ? rawExpiresDate * 1000
        : rawExpiresDate;
    return DateTime.fromMillisecondsSinceEpoch(normalizedMillis);
  }

  static bool isCriticalCookie(String name) =>
      criticalCookieNames.contains(name);

  static String get appBaseHost =>
      Uri.parse(AppConstants.baseUrl).host.toLowerCase();

  static bool matchesAppHost(String? domain) {
    final baseHost = appBaseHost;
    final normalized = domain?.trim().replaceFirst(RegExp(r'^\.'), '');
    if (normalized == null || normalized.isEmpty) return true;
    final lower = normalized.toLowerCase();
    if (lower == baseHost) return true;
    return DiscourseInstanceRuntime.isDefaultInstance &&
        lower.endsWith('.$baseHost');
  }

  Future<String?> readCookieValueFromController(
    InAppWebViewController controller,
    String name, {
    String? currentUrl,
  }) async {
    if (!io.Platform.isWindows) return null;

    try {
      final rawCookies = await _readWindowsCookiesFromController(
        controller,
        currentUrl: currentUrl,
      );
      String? fallback;
      for (final raw in rawCookies) {
        final cookieName = raw['name']?.toString();
        final value = raw['value']?.toString() ?? '';
        final domain = raw['domain']?.toString();
        if (cookieName != name || value.isEmpty) continue;
        if (matchesAppHost(domain)) return value;
        fallback ??= value;
      }
      return fallback;
    } catch (e) {
      debugPrint('[CookieJar][Windows] Failed to read live cookie $name: $e');
      return null;
    }
  }

  Future<int> syncCriticalCookiesFromController(
    InAppWebViewController controller, {
    String? currentUrl,
    Set<String>? cookieNames,
    Set<String>? excludeCookieNames,
    Map<String, String>? acceptValues,
    bool trusted = false,
    required Future<bool> Function(String name, String value) shouldSyncCookie,
  }) async {
    if (!io.Platform.isWindows) return 0;
    if (!_initialized) await initialize();

    try {
      final uri =
          Uri.tryParse(currentUrl ?? AppConstants.baseUrl) ??
          Uri.parse(AppConstants.baseUrl);
      final rawCookies = await _readWindowsCookiesFromController(
        controller,
        currentUrl: currentUrl,
      );
      final filtered = <Map<String, dynamic>>[];
      for (final raw in rawCookies) {
        final name = raw['name']?.toString();
        final value = raw['value']?.toString() ?? '';
        if (name == null || value.isEmpty) continue;
        if (cookieNames != null && !cookieNames.contains(name)) continue;
        if (excludeCookieNames != null && excludeCookieNames.contains(name)) {
          continue;
        }
        final onlyValue = acceptValues?[name];
        if (onlyValue != null && value != onlyValue) continue;
        if (!matchesAppHost(raw['domain']?.toString())) continue;
        if (!await shouldSyncCookie(name, value)) continue;
        filtered.add(raw);
      }

      if (filtered.isEmpty) return 0;

      final jar = _cookieJar;
      if (jar is EnhancedPersistCookieJar) {
        final remaining = [...filtered];
        if (trusted && acceptValues?['cf_clearance'] != null) {
          final verified = filtered
              .where((raw) => raw['name'] == 'cf_clearance')
              .map(
                (raw) => CdpCookieParser.parse(raw, originUrl: uri.toString()),
              )
              .whereType<CanonicalCookie>()
              .toList();
          if (verified.isNotEmpty) {
            await jar.replaceByNameForSite(uri, 'cf_clearance', verified);
            remaining.removeWhere((raw) => raw['name'] == 'cf_clearance');
          }
        }
        await jar.saveFromCdpCookies(uri, remaining, trusted: trusted);
        final authNames = filtered
            .map((raw) => raw['name']?.toString())
            .whereType<String>()
            .where(hostOnlyCookieNames.contains)
            .toSet();
        if (authNames.isNotEmpty) {
          await enforceAuthCookiePolicy(
            reason: 'windows_cdp_sync',
            names: authNames,
          );
        }
        return filtered.length;
      }

      final toSave = <io.Cookie>[];
      for (final raw in filtered) {
        final name = raw['name']?.toString();
        final value = raw['value']?.toString() ?? '';
        if (name == null || value.isEmpty) continue;

        io.Cookie cookie;
        try {
          cookie = io.Cookie(name, value);
        } catch (_) {
          cookie = io.Cookie(name, CookieValueCodec.encode(value));
        }

        final domain = raw['domain']?.toString();
        final cookiePath = raw['path']?.toString();
        final secure = raw['secure'] == true;
        final httpOnly = raw['httpOnly'] == true;
        final expires = raw['expires'];

        if (domain != null && domain.trim().isNotEmpty) {
          cookie.domain = domain;
        }
        cookie
          ..path = cookiePath == null || cookiePath.isEmpty ? '/' : cookiePath
          ..secure = secure
          ..httpOnly = httpOnly;
        if (expires is num && expires > 0) {
          cookie.expires = DateTime.fromMillisecondsSinceEpoch(
            (expires * 1000).round(),
          );
        }
        toSave.add(cookie);
      }

      if (toSave.isEmpty) return 0;
      await _cookieJar!.saveFromResponse(uri, toSave);
      final authNames = toSave
          .map((cookie) => cookie.name)
          .where(hostOnlyCookieNames.contains)
          .toSet();
      if (authNames.isNotEmpty) {
        await enforceAuthCookiePolicy(
          reason: 'windows_controller_sync',
          names: authNames,
        );
      }
      return toSave.length;
    } catch (e) {
      debugPrint('[CookieJar][Windows] Failed to sync live cookies: $e');
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> _readWindowsCookiesFromController(
    InAppWebViewController controller, {
    String? currentUrl,
  }) async {
    final baseUri = Uri.parse(AppConstants.baseUrl);
    final hosts = await getKnownHostsForDomain(baseUri.host);
    final currentHost = Uri.tryParse(currentUrl ?? '')?.host;
    if (currentHost != null &&
        currentHost.isNotEmpty &&
        matchesAppHost(currentHost)) {
      hosts.add(currentHost);
    }

    final urls = <String>{
      AppConstants.baseUrl,
      '${AppConstants.baseUrl}/',
      if (currentUrl != null && currentUrl.isNotEmpty) currentUrl,
      for (final host in hosts) baseUri.replace(host: host, path: '').toString(),
      for (final host in hosts) baseUri.replace(host: host, path: '/').toString(),
    }.toList(growable: false);

    final result = await controller.callDevToolsProtocolMethod(
      methodName: 'Network.getCookies',
      parameters: {'urls': urls},
    );
    final rawCookies = result is Map<String, dynamic>
        ? result['cookies']
        : null;
    if (rawCookies is! List) return const [];

    return rawCookies
        .whereType<Map>()
        .map((raw) => raw.map((key, value) => MapEntry(key.toString(), value)))
        .cast<Map<String, dynamic>>()
        .where((raw) => matchesAppHost(raw['domain']?.toString()))
        .toList(growable: false);
  }
}
