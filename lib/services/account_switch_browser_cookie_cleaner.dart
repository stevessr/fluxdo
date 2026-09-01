import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'account_browser_session_policy.dart';
import 'network/cookie/cookie_full_info.dart';
import 'network/cookie/cookie_jar_service.dart';
import 'network/cookie/raw_cookie_writer.dart';

/// 多账号切换专用的 WebView cookie 快速清理器。
///
/// 普通登出仍走 CookieJarService.clearAll() 的全量清理；只有账户切换会先尝试
/// 这里的“只删账号态、保留设备态”路径。任何写入失败或验证残留都返回 false，
/// 调用方必须立即退回旧的 deleteAllCookies() 路径，不能牺牲隔离正确性。
class AccountSwitchBrowserCookieCleaner {
  AccountSwitchBrowserCookieCleaner._();
  static final instance = AccountSwitchBrowserCookieCleaner._();

  static const Set<String> _deviceCookieNames = {
    'cf_clearance',
    '__cf_bm',
  };

  bool _isDeviceCookie(String name) {
    final lower = name.toLowerCase();
    return _deviceCookieNames.contains(lower) ||
        lower.startsWith('cf_') ||
        lower.startsWith('__cf');
  }

  bool _belongsToOrigin(CookieFullInfo info, String origin) {
    final host = Uri.parse(origin).host.toLowerCase();
    final rawDomain = info.domain?.trim().toLowerCase();
    if (rawDomain == null || rawDomain.isEmpty) return true;
    final domain = rawDomain.startsWith('.')
        ? rawDomain.substring(1)
        : rawDomain;
    return host == domain || host.endsWith('.$domain');
  }

  /// 清理 app-owned origins 的用户态 WebView cookies。
  ///
  /// AnyRouter 等 external origin 仍由 AccountManager 原有逻辑处理，避免改变
  /// 第三方登录隔离边界。成功必须满足：所有删除调用成功，且随后通过插件
  /// CookieManager 复检时四个 app origin 均只剩 Cloudflare/设备态 cookies。
  Future<bool> clearAppUserCookies() async {
    final writer = RawCookieWriter.instance;
    if (!writer.isSupported) return false;

    final origins = AccountBrowserSessionPolicy.appOrigins;
    final infosByOrigin = await Future.wait(
      origins.map((origin) => writer.getAllCookieInfos(origin)),
    );

    final seen = <String>{};
    final deletions = <({String origin, CookieFullInfo info})>[];
    for (var index = 0; index < origins.length; index++) {
      final origin = origins[index];
      for (final info in infosByOrigin[index]) {
        if (info.name.isEmpty ||
            _isDeviceCookie(info.name) ||
            !_belongsToOrigin(info, origin)) {
          continue;
        }
        final host = Uri.parse(origin).host.toLowerCase();
        final rawDomain = info.domain?.trim().toLowerCase();
        final normalizedDomain = rawDomain == null || rawDomain.isEmpty
            ? host
            : rawDomain.replaceFirst(RegExp(r'^\.'), '');
        final identity = [
          info.name,
          normalizedDomain,
          info.path ?? '/',
          info.isPartitioned == true ? '1' : '0',
        ].join('|');
        if (!seen.add(identity)) continue;
        deletions.add((origin: origin, info: info));
      }
    }

    var allDeleted = true;
    for (final item in deletions) {
      try {
        final deleted = await writer.deleteExactCookie(
          url: item.origin,
          name: item.info.name,
          domain: item.info.domain,
          path: item.info.path ?? '/',
        );
        if (!deleted) allDeleted = false;
      } catch (e) {
        allDeleted = false;
        debugPrint(
          '[AccountSwitchCookieCleaner] 删除 ${item.info.name} 失败: $e',
        );
      }
    }
    if (!allDeleted) return false;

    // RawCookieWriter 的读取 API 为 best-effort，平台通道异常会返回空列表。
    // 因此成功判定不能只靠它：用 WebView 自身 CookieManager 再做一次独立
    // 复检，任何异常或残留都回退全量清理。
    final manager = CookieJarService().webViewCookieManager;
    try {
      for (final origin in origins) {
        final cookies = await manager.getCookies(url: WebUri(origin));
        final residual = cookies.where(
          (cookie) =>
              cookie.name.isNotEmpty && !_isDeviceCookie(cookie.name),
        );
        if (residual.isNotEmpty) {
          debugPrint(
            '[AccountSwitchCookieCleaner] $origin 仍有 '
            '${residual.length} 个用户态 cookie，回退全量清理',
          );
          return false;
        }
      }
    } catch (e) {
      debugPrint('[AccountSwitchCookieCleaner] WebView 复检失败: $e');
      return false;
    }

    debugPrint(
      '[AccountSwitchCookieCleaner] selective clear ok: '
      '${deletions.length} cookies',
    );
    return true;
  }
}
