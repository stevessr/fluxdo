import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import 'auth_session.dart';
import 'discourse/discourse_service.dart';
import 'network/cookie/boundary_sync_service.dart';
import 'network/cookie/webview_cookie_priming.dart';
import 'toast_service.dart';
import 'webview_settings.dart';

/// Google OAuth 无 Linux.do 可见网页中转链路。
///
/// Linux.do 的匿名 CSRF / OmniAuth bootstrap / callback 都由隐藏的浏览器
/// WebView 网络栈完成，以保持浏览器 TLS 指纹并复用 cf_clearance；系统浏览器
/// 只会真正展示 accounts.google.com。Google 回调由 Android App Link 抢回 App
/// 后，也在隐藏 WebView 中请求 callback，并在最终 Linux.do 页面导航发生前取消，
/// 然后把 _t / _forum_session / cf_clearance 同步回 CookieJar。
class GoogleOAuthLoginFlow {
  GoogleOAuthLoginFlow._();

  static final GoogleOAuthLoginFlow instance = GoogleOAuthLoginFlow._();

  static const String _providerPath = '/auth/google_oauth2';
  static const String callbackPath = '/auth/google_oauth2/callback';
  static const String _pendingStateKey = 'google_oauth_pending_state';
  static const String _pendingStartedAtKey = 'google_oauth_pending_started_at';
  static const Duration _pendingTtl = Duration(minutes: 10);
  static const Duration _browserTimeout = Duration(seconds: 30);

  bool _starting = false;
  bool _handlingCallback = false;

  /// LoginPage 用它在授权成功后自动关闭登录页。
  ValueChanged<bool>? onFlowFinished;

  bool isCallback(Uri uri) {
    return uri.scheme.toLowerCase() == 'https' &&
        uri.host.toLowerCase() == 'linux.do' &&
        uri.path == callbackPath;
  }

  Future<bool> start() async {
    if (_starting) return false;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      ToastService.showError('Google 无网页中转登录目前仅支持 Android');
      return false;
    }

    _starting = true;
    try {
      // 确保登录相关单例已构造；CookieJar 本身在 main() 阶段已经初始化。
      DiscourseService();
      await _clearPending();

      final googleUri = await _bootstrapProviderWithBrowser();
      if (!_isAllowedGoogleAuthorizeUri(googleUri)) {
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

      // 只把 Google 页面交给系统浏览器。Linux.do 的两端都由隐藏浏览器栈处理。
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
    } on TimeoutException {
      await _clearPending();
      ToastService.showError('Google 登录初始化超时，请重试');
      return false;
    } catch (e) {
      await _clearPending();
      // 不输出 URI / query，避免 state 或 callback code 进入日志。
      debugPrint('[GoogleOAuth] 浏览器 bootstrap 失败: ${e.runtimeType}');
      ToastService.showError(
        '无法初始化 Google 登录会话（隐藏浏览器网络栈未通过 Cloudflare）',
      );
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

      final username = await _completeCallbackWithBrowser(
        uri.replace(fragment: ''),
      );
      await _clearPending();

      if (username == null || username.isEmpty) {
        ToastService.showError(
          'Google 已完成验证，但该账号还需要在 Linux.do 完成注册或附加验证；无网页模式无法继续',
        );
        _finish(false);
        return;
      }

      await DiscourseService().finalizeNativeLoginSuccess(username);
      ToastService.showSuccess('Google 登录成功');
      _finish(true);
    } on TimeoutException {
      await _clearPending();
      ToastService.showError('Google OAuth 回调处理超时');
      _finish(false);
    } catch (e) {
      await _clearPending();
      // callback URI 含一次性 code，绝不打印它。
      debugPrint('[GoogleOAuth] 浏览器 callback 失败: ${e.runtimeType}');
      ToastService.showError('Google OAuth 回调处理失败');
      _finish(false);
    } finally {
      _handlingCallback = false;
    }
  }

