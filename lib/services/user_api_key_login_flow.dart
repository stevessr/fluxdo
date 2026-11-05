import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'discourse/discourse_service.dart';
import '../models/user.dart';
import 'auth_session.dart';
import 'account_manager.dart';
import 'local_notification_service.dart' show navigatorKey;
import 'login_token_redeemer.dart';
import 'network/cookie/cookie_jar_service.dart';
import 'network/flux_request_spec.dart';
import 'network/exceptions/api_exception.dart';
import 'toast_service.dart';
import 'user_api_key_service.dart';
import 'system_browser_service.dart';

import 'package:m3e_ui/m3e_ui.dart';

/// 浏览器授权登录流程编排
///
/// 发起:登录页按钮 → [start] 拉起系统浏览器打开 /user-api-key/new。
/// 回程:系统浏览器授权后 302 到 discourse://auth_redirect,OS 深链拉回 App,
/// DeepLinkService 分发到 [handleCallback]:
/// 1. 解密 payload,校验 nonce(key 先暂存,供本流程兑换)
/// 2. App 无登录态时,用随行 OTP 兑换 _t(纯 dio,走主 dio 的 rhttp 通道过 CF),
///    再走 finalizeNativeLoginSuccess 完成与密码登录一致的收口(预加载 → 广播)
/// 3. 收口后 key 用完即焚(burnAfterLoginIfUseless):scopes 无 write 时该 key
///    是永久零权限凭据,立即 revoke+清除;开了 write 的站点则保留作 _t 自愈
///
/// 全程无可见 WebView / WebView 适配器:OTP 兑换的 CSRF 与 POST 都走主 dio,
/// 过 CF 靠 rhttp 的 Chrome TLS 指纹 + CfChallengeInterceptor 失效兜底。
///
/// 冷启动回调(App 被杀后从浏览器深链拉起)同样成立——流程不依赖登录页存活。
class UserApiKeyLoginFlow {
  UserApiKeyLoginFlow._();
  static final UserApiKeyLoginFlow instance = UserApiKeyLoginFlow._();

  /// 流程完成回调(仅 UI 用途:登录页借此 pop 自己),参数=是否成功
  ValueChanged<bool>? onFlowFinished;

  bool _handling = false;

  /// A pending OTP from a new login takes precedence over a stale local _t.
  static bool isSupplementalAuthorization({
    required String? existingToken,
    required String? otp,
    required bool guestSession,
  }) =>
      existingToken != null &&
      existingToken.isNotEmpty &&
      (otp == null || otp.isEmpty) &&
      !guestSession;

