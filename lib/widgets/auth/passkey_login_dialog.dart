import 'dart:convert';
import 'dart:io';

import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../constants.dart';
import '../../services/auth_session.dart';
import '../../services/network/cookie/boundary_sync_service.dart';
import '../../services/network/cookie/cookie_jar_service.dart';
import '../../services/network/cookie/webview_cookie_priming.dart';
import '../../services/preloaded_data_service.dart';
import '../../services/webview_session_cookie_refresh_service.dart';
import '../../services/webview_settings.dart';

/// Passkey 直连登录结果。
///
/// 这里的“直连”指 FluxDO 不打开 /login、不加载 Discourse Ember 登录页：
/// challenge / assertion / auth 都由一个同源轻量 WebView 中的 JS 直接完成。
/// WebView 只作为 WebAuthn ceremony 的安全上下文，真正的凭据选择 UI 由系统提供。
enum PasskeyLoginStatus { success, failure, canceled }

class PasskeyLoginDialogResult {
  const PasskeyLoginDialogResult.success(this.username)
    : status = PasskeyLoginStatus.success,
      errorMessage = null;

  const PasskeyLoginDialogResult.failure(this.errorMessage)
    : status = PasskeyLoginStatus.failure,
      username = null;

  const PasskeyLoginDialogResult.canceled()
    : status = PasskeyLoginStatus.canceled,
      username = null,
      errorMessage = null;

  final PasskeyLoginStatus status;
  final String? username;
  final String? errorMessage;
}

Future<PasskeyLoginDialogResult?> showPasskeyLoginDialog(
  BuildContext context,
) async {
  // 当前实现依赖 Android WebView 的 WebAuthentication support level。
  // 其他平台的嵌入式 WebView 是否能代表 linux.do RP 取决于平台 entitlement /
  // associated-domain 策略，第一版不做未经验证的跨平台承诺。
  if (!Platform.isAndroid) {
    return const PasskeyLoginDialogResult.failure(
      '当前直连 Passkey 实验仅支持 Android',
    );
  }

  return showDialog<PasskeyLoginDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _PasskeyLoginDialog(),
  );
}

class _PasskeyLoginDialog extends StatefulWidget {
  const _PasskeyLoginDialog();

  @override
  State<_PasskeyLoginDialog> createState() => _PasskeyLoginDialogState();
}

class _PasskeyLoginDialogState extends State<_PasskeyLoginDialog> {
  InAppWebViewController? _controller;
  bool _started = false;
  bool _finished = false;
  String _statusText = '正在准备 Passkey…';
  final int _flowGeneration = AuthSession().generation;