  /// 隐藏 WebView：同源 fetch CSRF 后，用真实 form POST 导航到 OmniAuth。
  /// 捕获服务端指向 accounts.google.com 的主框架导航并立即 CANCEL，因此用户
  /// 不会看到 Linux.do 页面，也不会在隐藏 WebView 中加载 Google 登录页。
  Future<Uri> _bootstrapProviderWithBrowser() async {
    final generation = AuthSession().generation;
    await WebViewCookiePriming.instance.prime(AppConstants.baseUrl);

    var pageLoaded = Completer<void>();
    final googleRedirect = Completer<Uri>();
    InAppWebViewController? controller;
    HeadlessInAppWebView? headless;

    void fail(Object error) {
      if (!googleRedirect.isCompleted) googleRedirect.completeError(error);
    }

    try {
      headless = HeadlessInAppWebView(
        initialSettings: _oauthHeadlessSettings(),
        initialUserScripts: WebViewSettings.compatPolyfillScripts,
        onReceivedServerTrustAuthRequest: (_, challenge) =>
            WebViewSettings.handleServerTrustAuthRequest(challenge),
        onWebViewCreated: (c) {
          controller = c;
          c.addJavaScriptHandler(
            handlerName: 'googleOAuthBootstrapResult',
            callback: (args) {
              final raw = args.isNotEmpty ? args.first : null;
              if (raw is Map && raw['ok'] != true) {
                final phase = raw['phase']?.toString() ?? 'unknown';
                final status = raw['status']?.toString() ?? '0';
                fail(StateError('OAuth bootstrap failed: $phase/$status'));
              }
              return null;
            },
          );
        },
        shouldOverrideUrlLoading: (c, action) async {
          final raw = action.request.url?.toString();
          final target = raw == null ? null : Uri.tryParse(raw);
          if (target == null) return NavigationActionPolicy.ALLOW;

          if (_isAllowedGoogleAuthorizeUri(target)) {
            if (!googleRedirect.isCompleted) googleRedirect.complete(target);
            return NavigationActionPolicy.CANCEL;
          }

          if (_isLinuxDo(target) && target.path.startsWith('/auth/failure')) {
            fail(StateError('Linux.do rejected Google OAuth bootstrap'));
            return NavigationActionPolicy.CANCEL;
          }

          return NavigationActionPolicy.ALLOW;
        },
        onLoadStop: (c, url) {
          if (!pageLoaded.isCompleted) pageLoaded.complete();
          final target = Uri.tryParse(url?.toString() ?? '');
          if (target != null && _isAllowedGoogleAuthorizeUri(target)) {
            if (!googleRedirect.isCompleted) googleRedirect.complete(target);
            c.stopLoading();
          }
        },
        onReceivedError: (c, request, error) {
          if (request.isForMainFrame != false &&
              !pageLoaded.isCompleted &&
              !googleRedirect.isCompleted) {
            pageLoaded.completeError(
              StateError('OAuth WebView init failed: ${error.type}'),
            );
          }
        },
      );

      await headless.run();
      controller = headless.webViewController;
      final c = controller;
      if (c == null) throw StateError('OAuth headless WebView unavailable');

      // HeadlessInAppWebView.run() 自身可能产生一次 load 回调，重新建 gate。
      pageLoaded = Completer<void>();
      await c.loadData(
        data: '<!DOCTYPE html><html><head><meta charset="utf-8"></head><body></body></html>',
        baseUrl: WebUri(AppConstants.baseUrl),
        mimeType: 'text/html',
        encoding: 'utf-8',
      );
      await pageLoaded.future.timeout(_browserTimeout);

      final providerUrl = '${AppConstants.baseUrl}$_providerPath';
      await c.evaluateJavascript(
        source: '''
(async function() {
  function done(payload) {
    try { window.flutter_inappwebview.callHandler('googleOAuthBootstrapResult', payload); } catch (_) {}
  }
  try {
    const csrfResp = await fetch('/session/csrf', {
      method: 'GET',
      credentials: 'include',
      cache: 'no-store',
      headers: { 'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest' }
    });
    const csrfText = await csrfResp.text();
    if (csrfResp.status !== 200) {
      return done({ok:false, phase:'csrf', status:csrfResp.status});
    }
    let csrfJson;
    try { csrfJson = JSON.parse(csrfText); }
    catch (_) { return done({ok:false, phase:'csrf-json', status:csrfResp.status}); }
    const csrf = csrfJson && csrfJson.csrf;
    if (!csrf) return done({ok:false, phase:'csrf-empty', status:csrfResp.status});

    const form = document.createElement('form');
    form.method = 'POST';
    form.action = ${jsonEncode(providerUrl)};
    function field(name, value) {
      const input = document.createElement('input');
      input.type = 'hidden';
      input.name = name;
      input.value = value;
      form.appendChild(input);
    }
    field('authenticity_token', csrf);
    field('origin', '/');
    document.body.appendChild(form);
    done({ok:true, phase:'submit'});
    form.submit();
  } catch (e) {
    done({ok:false, phase:'exception', status:0});
  }
})();
''',
      );

      return await googleRedirect.future.timeout(_browserTimeout);
    } finally {
      final c = controller;
      if (c != null) {
        await _syncBrowserCookies(c, generation);
      }
      headless?.dispose();
    }
  }