  /// Revocation is a post-login security cleanup, not a login prerequisite.
  /// The current session and navigation must become ready first.
  void _burnKeyInBackground(
    UserApiKeyService keys,
    Dio dio, {
    required String? authorizedKey,
  }) {
    if (authorizedKey == null || authorizedKey.isEmpty) return;
    unawaited(
      keys.burnAfterLoginIfUseless(dio, expectedKey: authorizedKey).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        debugPrint('[UserApiKeyLoginFlow] 授权 key 后台清理失败: $error');
      }),
    );
  }

  OverlayEntry? _loadingEntry;

  /// 深链回到 App 后,兑换+收口这段有网络耗时(可能还含 CF 验证),
  /// 用全局 overlay 给用户一个"正在完成登录"的反馈,避免看起来卡死。
  void _showLoading(String message) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    _loadingEntry?.remove();
    _loadingEntry = OverlayEntry(
      builder: (_) => _AuthLoadingOverlay(message: message),
    );
    overlay.insert(_loadingEntry!);
  }

  void _hideLoading() {
    _loadingEntry?.remove();
    _loadingEntry = null;
  }

  /// 构建授权 URL 并拉起系统浏览器。返回是否成功拉起。
  /// 首次调用会懒生成 RSA 密钥对(isolate,可能耗时数秒)。
  Future<bool> start({LoginBrowser? browser}) async {
    final authorizeUrl = await UserApiKeyService().buildAuthorizeUrl();
    try {
      // 指定安装的浏览器可以复用对应 profile 的 OAuth 提供商 cookie。
      // 指定 Android 包名也可绕开 linux.do App Links 导致的回弹。
      if (browser != null) {
        return await SystemBrowserService.instance.open(browser, authorizeUrl);
      }
      // 兼容旧入口调用。新登录页面总是先让用户手动选择。
      final mode = Platform.isAndroid
          ? LaunchMode.inAppBrowserView
          : LaunchMode.externalApplication;
      return await launchUrl(authorizeUrl, mode: mode);
    } catch (e) {
      debugPrint('[UserApiKeyLoginFlow] 拉起浏览器失败: $e');
      return false;
    }
  }

  /// 处理 discourse://auth_redirect 深链回调(由 DeepLinkService 分发)
  Future<void> handleCallback(Uri uri) async {
    if (_handling) return;
    _handling = true;
    var requestGeneration = AuthSession().generation;
    try {
      final userApiKeyService = UserApiKeyService();
      final result = await userApiKeyService.handleAuthRedirect(
        uri,
        requestGeneration: requestGeneration,
      );
      if (!AuthSession().isValid(requestGeneration)) return;
      // 冷启动 getInitialLink 会重放上次的 auth_redirect 深链;非本次授权流程
      // (nonce 已消费/不匹配)静默忽略,不弹 toast、不通知登录页。
      if (result.stale) {
        debugPrint('[UserApiKeyLoginFlow] 忽略残留授权回调');
        return;
      }
      if (!result.ok) {
        ToastService.showError('授权回调解析失败,请重新授权');
        onFlowFinished?.call(false);
        return;
      }
      // Bind cleanup to this callback's exact key, not any later login.
      final authorizedKey = await userApiKeyService.readApiKey();
      if (!AuthSession().isValid(requestGeneration)) return;

      // 登录页启动的 User API Key 授权是登录意图。旧代码只凭本地还有
      // _t 就当成"补授权"返回，造成 OTP 不兑换、新账号不会切换。
      // 如果有随回调签发的 OTP，必须尝试完成这次明确的登录。
      if (!AuthSession().isValid(requestGeneration)) return;
      final existingToken = await CookieJarService().getTToken();
      if (!AuthSession().isValid(requestGeneration)) return;
      final otp = result.otp;
      if (existingToken != null && existingToken.isNotEmpty) {
        final guestSession = await AccountManager().isGuestSession();
        if (!AuthSession().isValid(requestGeneration)) return;
        if (guestSession && otp != null) {
          // 兼容从旧版本升级或 guest 清理不完全的账户添加过程。
          await DiscourseService().detachSessionLocally();
          requestGeneration = AuthSession().generation;
        } else if (isSupplementalAuthorization(
          existingToken: existingToken,
          otp: otp,
          guestSession: guestSession,
        )) {
          // 无随行 OTP 的回调只能补授权，不能假装切换了账户。
          _burnKeyInBackground(
            userApiKeyService,
            DiscourseService().dio,
            authorizedKey: authorizedKey,
          );
          ToastService.showSuccess('授权成功（当前账号未切换）');
          onFlowFinished?.call(false);
          return;
        }
      }

      // 使用本次授权返回的 OTP 兑换新会话；无 OTP 不能确认登录。
      if (otp == null) {
        await userApiKeyService.burnAfterLoginIfUseless(DiscourseService().dio);
        ToastService.showError('授权成功,但未收到登录令牌,请重试');
        onFlowFinished?.call(false);
        return;
      }

      final completed = await _finishOtpLogin(
        otp: otp,
        requestGeneration: requestGeneration,
        userApiKeyService: userApiKeyService,
        authorizedKey: authorizedKey,
      );
      if (completed != null) onFlowFinished?.call(completed);
    } finally {
      _handling = false;
    }
  }

  /// The device flow must explicitly mint an OTP using its short-lived write
  /// Key before reaching here. Reuse browser auth's session finalization.
  Future<bool> completeDeviceOtp(
    String otp, {
    required int requestGeneration,
    required String expectedUsername,
  }) async {
    if (_handling || !AuthSession().isValid(requestGeneration)) return false;
    _handling = true;
    try {
      return await _finishOtpLogin(
            otp: otp,
            requestGeneration: requestGeneration,
            userApiKeyService: UserApiKeyService(),
            expectedUsername: expectedUsername,
          ) ==
          true;
    } finally {
      _handling = false;
    }
  }

  Future<bool?> _finishOtpLogin({
    required String otp,
    required int requestGeneration,
    required UserApiKeyService userApiKeyService,
    String? authorizedKey,
    String? expectedUsername,
  }) async {
    // 兑换 + 收口有网络耗时,显示全局 loading 反馈
    _showLoading('正在完成登录…');
    try {
      final service = DiscourseService();
      final redeemResult = await LoginTokenRedeemer.redeemUserApiKeyOtp(
        service.dio,
        otp,
        requestGeneration: requestGeneration,
      );
      if (!AuthSession().isValid(requestGeneration)) return null;
      final token = redeemResult.token;
      if (token == null) {
        if (redeemResult.challengeBlocked) {
          // 盾不是 OTP/Key 失效。不要在这里焚毁刚拿到的 key，也不要把
          // 用户误导成“令牌兑换失败”；重新授权时同 client_id 会自然替换旧 key。
          ToastService.showError('安全验证未完成,登录凭证未按失效处理,请重新尝试授权');
          return false;
        }
        if (authorizedKey != null) {
          await userApiKeyService.burnAfterLoginIfUseless(
            service.dio,
            expectedKey: authorizedKey,
          );
        }
        ToastService.showError('登录令牌兑换失败,请重试');
        return false;
      }

      // 新 _t 已落 jar;取 username 后走与密码登录同一套收口
      var username = '';
      User? verifiedUser;
      var currentUserBlockedByChallenge = false;
      try {
        final response = await service.dio.get(
          '/session/current.json',
          options: Options(
            extra: const {
              FluxRequestKeys.skipAuthCheck: true,
              FluxRequestKeys.skipCsrf: true,
              FluxRequestKeys.skipSessionStateSync: true,
              FluxRequestKeys.noRecovery: true,
            },
          ),
        );
        if (!AuthSession().isValid(requestGeneration)) return null;
        final data = response.data;
        final currentUser = data is Map<String, dynamic>
            ? data['current_user']
            : null;
        if (currentUser is Map<String, dynamic>) {
          username = currentUser['username']?.toString() ?? '';
          if (username.isNotEmpty) {
            try {
              verifiedUser = User.fromJson(currentUser);
            } catch (e) {
              debugPrint('[UserApiKeyLoginFlow] 用户资料解析失败，保留已确认用户名: $e');
            }
          }
        }
      } on DioException catch (e) {
        currentUserBlockedByChallenge =
            e.error is CfChallengeException ||
            LoginTokenRedeemer.isChallengeError(e);
        debugPrint('[UserApiKeyLoginFlow] 取 current_user 失败: $e');
      } catch (e) {
        debugPrint('[UserApiKeyLoginFlow] 取 current_user 失败: $e');
      }

      if (username.isEmpty) {
        // `_t` 已经成功兑换，后续 current_user 只是为了拿本地显示用户名。
        // 如果这里仅仅被盾挡住，不能把一个已建立的登录会话回滚成“登录失败”。
        // 扫码登录已有同样的保守兜底：先用占位 identifier 收口，后续正常
        // 会话请求/预加载会刷新真实用户信息。
        if (currentUserBlockedByChallenge) {
          if (!AuthSession().isValid(requestGeneration)) return null;
          await service.finalizeNativeLoginSuccess(
            expectedUsername ?? 'user',
            notifyBeforePreload: true,
          );
          _burnKeyInBackground(
            userApiKeyService,
            service.dio,
            authorizedKey: authorizedKey,
          );
          ToastService.showSuccess('登录成功');
          return true;
        }
        // _t 已落 jar 但确认请求失败;不带空用户名走收口(会写坏本地状态)
        if (authorizedKey != null) {
          await userApiKeyService.burnAfterLoginIfUseless(
            service.dio,
            expectedKey: authorizedKey,
          );
        }
        ToastService.showError('登录状态确认失败,请重试');
        return false;
      }

      if (expectedUsername != null &&
          username.toLowerCase() != expectedUsername.toLowerCase()) {
        ToastService.showError('设备授权用户与 OTP 会话用户不一致，已终止登录');
        return false;
      }
      if (!AuthSession().isValid(requestGeneration)) return null;
      await service.finalizeNativeLoginSuccess(
        username,
        confirmedUser: verifiedUser,
        notifyBeforePreload: true,
      );
      // 认证状态、登录页导航先于耗时的远程 key revoke 完成。
      _burnKeyInBackground(
        userApiKeyService,
        service.dio,
        authorizedKey: authorizedKey,
      );
      ToastService.showSuccess('登录成功');
      return true;
    } finally {
      _hideLoading();
    }
  }
}

/// 授权收口期间的全局 loading 遮罩(经 navigatorKey overlay 插入)
class _AuthLoadingOverlay extends StatelessWidget {
  const _AuthLoadingOverlay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LoadingSpinner(),
                const SizedBox(height: 16),
                Text(message, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
