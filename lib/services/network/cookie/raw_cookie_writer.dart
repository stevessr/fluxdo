import 'dart:io' as io;

import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'cookie_full_info.dart';
import 'raw_cookie_writer_fallback.dart';

typedef RawCookieWriteRequest = ({String url, String rawSetCookie});
typedef ExactCookieDeleteRequest = ({
  String url,
  String name,
  String? domain,
  String path,
});

class _RecentCookieInfoRead {
  const _RecentCookieInfoRead({
    required this.capturedAt,
    required this.cookies,
  });

  final DateTime capturedAt;
  final List<CookieFullInfo> cookies;
}

/// 通过原生平台通道写入 / 读取 / 删除 WebView cookie store。
///
/// 保留完整的 cookie 语义（host-only / domain / sameSite 等）。
///
/// v0.4.0 扩展：增加 [nukeAllVariants] / [deleteExactCookie] /
/// [getAllCookieInfos] / [countCookiesByName] 用于 Sentinel 内核（参见
/// `docs/cookie-sync-design-v0.4.0.md` §5.4）。
///
/// 平台支持矩阵:
/// - Android / iOS / macOS: native method channel `com.fluxdo/raw_cookie`
/// - Windows / Linux: Dart 层 [RawCookieWriterFallback] 包装
///   flutter_inappwebview 的 CookieManager (无需 native)
class RawCookieWriter {
  RawCookieWriter._();
  static final instance = RawCookieWriter._();

  static const _channel = MethodChannel('com.fluxdo/raw_cookie');
  static const _sharedStorageIsolatedCookieNames = {
    'cf_clearance',
    '_t',
    '_forum_session',
  };
  static const _recentCookieInfoReadLimit = 32;

  final Map<String, _RecentCookieInfoRead> _recentCookieInfoReads = {};

  /// 当前平台是否有 native method channel 实现。
  bool get _hasNativeChannel =>
      io.Platform.isAndroid || io.Platform.isIOS || io.Platform.isMacOS;

  /// 当前平台是否走 Dart fallback (flutter_inappwebview CookieManager)。
  bool get _hasDartFallback => io.Platform.isWindows || io.Platform.isLinux;

  /// 是否支持当前平台 (native 或 Dart fallback 任一可用即支持)。
  bool get isSupported => _hasNativeChannel || _hasDartFallback;

  /// 返回最近一次成功读取 [url] 时抓到的完整 cookie 信息。
  ///
  /// 这只是短流程中的性能提示，不是当前 WebView cookie store 的权威状态。
  /// 调用方必须提供一个很短的 [maxAge]，并在依赖它执行删除等破坏性操作后
  /// 用独立 API 复检。账号切换利用它复用刚刚保存账号快照时的读取结果，避免
  /// 随后清理阶段再次跨 MethodChannel/WK store 枚举同一批 cookie。
  List<CookieFullInfo>? getRecentCookieInfos(
    String url, {
    Duration maxAge = const Duration(seconds: 5),
  }) {
    if (maxAge.inMicroseconds <= 0) return null;
    final cached = _recentCookieInfoReads[url];
    if (cached == null) return null;
    if (DateTime.now().difference(cached.capturedAt) > maxAge) {
      _recentCookieInfoReads.remove(url);
      return null;
    }
    return cached.cookies;
  }

  void _rememberCookieInfoRead(String url, List<CookieFullInfo> cookies) {
    // Map 保持插入顺序。先移除再写回可让热点 URL 移到末尾，从而用一个很小的
    // 有界缓存覆盖账号切换涉及的 origins，而不会因浏览器访问任意 URL 无限增长。
    _recentCookieInfoReads.remove(url);
    if (_recentCookieInfoReads.length >= _recentCookieInfoReadLimit) {
      _recentCookieInfoReads.remove(_recentCookieInfoReads.keys.first);
    }
    _recentCookieInfoReads[url] = _RecentCookieInfoRead(
      capturedAt: DateTime.now(),
      cookies: List<CookieFullInfo>.unmodifiable(cookies),
    );
  }

  void _invalidateCookieInfoRead(String url) {
    _recentCookieInfoReads.remove(url);
  }

  void _invalidateCookieInfoReads(Iterable<String> urls) {
    for (final url in urls) {
      _invalidateCookieInfoRead(url);
    }
  }

