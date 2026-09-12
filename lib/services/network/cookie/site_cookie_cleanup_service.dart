import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'cookie_jar_service.dart';
import 'cookie_store_observer.dart';
import 'raw_cookie_writer.dart';
import 'strategy/platform_cookie_strategy.dart';

/// WebView 浏览器的按站点 Cookie 清理服务。
///
/// 发现范围只来自实际 Cookie 归属域、持久 CookieJar 记录以及 LINUX.DO
/// 已知服务子域，不根据“最后两段域名”猜测站点边界，避免误判 co.uk 等公共后缀。
class SiteCookieCleanupService {
  SiteCookieCleanupService._();

  static final SiteCookieCleanupService instance = SiteCookieCleanupService._();

  final CookieJarService _jar = CookieJarService();
  final PlatformCookieStrategy _strategy = PlatformCookieStrategy.create();

  Future<List<String>> discoverRelatedHosts(String currentUrl) async {
    final uri = Uri.tryParse(currentUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return const [];
    }

    if (!_jar.isInitialized) await _jar.initialize();

    final currentHost = _normalizeHost(uri.host);
    final hosts = <String>{currentHost};
    final appScoped = CookieJarService.matchesAppHost(currentHost);
    final scanHosts = <String>{currentHost};

    if (appScoped) {
      scanHosts.addAll(
        await _jar.getKnownHostsForDomain(CookieJarService.appBaseHost),
      );
    }

    for (final host in scanHosts) {
      try {
        final cookies = await _strategy.readCookiesFromWebView(
          _jar.webViewCookieManager,
          'https://$host/',
        );
        var ownsCookie = false;
        for (final cookie in cookies) {
          final owner = _cookieOwner(cookie, requestHost: host);
          if (owner == null) continue;
          if (owner == host) ownsCookie = true;
          if (_isRelatedHost(currentHost, owner, appScoped: appScoped)) {
            hosts.add(owner);
          }
        }
        if (host != currentHost && ownsCookie) hosts.add(host);
      } catch (e) {
        debugPrint('[SiteCookieCleanup] 读取 WebView Cookie 失败: host=$host error=$e');
      }
    }

    try {
      final canonicalCookies = await _jar.loadAllCanonicalCookies();
      for (final cookie in canonicalCookies) {
        final originHost = Uri.tryParse(cookie.originUrl ?? '')?.host;
        final owner = _normalizeNullableHost(
          cookie.normalizedDomain ?? originHost,
        );
        if (owner != null &&
            _isRelatedHost(currentHost, owner, appScoped: appScoped)) {
          hosts.add(owner);
        }
      }
    } catch (e) {
      debugPrint('[SiteCookieCleanup] 扫描 CookieJar 失败: $e');
    }

    final result = hosts.toList()
      ..sort((a, b) {
        if (a == currentHost) return -1;
        if (b == currentHost) return 1;
        return a.compareTo(b);
      });
    return result;
  }

  /// 同时清理 WebView store 与持久 CookieJar，防止后续 priming 把已删除
  /// Cookie 从另一侧重新灌回。
  Future<void> clearHosts(Iterable<String> rawHosts) async {
    final hosts = rawHosts
        .map(_normalizeHost)
        .where((host) => host.isNotEmpty)
        .toSet();
    if (hosts.isEmpty) return;

    if (!_jar.isInitialized) await _jar.initialize();

    final jar = _jar.cookieJar;
    if (jar is EnhancedPersistCookieJar) {
      await jar.deleteDomainsExactly(hosts);
    } else {
      for (final host in hosts) {
        await jar.delete(Uri.parse('https://$host/'));
      }
    }

    for (final host in hosts) {
      await _clearWebViewHost(host);
    }

    CookieStoreObserver.instance.notifyExternalChange();
  }

  Future<void> _clearWebViewHost(String host) async {
    final url = 'https://$host/';
    try {
      final cookies = await _strategy.readCookiesFromWebView(
        _jar.webViewCookieManager,
        url,
      );
      for (final cookie in cookies) {
        final owner = _cookieOwner(cookie, requestHost: host);
        if (owner != host) continue;

        final rawDomain = cookie.domain?.trim();
        final domain = rawDomain == null || rawDomain.isEmpty ? null : rawDomain;
        final path = cookie.path?.isNotEmpty == true ? cookie.path! : '/';

        final deleted = await RawCookieWriter.instance.deleteExactCookie(
          url: url,
          name: cookie.name,
          domain: domain,
          path: path,
        );
        if (!deleted) {
          // 原生精确删除不可用时，退回插件 CookieManager；仍只使用已枚举出的
          // exact domain/path，不做父域/子域扩张。
          await _jar.webViewCookieManager.deleteCookie(
            url: WebUri(url),
            name: cookie.name,
            domain: domain,
            path: path,
          );
        }
      }
    } catch (e) {
      debugPrint('[SiteCookieCleanup] 清理 WebView Cookie 失败: host=$host error=$e');
    }
  }

  static String? _cookieOwner(Cookie cookie, {required String requestHost}) {
    return _normalizeNullableHost(cookie.domain) ?? _normalizeHost(requestHost);
  }

  static bool _isRelatedHost(
    String currentHost,
    String candidate, {
    required bool appScoped,
  }) {
    if (candidate == currentHost) return true;
    if (appScoped && CookieJarService.matchesAppHost(candidate)) return true;
    return currentHost.endsWith('.$candidate') ||
        candidate.endsWith('.$currentHost');
  }

  static String _normalizeHost(String host) =>
      host.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');

  static String? _normalizeNullableHost(String? host) {
    if (host == null) return null;
    final normalized = _normalizeHost(host);
    return normalized.isEmpty ? null : normalized;
  }
}
