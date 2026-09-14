import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/messaging/telegram_web_policy.dart';

/// Experimental Telegram integration.
///
/// Telegram Web remains the safe fallback while the native MTProto provider is
/// still experimental. Keep the embedded surface constrained to Telegram's own
/// HTTPS origins and hand downloads, target=_blank windows and external links
/// back to the operating system.
class TelegramChatPage extends StatefulWidget {
  const TelegramChatPage({super.key});

  @override
  State<TelegramChatPage> createState() => _TelegramChatPageState();
}

class _TelegramChatPageState extends State<TelegramChatPage> {
  static final WebUri _telegramUrl = WebUri('https://web.telegram.org/a/');

  InAppWebViewController? _controller;
  double _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String? _error;

  bool get _webViewSupported {
    if (kIsWeb) return true;
    // Fluxdo uses flutter_inappwebview 6.2.0-beta.3. That prerelease includes
    // the Linux implementation in addition to the other supported platforms.
    return defaultTargetPlatform != TargetPlatform.fuchsia;
  }

  Future<bool> _launchExternalUri(WebUri uri) async {
    final externalUri = Uri.tryParse(uri.toString());
    if (externalUri == null) return false;

    try {
      if (!await canLaunchUrl(externalUri)) return false;
      return launchUrl(externalUri, mode: LaunchMode.externalApplication);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '无法打开外部链接：$error');
      }
      return false;
    }
  }

  Future<void> _updateNavigationState() async {
    final controller = _controller;
    if (controller == null) return;

    try {
      final results = await Future.wait<bool>([
        controller.canGoBack(),
        controller.canGoForward(),
      ]);
      if (!mounted) return;
      setState(() {
        _canGoBack = results[0];
        _canGoForward = results[1];
      });
    } catch (_) {
      // Some platform implementations may not expose history state during a
      // provisional navigation. The next successful load will retry it.
    }
  }

  Future<void> _goBack() async {
    final controller = _controller;
    if (controller == null || !await controller.canGoBack()) return;
    await controller.goBack();
    await _updateNavigationState();
  }

  Future<void> _goForward() async {
    final controller = _controller;
    if (controller == null || !await controller.canGoForward()) return;
    await controller.goForward();
    await _updateNavigationState();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _error = null);
    await _controller?.reload();
  }

  Future<void> _openExternally() async {
    await _launchExternalUri(_telegramUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Telegram'),
        actions: <Widget>[
          if (_webViewSupported) ...<Widget>[
            IconButton(
              tooltip: '后退',
              onPressed: _canGoBack ? _goBack : null,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            IconButton(
              tooltip: '前进',
              onPressed: _canGoForward ? _goForward : null,
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
            IconButton(
              tooltip: '刷新',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
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
                      '实验性 Telegram：Telegram Web 仅在内嵌页打开 telegram.org；外链、新窗口与下载交给系统处理。后续可替换为 native MTProto provider。',
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
                          '可以先使用 Telegram Web 外部浏览器；native MTProto adapter 会作为下一阶段实现。',
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
                  useOnDownloadStart: true,
                  supportMultipleWindows: true,
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
                onLoadStop: (controller, url) async {
                  if (!mounted) return;
                  setState(() => _progress = 1);
                  await _updateNavigationState();
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
                onDownloadStartRequest: (controller, request) async {
                  final launched = await _launchExternalUri(request.url);
                  if (!launched && mounted) {
                    setState(() {
                      _error = '无法交给系统下载：${request.url}';
                    });
                  }
                },
                onCreateWindow: (controller, action) async {
                  final uri = action.request.url;
                  if (uri != null) {
                    await _launchExternalUri(uri);
                  }
                  // We intentionally do not create a second embedded WebView.
                  return false;
                },
                shouldOverrideUrlLoading: (controller, action) async {
                  final webUri = action.request.url;
                  if (webUri == null) return NavigationActionPolicy.ALLOW;

                  final uri = Uri.tryParse(webUri.toString());
                  if (uri == null) return NavigationActionPolicy.CANCEL;

                  final disposition = TelegramWebPolicy.classify(
                    uri,
                    isMainFrame: action.isForMainFrame,
                  );
                  switch (disposition) {
                    case TelegramWebNavigationDisposition.embedded:
                    case TelegramWebNavigationDisposition.subframe:
                      return NavigationActionPolicy.ALLOW;
                    case TelegramWebNavigationDisposition.external:
                      final launched = await _launchExternalUri(webUri);
                      if (!launched && mounted) {
                        setState(() => _error = '无法打开链接：$webUri');
                      }
                      return NavigationActionPolicy.CANCEL;
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
