import 'dart:async';

typedef LoginPreloadedHydrator = Future<bool> Function(String html);
typedef LoginPreloadedRefresher = Future<void> Function();
typedef LoginReadyNotifier = void Function(String token);

/// 统一收口登录成功后的预加载数据准备时序。
///
/// 约束：
/// 1. 优先复用登录页已经拿到的首页 HTML 预加载数据；
/// 2. HTML 无法复用时再回退到 HTTP refresh；
/// 3. 只有预加载数据准备完成后，才广播登录成功。
class LoginReadyCoordinator {
  LoginReadyCoordinator({
    required LoginPreloadedHydrator hydrateFromHtml,
    required LoginPreloadedRefresher refreshPreloadedData,
    required LoginReadyNotifier notifyLoginReady,
  }) : _hydrateFromHtml = hydrateFromHtml,
       _refreshPreloadedData = refreshPreloadedData,
       _notifyLoginReady = notifyLoginReady;

  final LoginPreloadedHydrator _hydrateFromHtml;
  final LoginPreloadedRefresher _refreshPreloadedData;
  final LoginReadyNotifier _notifyLoginReady;

  /// API Key OTP 已经由服务器确认、CookieJar 已提交时，无需让预加载阻塞
  /// 认证态广播和 LoginPage 的导航。刷新失败只影响数据预热，不能回滚登录。
  void finalizeImmediately({
    required String token,
    void Function(Object error, StackTrace stackTrace)? onRefreshError,
  }) {
    _notifyLoginReady(token);
    unawaited(
      Future<void>.sync(_refreshPreloadedData).catchError(
        (Object error, StackTrace stackTrace) {
          onRefreshError?.call(error, stackTrace);
        },
      ),
    );
  }

  Future<bool> finalize({required String token, String? pageHtml}) async {
    var reusedPreloaded = false;
    if (pageHtml != null && pageHtml.isNotEmpty) {
      reusedPreloaded = await _hydrateFromHtml(pageHtml);
    }
    if (!reusedPreloaded) {
      await _refreshPreloadedData();
    }
    _notifyLoginReady(token);
    return reusedPreloaded;
  }
}