  /// 与 Discourse frontend/discourse/app/lib/webauthn.js 保持字段和编码口径一致。
  ///
  /// 注意：challenge 是服务端 stage_challenge 返回的字符串，Discourse 前端
  /// 使用 charCodeAt 逐字节复制，而不是把 challenge 当 base64 解码。
  static const String _inlineHtml = r'''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
</head>
<body>
<script>
(function () {
  function done(payload) {
    try {
      window.flutter_inappwebview.callHandler(
        'passkey_result',
        JSON.stringify(payload)
      );
    } catch (_) {}
  }

  function stringToBuffer(str) {
    var buffer = new ArrayBuffer(str.length);
    var byteView = new Uint8Array(buffer);
    for (var i = 0; i < str.length; i++) {
      byteView[i] = str.charCodeAt(i);
    }
    return buffer;
  }

  function bufferToBase64(buffer) {
    if (!buffer) return '';
    var bytes = new Uint8Array(buffer);
    var binary = '';
    // 分块，避免较长数组触发 apply 参数数量限制。
    for (var i = 0; i < bytes.length; i += 0x8000) {
      var end = Math.min(i + 0x8000, bytes.length);
      binary += String.fromCharCode.apply(null, bytes.subarray(i, end));
    }
    return btoa(binary);
  }

  async function readError(response) {
    var text = '';
    try { text = await response.text(); } catch (_) {}
    if (!text) return 'HTTP ' + response.status;
    try {
      var parsed = JSON.parse(text);
      if (parsed && parsed.error) return String(parsed.error);
      if (parsed && parsed.errors) return String(parsed.errors);
    } catch (_) {}
    // Cloudflare / Rails HTML 不整页回传给 Flutter。
    return text.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 240);
  }

  window.__fluxdoPasskeyLogin = async function () {
    if (!window.PublicKeyCredential || !navigator.credentials) {
      return done({
        phase: 'unsupported',
        message: 'PublicKeyCredential unavailable in embedded WebView'
      });
    }

    try {
      // POST /session/passkey/auth.json 仍需要与当前 server session 配对的 CSRF。
      var csrfResponse = await fetch('/session/csrf', {
        method: 'GET',
        credentials: 'include',
        cache: 'no-store',
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      });
      if (!csrfResponse.ok) {
        return done({
          phase: 'csrf',
          status: csrfResponse.status,
          message: await readError(csrfResponse)
        });
      }
      var csrfPayload = await csrfResponse.json();
      var csrf = csrfPayload && csrfPayload.csrf;
      if (!csrf) {
        return done({ phase: 'csrf', message: 'missing csrf token' });
      }

      var challengeResponse = await fetch('/session/passkey/challenge.json', {
        method: 'GET',
        credentials: 'include',
        cache: 'no-store',
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      });
      if (!challengeResponse.ok) {
        return done({
          phase: 'challenge',
          status: challengeResponse.status,
          message: await readError(challengeResponse)
        });
      }
      var challengePayload = await challengeResponse.json();
      if (!challengePayload || !challengePayload.challenge) {
        return done({ phase: 'challenge', message: 'missing passkey challenge' });
      }

      var credential;
      try {
        credential = await navigator.credentials.get({
          publicKey: {
            challenge: stringToBuffer(challengePayload.challenge),
            userVerification: 'required'
          }
        });
      } catch (error) {
        var name = error && error.name ? String(error.name) : '';
        if (name === 'NotAllowedError' || name === 'AbortError') {
          return done({ phase: 'canceled' });
        }
        return done({
          phase: 'credential',
          errorName: name,
          message: error && error.message ? String(error.message) : String(error)
        });
      }

      if (!credential || !credential.response) {
        return done({ phase: 'credential', message: 'empty authenticator response' });
      }

      var publicKeyCredential = {
        signature: bufferToBase64(credential.response.signature),
        clientData: bufferToBase64(credential.response.clientDataJSON),
        authenticatorData: bufferToBase64(credential.response.authenticatorData),
        credentialId: bufferToBase64(credential.rawId),
        userHandle: bufferToBase64(credential.response.userHandle)
      };

      var authResponse = await fetch('/session/passkey/auth.json', {
        method: 'POST',
        credentials: 'include',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': csrf,
          'X-Requested-With': 'XMLHttpRequest'
        },
        body: JSON.stringify({ publicKeyCredential: publicKeyCredential })
      });
      if (!authResponse.ok) {
        return done({
          phase: 'auth',
          status: authResponse.status,
          message: await readError(authResponse)
        });
      }

      var authText = await authResponse.text();
      if (authText) {
        try {
          var authPayload = JSON.parse(authText);
          if (authPayload && authPayload.error) {
            return done({ phase: 'auth', message: String(authPayload.error) });
          }
        } catch (_) {}
      }

      // 不依赖 passkey auth serializer 的具体 root 形状，统一从当前 session
      // 读取最终用户名，后续 Dart 侧沿用既有 finalizeNativeLoginSuccess。
      var currentResponse = await fetch('/session/current.json', {
        method: 'GET',
        credentials: 'include',
        cache: 'no-store',
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      });
      if (!currentResponse.ok) {
        return done({
          phase: 'session',
          status: currentResponse.status,
          message: await readError(currentResponse)
        });
      }
      var current = await currentResponse.json();
      var username = current && current.username;
      if (!username && current && current.user) username = current.user.username;
      if (!username) {
        return done({ phase: 'session', message: 'session has no username' });
      }

      return done({ phase: 'success', username: String(username) });
    } catch (error) {
      return done({
        phase: 'exception',
        message: error && error.message ? String(error.message) : String(error)
      });
    }
  };
})();
</script>
</body>
</html>
''';

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _setupHandlers(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'passkey_result',
      callback: (args) {
        final raw = args.isNotEmpty ? args.first?.toString() : null;
        if (raw != null) {
          _handleResult(raw);
        }
        return null;
      },
    );
  }

  Future<void> _startFlow() async {
    if (_started || _finished) return;
    _started = true;
    final controller = _controller;
    if (controller == null) {
      _finishFailure('Passkey WebView 尚未就绪');
      return;
    }

    try {
      if (mounted) setState(() => _statusText = '正在同步安全会话…');
      await WebViewCookiePriming.instance.prime(AppConstants.baseUrl);
      if (_finished) return;

      // WebAuthn support 已在这个 InAppWebView 创建时直接写入其 WebSettings，
      // 不再依赖 MainActivity 扫描 Flutter PlatformView 的原生 View 树。
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (_finished) return;
      if (mounted) setState(() => _statusText = '请使用系统 Passkey 验证身份');
      await controller.evaluateJavascript(
        source: 'window.__fluxdoPasskeyLogin();',
      );
    } catch (e) {
      _finishFailure('Passkey 初始化失败: $e');
    }
  }

  Future<void> _handleResult(String raw) async {
    if (_finished) return;

    Map<String, dynamic> payload;
    try {
      payload = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      _finishFailure('Passkey 响应解析失败');
      return;
    }

    final phase = payload['phase']?.toString() ?? 'unknown';
    if (phase == 'canceled') {
      _finishCanceled();
      return;
    }
    if (phase == 'success') {
      final username = payload['username']?.toString();
      if (username == null || username.isEmpty) {
        _finishFailure('Passkey 登录成功但无法读取用户名');
        return;
      }
      await _finishSuccess(username);
      return;
    }

    final status = (payload['status'] as num?)?.toInt();
    final detail = _shortMessage(payload['message']?.toString());
    final errorName = payload['errorName']?.toString();
    final suffix = status == null ? '' : ' (HTTP $status)';
    final message = switch (phase) {
      'unsupported' =>
        '嵌入式 Android WebView 未暴露 WebAuthn；浏览器可用不代表 WebView 可用，请确认 Android System WebView/Chrome 已更新',
      'csrf' => 'Cloudflare/CSRF 验证失败$suffix',
      'challenge' => '无法获取 Passkey challenge$suffix',
      'credential' => errorName == 'SecurityError'
          ? '系统拒绝 WebView 代表 linux.do 请求 Passkey：${detail ?? 'SecurityError'}'
          : detail ?? '系统 Passkey 验证失败',
      'auth' => detail ?? 'Passkey 凭据校验失败$suffix',
      'session' => detail ?? 'Passkey 已验证，但会话建立失败$suffix',
      'exception' => detail ?? 'Passkey 请求异常',
      _ => detail ?? 'Passkey 登录失败',
    };
    _finishFailure(message);
  }

  String? _shortMessage(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    return text.length <= 240 ? text : '${text.substring(0, 240)}…';
  }

  Future<void> _finishSuccess(String username) async {
    if (_finished) return;
    if (!AuthSession().isValid(_flowGeneration)) {
      _finishCanceled();
      return;
    }

    final controller = _controller;
    if (controller == null) {
      _finishFailure('Passkey 会话同步失败: WebView 已释放');
      return;
    }

    if (mounted) setState(() => _statusText = '正在同步登录状态…');

    try {
      var bootstrapped = false;
      final bootstrapResult = await WebViewSessionCookieRefreshService.instance
          .runOnController(
            controller,
            reason: 'passkey_login_success',
            pluginCandidates: PreloadedDataService().pluginCandidatesSync,
          );
      bootstrapped = bootstrapResult.ok;

      await BoundarySyncService.instance.syncFromWebView(
        controller: controller,
        currentUrl: AppConstants.baseUrl,
        cookieNames: null,
        allowLowConfidenceSessionCookies: true,
        requestGeneration: _flowGeneration,
        trusted: true,
      );

      final runtimeDetails = await CookieJarService()
          .getCookieDiagnosticsForRequest(
            Uri.parse(AppConstants.baseUrl),
            names: const {'_rt'},
          );
      final hasRuntimeCookie = runtimeDetails.any(
        (cookie) => (cookie['valueLength'] as int? ?? 0) > 0,
      );
      final tToken = await CookieJarService().getTToken();
      if (hasRuntimeCookie) {
        WebViewSessionCookieRefreshService.instance.markSynced(
          reason: 'passkey_login_success',
          tToken: tToken,
          hasRuntimeCookie: hasRuntimeCookie,
        );
      }
      await WebViewSessionCookieRefreshService.instance.logCookieSummary(
        reason: 'passkey_login_success',
        bootstrapOk: bootstrapped,
      );
    } catch (e) {
      _finishFailure('Passkey 已验证，但同步会话失败: $e');
      return;
    }

    if (_finished) return;
    _finished = true;
    if (mounted) {
      Navigator.of(context).pop(PasskeyLoginDialogResult.success(username));
    }
  }

  void _finishFailure(String message) {
    if (_finished) return;
    _finished = true;
    if (mounted) {
      Navigator.of(context).pop(PasskeyLoginDialogResult.failure(message));
    }
  }

  void _finishCanceled() {
    if (_finished) return;
    _finished = true;
    if (mounted) {
      Navigator.of(context).pop(const PasskeyLoginDialogResult.canceled());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: Icon(Symbols.fingerprint_rounded, color: scheme.primary, size: 36),
        title: const Text('Passkey 登录'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // WebAuthn support 必须写到这个具体 WebView 的 WebSettings；不能再
              // 依赖 Activity View 树扫描，因为 Flutter PlatformView 组合模式下
              // 原生 WebView 不保证能从 window.decorView 稳定遍历到。
              SizedBox(
                width: 1,
                height: 1,
                child: InAppWebView(
                  initialData: InAppWebViewInitialData(
                    data: _inlineHtml,
                    baseUrl: WebUri(AppConstants.baseUrl),
                    mimeType: 'text/html',
                    encoding: 'utf-8',
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    transparentBackground: true,
                    supportZoom: false,
                    sharedCookiesEnabled: true,
                    thirdPartyCookiesEnabled: true,
                    userAgent: AppConstants.webViewUserAgentOverride,
                    webAuthenticationSupport:
                        WebAuthenticationSupport.FOR_BROWSER,
                  ),
                  initialUserScripts: WebViewSettings.compatPolyfillScripts,
                  onReceivedServerTrustAuthRequest: (_, challenge) =>
                      WebViewSettings.handleServerTrustAuthRequest(challenge),
                  onWebViewCreated: (controller) {
                    _controller = controller;
                    WebViewSettings.registerJsErrorReporter(controller);
                    _setupHandlers(controller);
                  },
                  onLoadStop: (controller, _) {
                    _startFlow();
                  },
                ),
              ),
              const SizedBox(height: 18),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _statusText,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '不会打开 linux.do 登录网页',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: _finishCanceled, child: const Text('取消')),
        ],
      ),
    );
  }
}
