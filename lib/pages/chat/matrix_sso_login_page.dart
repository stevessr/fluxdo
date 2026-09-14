import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

class MatrixSsoLoginPage extends StatefulWidget {
  const MatrixSsoLoginPage({
    super.key,
    required this.initialUri,
    required this.callbackUri,
  });

  final Uri initialUri;
  final Uri callbackUri;

  @override
  State<MatrixSsoLoginPage> createState() => _MatrixSsoLoginPageState();
}

class _MatrixSsoLoginPageState extends State<MatrixSsoLoginPage> {
  double _progress = 0;
  String? _error;
  bool _completed = false;

  bool _isExpectedCallback(Uri uri) {
    final expectedState = widget.callbackUri.queryParameters['state'];
    return uri.scheme == widget.callbackUri.scheme &&
        uri.host == widget.callbackUri.host &&
        uri.path == widget.callbackUri.path &&
        expectedState != null &&
        uri.queryParameters['state'] == expectedState;
  }

  Future<void> _handleCallback(Uri uri) async {
    if (_completed) return;
    if (!_isExpectedCallback(uri)) {
      if (mounted) {
        setState(() {
          _error = '已拒绝无法验证 state 的 Matrix SSO 回调。';
        });
      }
      return;
    }

    final loginToken = uri.queryParameters['loginToken']?.trim();
    if (loginToken == null || loginToken.isEmpty) {
      if (mounted) {
        setState(() => _error = 'Matrix SSO 回调没有 loginToken。');
      }
      return;
    }

    _completed = true;
    if (!mounted) return;
    Navigator.of(context).pop(loginToken);
  }

  Future<void> _launchExternal(WebUri webUri) async {
    final uri = Uri.tryParse(webUri.toString());
    if (uri == null) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // The embedded SSO page remains usable if an optional external-app link
      // cannot be launched.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Matrix SSO'),
        actions: <Widget>[
          IconButton(
            tooltip: '取消登录',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: <Widget>[
                  Icon(Icons.security_rounded, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fluxdo 只接受本次登录生成的 nonce 回调；SSO 页面本身可跳转到 homeserver 配置的身份提供商。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_progress > 0 && _progress < 1)
            LinearProgressIndicator(value: _progress),
          if (_error != null)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.error_outline_rounded, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!)),
                  ],
                ),
              ),
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(widget.initialUri.toString()),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                databaseEnabled: true,
                useShouldOverrideUrlLoading: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                supportZoom: true,
              ),
              onProgressChanged: (controller, progress) {
                if (!mounted) return;
                setState(() => _progress = progress / 100);
              },
              onReceivedError: (controller, request, error) {
                if (request.isForMainFrame != true || !mounted) return;
                final uri = Uri.tryParse(request.url.toString());
                if (uri != null && _isExpectedCallback(uri)) return;
                setState(() {
                  _error = '${error.type}: ${error.description}';
                });
              },
              shouldOverrideUrlLoading: (controller, action) async {
                final webUri = action.request.url;
                if (webUri == null || !action.isForMainFrame) {
                  return NavigationActionPolicy.ALLOW;
                }

                final uri = Uri.tryParse(webUri.toString());
                if (uri == null) return NavigationActionPolicy.CANCEL;

                if (uri.scheme == widget.callbackUri.scheme &&
                    uri.host == widget.callbackUri.host &&
                    uri.path == widget.callbackUri.path) {
                  await _handleCallback(uri);
                  return NavigationActionPolicy.CANCEL;
                }

                if (uri.scheme == 'http' || uri.scheme == 'https') {
                  return NavigationActionPolicy.ALLOW;
                }

                await _launchExternal(webUri);
                return NavigationActionPolicy.CANCEL;
              },
            ),
          ),
        ],
      ),
    );
  }
}
