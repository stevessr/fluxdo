import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

/// Experimental Telegram integration.
///
/// Telegram Web is intentionally used as the first transport because Fluxdo
/// already ships flutter_inappwebview. It gives the branch a usable Telegram
/// client without introducing TDLib native binaries. The page is isolated so
/// it can later be swapped for a native MTProto/TDLib adapter without changing
/// the chat hub navigation.
class TelegramChatPage extends StatefulWidget {
  const TelegramChatPage({super.key});

  @override
  State<TelegramChatPage> createState() => _TelegramChatPageState();
}

class _TelegramChatPageState extends State<TelegramChatPage> {
  static final WebUri _telegramUrl = WebUri('https://web.telegram.org/a/');

  InAppWebViewController? _controller;
  double _progress = 0;
  String? _error;

  bool get _webViewSupported {
    if (kIsWeb) return true;
    // Fluxdo already uses flutter_inappwebview 6.2.0-beta.3, whose federated
    // plugin includes Android/iOS/macOS/Windows/Linux implementations.
    return defaultTargetPlatform != TargetPlatform.fuchsia;
  }

  Future<void> _reload() async {
    await _controller?.reload();
  }

  Future<void> _openExternally() async {
    final uri = Uri.parse(_telegramUrl.toString());
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Telegram'),
        actions: <Widget>[
          if (_webViewSupported)
            IconButton(
              tooltip: '刷新',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          IconButton(
            tooltip: '在外部浏览器打开',
            onPressed: _openExternally,
            icon: const Icon(Icons.open_in_browser_rounded),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: Row(
                children: <Widget>[
                  Icon(Icons.science_outlined, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '实验性 Telegram：当前复用 Telegram Web；后续可替换为纯 Dart MTProto / TDLib provider。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_webViewSupported)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.open_in_browser_rounded, size: 56),
                        const SizedBox(height: 16),
                        const Text(
                          '当前平台没有 flutter_inappwebview 实现',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '可以先使用 Telegram Web 外部浏览器；原生 MTProto adapter 会作为下一阶段实现。',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _openExternally,
                          icon: const Icon(Icons.launch_rounded),
                          label: const Text('打开 Telegram Web'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else ...<Widget>[
            if (_progress > 0 && _progress < 1)
              LinearProgressIndicator(value: _progress),
            if (_error != null)
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.error_outline_rounded, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!)),
                      TextButton(onPressed: _reload, child: const Text('重试')),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: _telegramUrl),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  useShouldOverrideUrlLoading: true,
                  supportZoom: false,
                  transparentBackground: false,
                ),
                onWebViewCreated: (controller) {
                  _controller = controller;
                },
                onLoadStart: (controller, url) {
                  if (!mounted) return;
                  setState(() => _error = null);
                },
                onProgressChanged: (controller, progress) {
                  if (!mounted) return;
                  setState(() => _progress = progress / 100);
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame != true || !mounted) return;
                  setState(() {
                    _error = '${error.type}: ${error.description}';
                  });
                },
                shouldOverrideUrlLoading: (controller, action) async {
                  final uri = action.request.url;
                  if (uri == null) return NavigationActionPolicy.ALLOW;

                  final scheme = uri.scheme.toLowerCase();
                  if (scheme == 'http' || scheme == 'https') {
                    return NavigationActionPolicy.ALLOW;
                  }

                  // tg://, mailto:, tel: and other app links should leave the
                  // embedded browser instead of failing inside WebView.
                  final externalUri = Uri.tryParse(uri.toString());
                  if (externalUri != null && await canLaunchUrl(externalUri)) {
                    await launchUrl(
                      externalUri,
                      mode: LaunchMode.externalApplication,
                    );
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
