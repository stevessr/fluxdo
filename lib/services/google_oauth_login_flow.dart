import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'discourse/discourse_service.dart';
import 'network/discourse_dio.dart';
import 'network/flux_request_spec.dart';
import 'toast_service.dart';

/// Google OAuth 登录实验链路。
///
/// 目标不是在 WebView 里打开 linux.do 登录页，而是让 FluxDO 自己充当
/// Discourse OmniAuth 与系统浏览器之间的协议中间层：
///
/// 1. FluxDO 用自己的 CookieJar 获取 CSRF；
/// 2. POST /auth/google_oauth2，只接收 302，不跟随；
/// 3. 仅把 302 的 accounts.google.com 地址交给系统浏览器；
/// 4. Google 回到 https://linux.do/auth/google_oauth2/callback 时由 Android
///    App Link 抢回 FluxDO；
/// 5. FluxDO 用步骤 2 的同一 CookieJar 请求 callback，让 Discourse 在
///    App 的 CookieJar 中建立正式登录会话；
/// 6. 不跟随 callback 最后的 linux.do 页面跳转，直接检查 session 并完成
///    原生登录收口。
///
/// Google 密码、Google access token 和站点 client_secret 都不会进入 FluxDO。
/// App 只短暂持有 Google 给 Discourse 的一次性 callback code，并且该请求
/// 使用关闭网络日志的独立 Dio，避免 code/state 被写入日志。
class GoogleOAuthLoginFlow {
  GoogleOAuthLoginFlow._();

  static final GoogleOAuthLoginFlow instance = GoogleOAuthLoginFlow._();

  static const String _providerPath = '/auth/google_oauth2';
  static const String callbackPath = '/auth/google_oauth2/callback';
  static const String _pendingStateKey = 'google_oauth_pending_state';
  static const String _pendingStartedAtKey = 'google_oauth_pending_started_at';
  static const Duration _pendingTtl = Duration(minutes: 10);

  Dio? _oauthDio;
  bool _starting = false;
  bool _handlingCallback = false;

  /// LoginPage 用它在授权成功后自动关闭登录页。
  ValueChanged<bool>? onFlowFinished;

  Dio get _dio => _oauthDio ??= DiscourseDio.create(
    maxConcurrent: null,
    enableRetry: false,
    enableCfChallenge: false,
    enableNetworkLog: false,
  );

  bool isCallback(Uri uri) {
    return uri.scheme.toLowerCase() == 'https' &&
        uri.host.toLowerCase() == 'linux.do' &&
        uri.path == callbackPath;
  }

  /// 发起 Google OAuth。
  ///
  /// 目前仅在 Android 开启：AndroidManifest 已为 callback 增加 App Link。
  /// iOS 尚未配置 linux.do Associated Domains，贸然启用会让 callback 落到
  /// Safari 并展示 linux.do 页面，违反本实验的“无站点网页中转”约束。
  Future<bool> start() async {
    if (_starting) return false;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      ToastService.showError('Google 无网页中转登录目前仅支持 Android');
      return false;
    }