  /// 用隐藏浏览器网络栈请求 callback。callback 最终要跳转到 Linux.do 页面时
  /// 在 shouldOverrideUrlLoading 里直接取消；此时 Set-Cookie 已由 WebView 内核
  /// 接收。随后同一 WebView 用 fetch('/session/current.json') 验证登录态。
  Future<String?> _completeCallbackWithBrowser(Uri callbackUri) async {
    final generation = AuthSession().generation;
    await WebViewCookiePriming.instance.prime(AppConstants.baseUrl);

    var pageLoaded = Completer<void>();
    final callbackProcessed = Completer<void>();
    final sessionResult = Completer<Map<String, dynamic>>();
    InAppWebViewController? controller;
    HeadlessInAppWebView? headless;
    var callbackStarted = false;

    void fail(Object error) {
      if (!callbackProcessed.isCompleted) callbackProcessed.completeError(error);
    }

    try {
      headless = HeadlessInAppWebView(
        initialSettings: _oauthHeadlessSettings(),
        initialUserScripts: WebViewSettings.compatPolyfillScripts,
        onReceivedServerTrustAuthRequest: (_, challenge) =>
            WebViewSettings.handleServerTrustAuthRequest(challenge),
        onWebViewCreated: (c) {
          controller = c;
          c.addJavaScriptHandler(
            handlerName: 'googleOAuthSessionResult',
            callback: (args) {
              if (sessionResult.isCompleted) return null;
              final raw = args.isNotEmpty ? args.first : null;
              if (raw is Map) {
                sessionResult.complete(Map<String, dynamic>.from(raw));
              } else {
                sessionResult.complete(<String, dynamic>{
                  'ok': false,
                  'status': 0,
                });
              }
              return null;
            },
          );
        },
        shouldOverrideUrlLoading: (c, action) async {
          final raw = action.request.url?.toString();
          final target = raw == null ? null : Uri.tryParse(raw);
          if (target == null || !callbackStarted) {
            return NavigationActionPolicy.ALLOW;
          }

          // 初始 callback 本身必须放行；其他 linux.do 主框架导航都是 callback
          // 的最终去向，直接取消，避免真正加载首页/登录页。
          if (isCallback(target)) return NavigationActionPolicy.ALLOW;

          if (_isLinuxDo(target)) {
            if (target.path.startsWith('/auth/failure')) {
              fail(StateError('Linux.do rejected Google OAuth callback'));
            } else if (!callbackProcessed.isCompleted) {
              callbackProcessed.complete();
            }
            return NavigationActionPolicy.CANCEL;
          }

          // callback 正常不应再跳外站；Google 地址也禁止在隐藏 WebView 重开。
          if (_isAllowedGoogleAuthorizeUri(target)) {
            fail(StateError('Unexpected Google redirect during callback'));
            return NavigationActionPolicy.CANCEL;
          }

          return NavigationActionPolicy.ALLOW;
        },
        onLoadStop: (c, url) {
          if (!pageLoaded.isCompleted) pageLoaded.complete();
          if (!callbackStarted || callbackProcessed.isCompleted) return;
          final target = Uri.tryParse(url?.toString() ?? '');
          // 极少数情况下 callback 可能 200 而不是 302；也视为已处理，后续
          // 由 session/current.json 决定是否真的登录成功。
          if (target != null && isCallback(target)) {
            callbackProcessed.complete();
          }
        },
        onReceivedError: (c, request, error) {
          if (request.isForMainFrame != false &&
              callbackStarted &&
              !callbackProcessed.isCompleted) {
            fail(StateError('OAuth callback WebView error: ${error.type}'));
          }
        },
      );

      await headless.run();
      controller = headless.webViewController;
      final c = controller;
      if (c == null) throw StateError('OAuth callback WebView unavailable');

      pageLoaded = Completer<void>();
      await c.loadData(
        data: '<!DOCTYPE html><html><head><meta charset="utf-8"></head><body></body></html>',
        baseUrl: WebUri(AppConstants.baseUrl),
        mimeType: 'text/html',
        encoding: 'utf-8',
      );
      await pageLoaded.future.timeout(_browserTimeout);

      callbackStarted = true;
      await c.loadUrl(urlRequest: URLRequest(url: WebUri(callbackUri.toString())));
      await callbackProcessed.future.timeout(_browserTimeout);

      // 给 WebView CookieStore 一个很短的提交窗口，再用同一浏览器上下文检查会话。
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await c.evaluateJavascript(
        source: '''
(async function() {
  function done(payload) {
    try { window.flutter_inappwebview.callHandler('googleOAuthSessionResult', payload); } catch (_) {}
  }
  try {
    const r = await fetch('/session/current.json', {
      method: 'GET',
      credentials: 'include',
      cache: 'no-store',
      headers: { 'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest' }
    });
    done({ok:r.status === 200, status:r.status, body:await r.text()});
  } catch (e) {
    done({ok:false, status:0, body:''});
  }
})();
''',
      );

      final result = await sessionResult.future.timeout(_browserTimeout);
      if (result['ok'] != true) return null;
      final body = result['body']?.toString() ?? '';
      if (body.isEmpty) return null;

      try {
        final decoded = jsonDecode(body);
        if (decoded is! Map) return null;
        final currentUser = decoded['current_user'];
        if (currentUser is! Map) return null;
        return currentUser['username']?.toString();
      } catch (_) {
        return null;
      }
    } finally {
      final c = controller;
      if (c != null) {
        await _syncBrowserCookies(c, generation);
      }
      headless?.dispose();
    }
  }

