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
  Future<void> _captureCurrentAccountRuntime() async {
    final username = _username?.trim();
    if (username == null ||
        username.isEmpty ||
        username == AccountManager.guestAccountId) {
      return;
    }

    try {
      final token = await _cookieJar.getTToken();
      if (token == null || token.isEmpty) return;
      final cookies = await _cookieJar.loadAllCanonicalCookies();
      AccountRuntimePool.instance.save(
        username: username,
        cookies: cookies,
        sessionToken: token,
        csrfToken: _cookieSync.csrfToken,
        currentUser: currentUserNotifier.value,
      );
      debugPrint(
        '[AccountSwitch] 已缓存 native runtime: $username '
        '(${cookies.length} cookies, csrf=${_cookieSync.csrfToken != null})',
      );
    } catch (e) {
      // runtime cache 只是快路，失败必须无条件回退原来的持久化快照流程。
      debugPrint('[AccountSwitch] 缓存 native runtime 失败(继续): $e');
    }
  }

  Future<AccountNativeRuntime?> _activateCachedAccountRuntime({
    required String expectedUsername,
    required String restoredSessionToken,
  }) async {
    final runtime = AccountRuntimePool.instance.findMatching(
      expectedUsername,
      restoredSessionToken,
    );
    if (runtime == null) return null;

    // AccountManager 已经把磁盘快照回灌到 jar。这里切回进程内 runtime 时先
    // 保存这份状态作为异常回退，再用 runtime 中更新过的 cookie 覆盖；CF
    // cookie 属于设备态，不在 runtime 中，始终保留当前最新值。
    final fallbackCookies = await _cookieJar.loadAllCanonicalCookies();
    final cfClearanceCookie = await _cookieJar.getCfClearanceCookie();
    try {
      await _cookieJar.cookieJar.deleteAll();
      await _cookieJar.restoreCanonicalCookies(runtime.cookies, trusted: true);
      if (cfClearanceCookie != null) {
        await _cookieJar.restoreCfClearance(cfClearanceCookie);
      }

      final liveToken = await _cookieJar.getTToken();
      if (liveToken == null ||
          liveToken.isEmpty ||
          liveToken != runtime.sessionToken) {
        throw StateError('runtime session token restore mismatch');
      }

      await _cookieSync.reset();
      final cachedCsrf = runtime.csrfToken;
      if (cachedCsrf != null && cachedCsrf.isNotEmpty) {
        _cookieSync.setCsrfToken(cachedCsrf);
      }
      _tToken = liveToken;
      _username = runtime.username;

      final cachedUser = runtime.currentUser;
      if (cachedUser != null &&
          cachedUser.username.toLowerCase() == expectedUsername.toLowerCase()) {
        currentUserNotifier.value = cachedUser;
      }
      return runtime;
    } catch (e) {
      debugPrint('[AccountSwitch] native runtime 激活失败，回退磁盘快照: $e');
      try {
        await _cookieJar.cookieJar.deleteAll();
        await _cookieJar.restoreCanonicalCookies(
          fallbackCookies,
          trusted: true,
        );
        if (cfClearanceCookie != null) {
          await _cookieJar.restoreCfClearance(cfClearanceCookie);
        }
      } catch (rollbackError) {
        debugPrint(
          '[AccountSwitch] native runtime 回退 cookie 失败: $rollbackError',
        );
      }
      return null;
    }
  }

  /// 多账号切换专用的本地摘除。
  ///
  /// 与 [detachSessionLocally] 的认证内存/后台服务边界完全一致，但 WebView
  /// 不再无条件 `deleteAllCookies()`：先清 CookieJar，再选择性删除 app-owned
  /// origins 的用户态 cookie 并独立复检。任何失败都会自动回退原来的全量
  /// WebView 清理，因此快路不会降低账号隔离强度。
  Future<void> detachSessionForAccountSwitch() async {
    // 在推进 generation/清空 cookie 之前保存当前账号的进程内 runtime。
    // 持久化快照仍是恢复真源；runtime 只负责连续切换的低延迟快路。
    await _captureCurrentAccountRuntime();
    AuthSession().advance();

    MessageBusService().stopAll();
    unawaited(CfClearanceRefreshService().stop());
    WebViewAdapterSettingsService.instance.resetSessionFallback();
    CfChallengeService().resetSessionCompatibilityDecision();
    CfClearanceAuthority.instance.reset();

    try {
      _clearPreviousTTokenFallback();
      _tToken = null;
      _username = null;
      _cachedUserSummary = null;
      _cachedUserSummaryUsername = null;
      _userSummaryCacheTime = null;
      await _enqueueUsernameStorage(
        () => _storage.delete(key: DiscourseService._usernameKey),
      );
      _credentialsLoaded = false;
      WebViewSessionCookieRefreshService.instance.resetSessionState();
      WebViewCookiePriming.instance.invalidate();

      await _cookieSync.reset();
      final cfClearanceCookie = await _cookieJar.getCfClearanceCookie();

      var selectiveClearOk = false;
      try {
        // 只清 native CookieJar；WebView 由选择性清理器处理。
        await _cookieJar.cookieJar.deleteAll();
        if (cfClearanceCookie != null) {
          await _cookieJar.restoreCfClearance(cfClearanceCookie);
        }
        selectiveClearOk = await AccountSwitchBrowserCookieCleaner.instance
            .clearAppUserCookies();
      } catch (e) {
        debugPrint('[AccountSwitch] selective detach 失败，回退全量清理: $e');
      }

      if (!selectiveClearOk) {
        // 与原 detachSessionLocally 的旧路径等价：native + WebView 全量清理，
        // 然后恢复 native cf_clearance。后续 AccountManager 仍会清 external origin。
        await _cookieJar.clearAll();
        if (cfClearanceCookie != null) {
          await _cookieJar.restoreCfClearance(cfClearanceCookie);
        }
        debugPrint('[AccountSwitch] WebView cookie 使用全量清理兜底');
      }

      PreloadedDataService().reset();
    } finally {
      currentUserNotifier.value = null;
      _resetStrikes();
    }
  }

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

    // 快路：磁盘快照的 _t 与进程内 runtime 一致时，优先恢复 runtime 中
    // 最新的 cookie/CSRF/currentUser。短窗口内它刚作为活跃账号运行过，可
    // 直接复用那次有效性结论，省掉重复的 /session/current.json；超过窗口
    // 仍保留 runtime 状态，但继续走下面的服务端校验。
    final cachedRuntime = await _activateCachedAccountRuntime(
      expectedUsername: expected,
      restoredSessionToken: initialToken,
    );
    if (!isCurrent()) {
      return const AccountSwitchSessionValidation(isValid: false);
    }
    if (cachedRuntime != null) {
      final cachedUser = cachedRuntime.currentUser;
      final cachedUserMatches =
          cachedUser != null &&
          cachedUser.username.toLowerCase() == expected.toLowerCase();
      if (cachedUserMatches && cachedRuntime.canReuseValidation()) {
        _resetStrikes();
        LogWriter.instance.write({
          'timestamp': DateTime.now().toIso8601String(),
          'level': 'info',
          'type': 'auth',
          'event': 'account_switch_runtime_reused',
          'message': '账户切换复用进程内 native runtime，跳过重复 session 校验',
          'expectedUsername': expected,
          'runtimeAgeMs': DateTime.now()
              .difference(cachedRuntime.capturedAt)
              .inMilliseconds,
        });
        return AccountSwitchSessionValidation(
          isValid: true,
          currentUser: {'username': cachedUser.username},
        );
      }
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
      final rawCurrentUser = data is Map ? data['current_user'] : null;
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

  /// 提交一个已经完成 cookie 回灌与服务端校验的账号切换。
  ///
  /// 普通登录的 [onLoginSuccess] 会登记 guest 状态并排入一次完整 WebView
  /// 多账号快照；账户切换本身已经持有目标快照，紧接着还会排一轮轻量刷新，
  /// 再走那条通用路径只会让下一次连续切换被完整快照挡在串行队列后面。
  /// 因此这里仅提交当前认证上下文与必要的浏览器 session bootstrap。
  Future<bool> commitAccountSwitchSession({
    required String username,
    required int requestGeneration,
    required bool notifyAuthState,
  }) async {
    if (!AuthSession().isValid(requestGeneration)) return false;

    final token = await _cookieJar.getTToken();
    if (!AuthSession().isValid(requestGeneration) ||
        token == null ||
        token.isEmpty) {
      return false;
    }

    await saveUsername(username, requestGeneration: requestGeneration);
    if (!AuthSession().isValid(requestGeneration)) return false;

    setToken(token);
    AuthIssueNoticeService.instance.clearSessionCookieRepairHint();

    final forceBrowserSessionSync = !WebViewSessionCookieRefreshService.instance
        .hasFreshSyncForToken(token);
    WebViewSessionCookieRefreshService.instance.ensureInBackground(
      reason: 'account_switch_success',
      force: forceBrowserSessionSync,
    );

    if (notifyAuthState) _authStateController.add(null);
    return true;
  }
}
