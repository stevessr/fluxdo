part of 'discourse_service.dart';

/// 账户切换专用的服务端会话校验结果。
///
/// [currentUser] 仅在 `/session/current.json` 明确返回并且能够解析为当前用户时
/// 提供。网络/CF 等不确定错误仍沿用现有保守策略视为会话可继续，但不会伪造
/// current user；调用方此时应回退到原来的 preload 收口。
class AccountSwitchSessionValidation {
  const AccountSwitchSessionValidation({
    required this.isValid,
    this.currentUser,
  });

  final bool isValid;
  final Map<String, dynamic>? currentUser;
}

extension AccountSwitchSessionValidationExtension on DiscourseService {
  /// 校验待切换快照，并把 `/session/current.json` 已经返回的 current_user
  /// 一并交给切换链路复用。
  ///
  /// 与 [isLoggedIn] 的账户切换用法保持同一语义：401/403/404 或用户名串号
  /// 才确认失败；网络/CF 异常保守保留本地会话。区别是这里不会把服务端
  /// 已经返回的 current_user 丢掉，因此后续无需再为了首屏身份等待首页 HTML。
  Future<AccountSwitchSessionValidation> validateAccountSwitchSession({
    required String expectedUsername,
    required int requestGeneration,
  }) async {
    bool isCurrent() => AuthSession().isValid(requestGeneration);

    final expected = expectedUsername.trim();
    if (expected.isEmpty || !isCurrent()) {
      return const AccountSwitchSessionValidation(isValid: false);
    }

    final initialToken = await _cookieJar.getTToken();
    if (!isCurrent() || initialToken == null || initialToken.isEmpty) {
      return const AccountSwitchSessionValidation(isValid: false);
    }

    try {
      final response = await _dio.get(
        '/session/current.json',
        queryParameters: {'_': DateTime.now().millisecondsSinceEpoch},
        options: Options(
          extra: const {'skipAuthCheck': true, 'skipCsrf': true},
        ),
      );
      if (!isCurrent()) {
        return const AccountSwitchSessionValidation(isValid: false);
      }

      final data = response.data;
      final rawCurrentUser = data is Map<String, dynamic>
          ? data['current_user']
          : null;
      if (rawCurrentUser is! Map) {
        LogWriter.instance.write({
          'timestamp': DateTime.now().toIso8601String(),
          'level': 'warning',
          'type': 'auth',
          'event': 'account_switch_session_check_failed',
          'message': '账户切换校验返回 200 但无 current_user',
          'statusCode': response.statusCode,
          'expectedUsername': expected,
        });
        return const AccountSwitchSessionValidation(isValid: false);
      }

      final currentUser = Map<String, dynamic>.from(rawCurrentUser);
      final liveUsername = currentUser['username']?.toString().trim();
      final resolvedUsername = liveUsername != null && liveUsername.isNotEmpty
          ? liveUsername
          : expected;
      if (resolvedUsername.toLowerCase() != expected.toLowerCase()) {
        LogWriter.instance.write({
          'timestamp': DateTime.now().toIso8601String(),
          'level': 'warning',
          'type': 'auth',
          'event': 'auth_session_username_mismatch',
          'message': '账户切换校验返回了非预期账号',
          'expectedUsername': expected,
          'actualUsername': resolvedUsername,
        });
        return const AccountSwitchSessionValidation(isValid: false);
      }

      // 响应可能轮换 session cookie。以拦截器已经落入 CookieJar 的最终值
      // 为准，不把请求前的旧 token 再写回内存。
      final liveToken = await _cookieJar.getTToken();
      if (!isCurrent()) {
        return const AccountSwitchSessionValidation(isValid: false);
      }
      _tToken = liveToken != null && liveToken.isNotEmpty
          ? liveToken
          : initialToken;
      _username = resolvedUsername;
      _resetStrikes();

      // 先验证模型可解析，再允许调用方跳过首页 preload。若站点字段形态变化，
      // 会自动退回旧的完整 preload 路径，而不是把半份用户对象提交给 UI。
      try {
        currentUserNotifier.value = User.fromJson(currentUser);
        return AccountSwitchSessionValidation(
          isValid: true,
          currentUser: currentUser,
        );
      } catch (e) {
        debugPrint('[AccountSwitch] current_user 解析失败，回退 preload: $e');
        return const AccountSwitchSessionValidation(isValid: true);
      }
    } on DioException catch (e) {
      if (!isCurrent()) {
        return const AccountSwitchSessionValidation(isValid: false);
      }
      final status = e.response?.statusCode;
      if (status == 401 || status == 403 || status == 404) {
        LogWriter.instance.write({
          'timestamp': DateTime.now().toIso8601String(),
          'level': 'warning',
          'type': 'auth',
          'event': 'account_switch_session_check_failed',
          'message': '账户切换校验被服务端明确拒绝',
          'statusCode': status,
          'expectedUsername': expected,
          'errorType': e.type.toString(),
        });
        return const AccountSwitchSessionValidation(isValid: false);
      }

      // 与 isLoggedIn 一致：网络异常/CF 不确定时保守保留快照，后续仍走
      // 完整 preload 收口；不会因为一次网络抖动把已保存账号删除。
      _tToken = initialToken;
      _username = expected;
      return const AccountSwitchSessionValidation(isValid: true);
    } catch (e) {
      if (!isCurrent()) {
        return const AccountSwitchSessionValidation(isValid: false);
      }
      debugPrint('[AccountSwitch] session 校验异常，保守回退 preload: $e');
      _tToken = initialToken;
      _username = expected;
      return const AccountSwitchSessionValidation(isValid: true);
    }
  }
}