    _starting = true;
    try {
      // 先构造主服务，确保全局 CookieJar 等登录基础设施已经初始化。
      DiscourseService();
      await _clearPending();

      final csrf = await _fetchAnonymousCsrf();
      if (csrf == null || csrf.isEmpty) {
        ToastService.showError('无法初始化 Google 登录会话');
        return false;
      }

      final response = await _dio.post(
        _providerPath,
        data: <String, dynamic>{
          // 对齐 Discourse LoginMethod.buildPostForm()。
          'authenticity_token': csrf,
          'origin': '/',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: <String, dynamic>{'X-CSRF-Token': csrf},
          followRedirects: false,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
          extra: <String, dynamic>{
            FluxRequestKeys.skipCsrf: true,
            FluxRequestKeys.skipAuthCheck: true,
            FluxRequestKeys.skipRedirect: true,
            FluxRequestKeys.skipNetworkLog: true,
            FluxRequestKeys.skipCfChallenge: true,
            FluxRequestKeys.noRecovery: true,
            'requestTag': 'google-oauth-start',
          },
        ),
      );

      final location = response.headers.value('location');
      if (location == null || location.isEmpty) {
        ToastService.showError('Linux.do 未返回 Google 授权地址');
        return false;
      }

      final googleUri = response.requestOptions.uri.resolve(location);
      if (!_isAllowedGoogleAuthorizeUri(googleUri)) {
        debugPrint(
          '[GoogleOAuth] 拒绝非 Google OAuth 重定向: '
          '${googleUri.scheme}://${googleUri.host}${googleUri.path}',
        );
        ToastService.showError('Google 授权地址校验失败');
        return false;
      }

      final redirectUri = googleUri.queryParameters['redirect_uri'];
      if (redirectUri != null && redirectUri.isNotEmpty) {
        final parsedRedirect = Uri.tryParse(redirectUri);
        if (parsedRedirect == null || !isCallback(parsedRedirect)) {
          ToastService.showError('Google OAuth 回调地址不符合预期');
          return false;
        }
      }

      final state = googleUri.queryParameters['state'];
      if (state == null || state.isEmpty) {
        ToastService.showError('Google OAuth 缺少 state');
        return false;
      }

      await _savePending(state);

      // 初始地址已经是 accounts.google.com，因此 externalApplication 不会像
      // 直接打开 linux.do 那样被 App Link 立刻弹回 FluxDO。
      // Google 完成后回到 linux.do callback，才由我们的 callback App Link 接管。
      final launched = await launchUrl(
        googleUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        await _clearPending();
        ToastService.showError('无法打开 Google 登录');
        return false;
      }
      return true;
    } on DioException catch (e) {
      await _clearPending();
      // 不输出 requestOptions.uri：callback 链路可能带一次性 code/state。
      debugPrint(
        '[GoogleOAuth] 发起失败: status=${e.response?.statusCode}, type=${e.type}',
      );
      ToastService.showError(
        '无法直接启动 Google 登录（网络或 Cloudflare 拒绝；未打开 Linux.do 网页）',
      );
      return false;
    } catch (e) {
      await _clearPending();
      debugPrint('[GoogleOAuth] 发起失败: ${e.runtimeType}');
      ToastService.showError('Google 登录启动失败');
      return false;
    } finally {
      _starting = false;
    }
  }

  /// 处理被 App Link 截获的 Google -> linux.do callback。
  Future<void> handleCallback(Uri uri) async {
    if (!isCallback(uri) || _handlingCallback) return;

    _handlingCallback = true;
    try {
      final pending = await _loadPending();
      if (pending.state == null || pending.startedAt == null) {
        ToastService.showError('没有待处理的 Google 登录');
        _finish(false);
        return;
      }

      final startedAt = DateTime.fromMillisecondsSinceEpoch(pending.startedAt!);
      if (DateTime.now().difference(startedAt) > _pendingTtl) {
        await _clearPending();
        ToastService.showError('Google 登录已超时，请重新发起');
        _finish(false);
        return;
      }

      final callbackState = uri.queryParameters['state'];
      if (callbackState == null || callbackState != pending.state) {
        await _clearPending();
        ToastService.showError('Google 登录 state 校验失败');
        _finish(false);
        return;
      }

      final oauthError = uri.queryParameters['error'];
      if (oauthError != null && oauthError.isNotEmpty) {
        await _clearPending();
        ToastService.showError('Google 登录已取消或被拒绝');
        _finish(false);
        return;
      }

      final code = uri.queryParameters['code'];
      if (code == null || code.isEmpty) {
        await _clearPending();
        ToastService.showError('Google 回调缺少授权 code');
        _finish(false);
        return;
      }

      // 不让 Dio 跟随 Discourse callback 最终指向 / 的 302；否则会真的请求
      // linux.do 页面。这里唯一访问的是 OAuth callback HTTP endpoint。
      final response = await _dio.getUri(
        uri.replace(fragment: ''),
        options: Options(
          followRedirects: false,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
          extra: <String, dynamic>{
            FluxRequestKeys.skipCsrf: true,
            FluxRequestKeys.skipAuthCheck: true,
            FluxRequestKeys.skipRedirect: true,
            FluxRequestKeys.skipNetworkLog: true,
            FluxRequestKeys.skipCfChallenge: true,
            FluxRequestKeys.noRecovery: true,
            'requestTag': 'google-oauth-callback',
          },
        ),
      );

      await _clearPending();

      final location = response.headers.value('location');
      if (location != null && location.contains('/auth/failure')) {
        ToastService.showError('Linux.do 拒绝了 Google OAuth 回调');
        _finish(false);
        return;
      }

      final username = await _readCurrentUsername();
      if (username == null || username.isEmpty) {
        // OAuth 成功但 Discourse 未 log_on_user：典型是首次注册、站点审批、
        // OAuth 后额外 2FA 等。严格模式下不打开站点页面补流程。
        ToastService.showError(
          'Google 已完成验证，但该账号还需要在 Linux.do 完成注册或附加验证；无网页模式无法继续',
        );
        _finish(false);
        return;
      }

      await DiscourseService().finalizeNativeLoginSuccess(username);
      ToastService.showSuccess('Google 登录成功');
      _finish(true);
    } on DioException catch (e) {
      await _clearPending();
      debugPrint(
        '[GoogleOAuth] 回调失败: status=${e.response?.statusCode}, type=${e.type}',
      );
      ToastService.showError('Google OAuth 回调处理失败');
      _finish(false);
    } catch (e) {
      await _clearPending();
      debugPrint('[GoogleOAuth] 回调失败: ${e.runtimeType}');
      ToastService.showError('Google 登录完成失败');
      _finish(false);
    } finally {
      _handlingCallback = false;
    }
  }

  Future<String?> _fetchAnonymousCsrf() async {
    final response = await _dio.get(
      '/session/csrf',
      options: Options(
        extra: <String, dynamic>{
          FluxRequestKeys.skipCsrf: true,
          FluxRequestKeys.skipAuthCheck: true,
          FluxRequestKeys.skipRedirect: true,
          FluxRequestKeys.skipNetworkLog: true,
          FluxRequestKeys.skipCfChallenge: true,
          FluxRequestKeys.noRecovery: true,
          'requestTag': 'google-oauth-csrf',
        },
      ),
    );

    final data = response.data;
    if (data is Map) return data['csrf']?.toString();
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return decoded['csrf']?.toString();
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _readCurrentUsername() async {
    final response = await _dio.get(
      '/session/current.json',
      options: Options(
        extra: <String, dynamic>{
          FluxRequestKeys.skipCsrf: true,
          FluxRequestKeys.skipAuthCheck: true,
          FluxRequestKeys.skipNetworkLog: true,
          FluxRequestKeys.skipCfChallenge: true,
          FluxRequestKeys.noRecovery: true,
          'requestTag': 'google-oauth-session-check',
        },
      ),
    );

    dynamic data = response.data;
    if (data is String && data.isNotEmpty) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        return null;
      }
    }
    if (data is! Map) return null;
    final currentUser = data['current_user'];
    if (currentUser is! Map) return null;
    return currentUser['username']?.toString();
  }

  bool _isAllowedGoogleAuthorizeUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'accounts.google.com';
  }

  Future<void> _savePending(String state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingStateKey, state);
    await prefs.setInt(
      _pendingStartedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<({String? state, int? startedAt})> _loadPending() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      state: prefs.getString(_pendingStateKey),
      startedAt: prefs.getInt(_pendingStartedAtKey),
    );
  }

  Future<void> _clearPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingStateKey);
    await prefs.remove(_pendingStartedAtKey);
  }

  void _finish(bool success) {
    onFlowFinished?.call(success);
  }
}