  InAppWebViewSettings _oauthHeadlessSettings() => InAppWebViewSettings(
    javaScriptEnabled: true,
    sharedCookiesEnabled: true,
    userAgent: AppConstants.webViewUserAgentOverride,
    // CF / OAuth 需要接近真实浏览器，保留资源加载能力，仅拦截主框架导航。
    useShouldOverrideUrlLoading: true,
    useShouldInterceptRequest: false,
    useOnLoadResource: false,
    useOnDownloadStart: false,
    transparentBackground: true,
    disableContextMenu: true,
    verticalScrollBarEnabled: false,
    horizontalScrollBarEnabled: false,
    disableVerticalScroll: true,
    disableHorizontalScroll: true,
    supportZoom: false,
    thirdPartyCookiesEnabled: true,
  );

  Future<void> _syncBrowserCookies(
    InAppWebViewController controller,
    int generation,
  ) async {
    await BoundarySyncService.instance.syncFromWebView(
      currentUrl: AppConstants.baseUrl,
      controller: controller,
      cookieNames: const {'_t', '_forum_session', 'cf_clearance'},
      // Android 老 WebView 可能拿不到完整 cookie 元数据；OAuth 边界处我们明确
      // 知道来源是 linux.do 的浏览器上下文，因此允许回写会话 cookie。
      allowLowConfidenceSessionCookies: true,
      requestGeneration: generation,
    );
  }

  bool _isLinuxDo(Uri uri) =>
      uri.scheme.toLowerCase() == 'https' && uri.host.toLowerCase() == 'linux.do';

  bool _isAllowedGoogleAuthorizeUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https') return false;
    return uri.host.toLowerCase() == 'accounts.google.com';
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
