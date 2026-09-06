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
  static const _recentCaptureMaxAge = Duration(seconds: 5);

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

  Future<List<CookieFullInfo>> _readCookieInfosForSwitch(
    RawCookieWriter writer,
    String origin,
  ) async {
    // AccountManager 会在 detach 前刚刚抓取完整 WebView cookie 快照。优先复用
    // 那次成功读取，避免切换流程对同一 origin 再做一次 native/WK 枚举。
    // 若缓存缺失或已过期则保持原行为，立即读取真实 store。
    return writer.getRecentCookieInfos(
          origin,
          maxAge: _recentCaptureMaxAge,
        ) ??
        await writer.getAllCookieInfos(origin);
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
      origins.map((origin) => _readCookieInfosForSwitch(writer, origin)),
    );

    // 先按完整 cookie identity 去重。Android 随后把这些互不相同的目标合成
    // 一次 native batch；其它平台仍可安全并发删除不同 identity。
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

    final deletedCount = await writer.deleteExactCookiesBatch(
      deletions.map(
        (item) => (
          url: item.origin,
          name: item.info.name,
          domain: item.info.domain,
          path: item.info.path ?? '/',
        ),
      ),
    );
    if (deletedCount != deletions.length) {
      debugPrint(
        '[AccountSwitchCookieCleaner] selective delete incomplete: '
        '$deletedCount/${deletions.length}，回退全量清理',
      );
      return false;
    }

    // Recent-cookie cache 只是删除候选，不能作为成功依据。这里继续使用 WebView
    // 自身 CookieManager 做一次独立复检：即使快照之后页面又写入了新 cookie，
    // 也会在此处被发现并回退全量清理，账号隔离正确性不依赖缓存新鲜度。
    final manager = CookieJarService().webViewCookieManager;
    final verificationResults = await Future.wait<bool>(
      origins.map((origin) async {
        try {
          final cookies = await manager.getCookies(url: WebUri(origin));
          final residual = cookies
              .where(
                (cookie) =>
                    cookie.name.isNotEmpty && !_isDeviceCookie(cookie.name),
              )
              .length;
          if (residual > 0) {
            debugPrint(
              '[AccountSwitchCookieCleaner] $origin 仍有 '
              '$residual 个用户态 cookie，回退全量清理',
            );
            return false;
          }
          return true;
        } catch (e) {
          debugPrint(
            '[AccountSwitchCookieCleaner] $origin WebView 复检失败: $e',
          );
          return false;
        }
      }),
    );
    if (verificationResults.any((verified) => !verified)) return false;

    debugPrint(
      '[AccountSwitchCookieCleaner] selective clear ok: '
      '${deletions.length} cookies',
    );
    return true;
  }
}