  /// 通过原始 Set-Cookie 头字符串写入 cookie。
  ///
  /// [url] — cookie 所属的 URL（如 `https://linux.do`）
  /// [rawSetCookie] — 原始 Set-Cookie 头（如 `_t=xxx; path=/; secure; httponly`）
  ///
  /// 各平台实现：
  /// - Android: `CookieManager.setCookie(url, rawSetCookie)`
  /// - iOS/macOS: `HTTPCookie.cookies(withResponseHeaderFields:for:)` → `WKHTTPCookieStore.setCookie`
  ///   默认同时写入 `HTTPCookieStorage.shared`；[writeSharedStorage] 可关闭
  ///   shared storage 写入，用于避免 Apple 平台对特定 HttpOnly domain cookie
  ///   产生双份 WK 变体。
  ///   `cf_clearance` 会强制 WK-only 写入，防止 shared storage 与 WK store
  ///   双写后在 WebKit 中出现两个同名变体。
  /// - Linux: `soup_cookie_jar_set_cookie(jar, uri, rawSetCookie)`
  Future<bool> setRawCookie(
    String url,
    String rawSetCookie, {
    bool writeSharedStorage = true,
  }) async {
    _invalidateCookieInfoRead(url);
    final effectiveWriteSharedStorage = _effectiveSharedStorageWrite(
      url,
      rawSetCookie,
      requested: writeSharedStorage,
    );
    if (_hasDartFallback) {
      return RawCookieWriterFallback.instance.setRawCookie(
        url,
        rawSetCookie,
        writeSharedStorage: effectiveWriteSharedStorage,
      );
    }
    try {
      final result = await _channel.invokeMethod<bool>('setRawCookie', {
        'url': url,
        'rawSetCookie': rawSetCookie,
        'writeSharedStorage': effectiveWriteSharedStorage,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[RawCookieWriter] setRawCookie failed: $e');
      return false;
    } on MissingPluginException {
      debugPrint('[RawCookieWriter] Platform channel not available');
      return false;
    }
  }

  bool _effectiveSharedStorageWrite(
    String url,
    String rawSetCookie, {
    required bool requested,
  }) {
    if (!requested) return false;

    final name = _cookieNameFromRawHeader(url, rawSetCookie);
    if (name == null) return requested;
    return !_sharedStorageIsolatedCookieNames.contains(name.toLowerCase());
  }

  String? _cookieNameFromRawHeader(String url, String rawSetCookie) {
    try {
      return SetCookieParser.parse(rawSetCookie, uri: Uri.parse(url)).name;
    } catch (_) {
      final separator = rawSetCookie.indexOf('=');
      if (separator <= 0) return null;
      final name = rawSetCookie.substring(0, separator).trim();
      return name.isEmpty ? null : name;
    }
  }

  /// 批量写入同一 URL 的多个 raw Set-Cookie 头。
  Future<int> setRawCookies(String url, List<String> rawSetCookies) {
    return setRawCookiesBatch(
      rawSetCookies.map((raw) => (url: url, rawSetCookie: raw)),
    );
  }

  /// 批量写入多个 origin 的 raw Set-Cookie。
  ///
  /// Android 走一次原生 MethodChannel batch：一次性向 Chromium cookie store
  /// 发出整批 setCookie，并且只在批次尾部 flush 一次。其它平台维持原来的
  /// 串行写入语义，避免扩大 Apple/shared-storage 的行为变化范围。
  Future<int> setRawCookiesBatch(
    Iterable<RawCookieWriteRequest> cookies,
  ) async {
    final items = cookies.toList(growable: false);
    if (items.isEmpty) return 0;
    _invalidateCookieInfoReads(items.map((item) => item.url));
    if (!io.Platform.isAndroid) return _setRawCookiesSerial(items);

    try {
      final result = await _channel.invokeMethod<int>('setRawCookiesBatch', {
        'cookies': items
            .map(
              (item) => {
                'url': item.url,
                'rawSetCookie': item.rawSetCookie,
              },
            )
            .toList(growable: false),
      });
      final written = result ?? 0;
      if (written == items.length) return written;
      debugPrint(
        '[RawCookieWriter] setRawCookiesBatch incomplete '
        '$written/${items.length}, fallback serial',
      );
      return _setRawCookiesSerial(items);
    } on PlatformException catch (e) {
      debugPrint('[RawCookieWriter] setRawCookiesBatch failed, fallback: $e');
      return _setRawCookiesSerial(items);
    } on MissingPluginException {
      debugPrint(
        '[RawCookieWriter] setRawCookiesBatch unavailable, fallback serial',
      );
      return _setRawCookiesSerial(items);
    }
  }

  Future<int> _setRawCookiesSerial(List<RawCookieWriteRequest> items) async {
    var written = 0;
    for (final item in items) {
      if (await setRawCookie(item.url, item.rawSetCookie)) written++;
    }
    return written;
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 新增：Sentinel 内核所需的原语
  //
  // 原生侧实现详见 §8.4。Phase 1 阶段 Dart 通道已包装，原生侧 Phase 2 实现。
  // 待原生侧实现前，调用返回安全默认值（不抛异常）。
  // ---------------------------------------------------------------------------

  /// 暴力穷举删除指定 name 的所有变体。
  ///
  /// 仅供 Sentinel 在 Android 上"无法精确枚举变体"时使用。
  /// 对每对 `(domain, path)` 组合发出 `Max-Age=0` 删除请求。
  ///
  /// [domainCandidates] — null 表示尝试 host-only（不传 Domain 属性）
  ///
  /// 返回成功删除的变体数（best-effort，原生侧可能无法精确统计）。
  ///
  /// 验证项：V4（Android Max-Age=0 + Domain 精确匹配实测）。
  Future<int> nukeAllVariants({
    required String url,
    required String name,
    required List<String?> domainCandidates,
    required List<String> pathCandidates,
  }) async {
    _invalidateCookieInfoRead(url);
    if (_hasDartFallback) {
      return RawCookieWriterFallback.instance.nukeAllVariants(
        url: url,
        name: name,
        domainCandidates: domainCandidates,
        pathCandidates: pathCandidates,
      );
    }
    try {
      final result = await _channel.invokeMethod<int>('nukeAllVariants', {
        'url': url,
        'name': name,
        'domainCandidates': domainCandidates,
        'pathCandidates': pathCandidates,
      });
      return result ?? 0;
    } on PlatformException catch (e) {
      debugPrint('[RawCookieWriter] nukeAllVariants failed: $e');
      return 0;
    } on MissingPluginException {
      debugPrint('[RawCookieWriter] Platform channel not available');
      return 0;
    }
  }

  /// 精确删除指定 `(name, domain, path)` 的单条 cookie 变体。
  ///
  /// iOS / macOS：`WKHTTPCookieStore.delete(HTTPCookie)` 精确匹配。
  /// Android：退化为 `nukeAllVariants` 的单组合调用（domain/path 必须与设置时一致）。
  ///
  /// 验证项：V1（iOS HTTPCookie host-only 行为）。
  Future<bool> deleteExactCookie({
    required String url,
    required String name,
    required String? domain,
    required String path,
  }) async {
    _invalidateCookieInfoRead(url);
    if (_hasDartFallback) {
      return RawCookieWriterFallback.instance.deleteExactCookie(
        url: url,
        name: name,
        domain: domain,
        path: path,
      );
    }
    try {
      final result = await _channel.invokeMethod<bool>('deleteExactCookie', {
        'url': url,
        'name': name,
        'domain': domain,
        'path': path,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[RawCookieWriter] deleteExactCookie failed: $e');
      return false;
    } on MissingPluginException {
      debugPrint('[RawCookieWriter] Platform channel not available');
      return false;
    }
  }

  /// 批量精确删除互不相同的 cookie identity。
  ///
  /// Android 把所有 `(url,name,domain,path)` 合并为一次平台调用，每个 identity
  /// 仍覆盖 plain / Secure / SameSite=None / Partitioned 四种删除头，但整批
  /// 只 flush 一次。其它平台沿用并发的单条删除，保持既有性能与行为。
  Future<int> deleteExactCookiesBatch(
    Iterable<ExactCookieDeleteRequest> cookies,
  ) async {
    final items = cookies.toList(growable: false);
    if (items.isEmpty) return 0;
    _invalidateCookieInfoReads(items.map((item) => item.url));
    if (!io.Platform.isAndroid) return _deleteExactCookiesFallback(items);

    try {
      final result = await _channel.invokeMethod<int>('deleteExactCookiesBatch', {
        'cookies': items
            .map(
              (item) => {
                'url': item.url,
                'name': item.name,
                'domain': item.domain,
                'path': item.path,
              },
            )
            .toList(growable: false),
      });
      final deleted = result ?? 0;
      if (deleted == items.length) return deleted;
      debugPrint(
        '[RawCookieWriter] deleteExactCookiesBatch incomplete '
        '$deleted/${items.length}, fallback individual deletes',
      );
      return _deleteExactCookiesFallback(items);
    } on PlatformException catch (e) {
      debugPrint(
        '[RawCookieWriter] deleteExactCookiesBatch failed, fallback: $e',
      );
      return _deleteExactCookiesFallback(items);
    } on MissingPluginException {
      debugPrint(
        '[RawCookieWriter] deleteExactCookiesBatch unavailable, fallback',
      );
      return _deleteExactCookiesFallback(items);
    }
  }

  Future<int> _deleteExactCookiesFallback(
    List<ExactCookieDeleteRequest> items,
  ) async {
    final results = await Future.wait<bool>(
      items.map(
        (item) => deleteExactCookie(
          url: item.url,
          name: item.name,
          domain: item.domain,
          path: item.path,
        ),
      ),
    );
    return results.where((deleted) => deleted).length;
  }

  /// 读取指定 url 下所有 cookie 的完整信息。
  ///
  /// 每次调用都读取真实 store，并把成功结果保留为一个很小的最近读取缓存。
  /// 缓存不会自动参与普通读取；只有显式调用 [getRecentCookieInfos] 才会复用。
  ///
  /// 平台差异：
  /// - iOS / macOS：`WKHTTPCookieStore.getAllCookies()` 返回完整字段
  /// - Android（新 WebView）：通过 `WebViewCompat.getCookieInfo` 返回完整字段
  /// - Android（旧 WebView）：仅能拿到 name + value，其它字段为 null
  ///
  /// 验证项：V12（flutter_inappwebview Android getCookies 实际行为）。
  Future<List<CookieFullInfo>> getAllCookieInfos(String url) async {
    if (_hasDartFallback) {
      final result = await RawCookieWriterFallback.instance.getAllCookieInfos(
        url,
      );
      _rememberCookieInfoRead(url, result);
      return result;
    }
    try {
      final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'getAllCookieInfos',
        {'url': url},
      );
      if (raw == null) return const [];
      final result = raw
          .map((m) {
            final map = Map<String, dynamic>.from(m);
            return CookieFullInfo(
              name: map['name'] as String? ?? '',
              value: map['value'] as String? ?? '',
              domain: map['domain'] as String?,
              path: map['path'] as String?,
              isSecure: map['isSecure'] as bool?,
              isHttpOnly: map['isHttpOnly'] as bool?,
              expiresMillis: map['expiresMillis'] as int?,
              sameSite: map['sameSite'] as String?,
              isPartitioned: map['partitioned'] as bool?,
            );
          })
          .toList(growable: false);
      _rememberCookieInfoRead(url, result);
      return result;
    } on PlatformException catch (e) {
      debugPrint('[RawCookieWriter] getAllCookieInfos failed: $e');
      return const [];
    } on MissingPluginException {
      debugPrint('[RawCookieWriter] Platform channel not available');
      return const [];
    }
  }

  /// 统计指定 url 下 cookie name 的变体数量。
  ///
  /// 在 Android 上基于 `CookieManager.getCookie(url)` 拼接字符串拆分计数。
  /// 在 iOS 上基于 `getAllCookies` 过滤。
  ///
  /// 比 [getAllCookieInfos] 更轻量，仅返回数量不返回内容。
  Future<int> countCookiesByName(String url, String name) async {
    if (_hasDartFallback) {
      return RawCookieWriterFallback.instance.countCookiesByName(url, name);
    }
    try {
      final result = await _channel.invokeMethod<int>('countCookiesByName', {
        'url': url,
        'name': name,
      });
      return result ?? 0;
    } on PlatformException catch (e) {
      debugPrint('[RawCookieWriter] countCookiesByName failed: $e');
      return 0;
    } on MissingPluginException {
      debugPrint('[RawCookieWriter] Platform channel not available');
      return 0;
    }
  }
}
