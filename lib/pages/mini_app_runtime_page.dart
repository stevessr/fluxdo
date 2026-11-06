import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../constants.dart';
import '../models/mini_app.dart';
import '../models/mini_app_runtime.dart';
import '../services/discourse/discourse_service.dart';
import '../services/mini_app_runtime_repository.dart';
import '../services/network/cookie/cookie_store_observer.dart';
import '../services/network/cookie/webview_cookie_priming.dart';
import '../services/webview_settings.dart';
import '../services/windows_webview_environment_service.dart';
import 'webview_page.dart';

/// Native shell around the official, sandboxed Discourse mini app runtime.
/// The origin's loader handles /launch, verification, decryption and the SDK.
class MiniAppRuntimePage extends StatefulWidget {
  const MiniAppRuntimePage({super.key, required this.app});

  final MiniApp app;

  @override
  State<MiniAppRuntimePage> createState() => _MiniAppRuntimePageState();
}

class _MiniAppRuntimePageState extends State<MiniAppRuntimePage> {
  late final MiniAppRuntimeRepository _repository = MiniAppRuntimeRepository(
    dio: DiscourseService().dio,
    site: Uri.parse(AppConstants.baseUrl),
  );
  late Future<MiniAppRuntime> _runtimeFuture;
  InAppWebViewController? _controller;
  bool _loading = true;
  String? _loadError;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _runtimeFuture = _repository.resolve(widget.app.id);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _retry() {
    _controller = null;
    setState(() {
      _loadError = null;
      _loading = true;
      _progress = 0;
      _runtimeFuture = _repository.resolve(widget.app.id);
    });
  }

  void _reload() {
    final controller = _controller;
    if (controller == null || _loadError != null) {
      _retry();
    } else {
      unawaited(controller.reload());
    }
  }

  void _openWebsite() {
    WebViewPage.open(
      context,
      widget.app.url.toString(),
      title: widget.app.name,
    );
  }

  Future<NavigationActionPolicy> _shouldOverrideUrlLoading(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    final url = action.request.url;
    if (url == null) return NavigationActionPolicy.CANCEL;
    // The runtime uses cross-origin-isolated, sandboxed nested frames.
    // Do not interfere with subframe and blob/data navigations.
    if (action.isForMainFrame != true) return NavigationActionPolicy.ALLOW;
    final site = Uri.parse(AppConstants.baseUrl);
    if (url.scheme == 'https' &&
        url.host.toLowerCase() == site.host.toLowerCase() &&
        url.port == site.port) {
      return NavigationActionPolicy.ALLOW;
    }
    if (url.scheme == 'about') return NavigationActionPolicy.ALLOW;
    if (mounted && url.scheme == 'https') {
      unawaited(WebViewPage.open(context, url.toString()));
    }
    return NavigationActionPolicy.CANCEL;
  }

  Widget _buildRuntime(MiniAppRuntime runtime) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Column(
      children: [
        if (_loading) LinearProgressIndicator(value: _progress > 0 && _progress < 1 ? _progress : null),
        if (_loadError != null)
          MaterialBanner(
            content: Text(zh
                ? '无法初始化应用运行环境，请重试或在网页中打开。'
                : 'Unable to initialize the app runtime. Retry or open its web page.'),
            actions: [
              TextButton(onPressed: _retry, child: Text(zh ? '重试' : 'Retry')),
              TextButton(
                onPressed: _openWebsite,
                child: Text(zh ? '网页打开' : 'Open website'),
              ),
            ],
          ),
        Expanded(
          child: WebViewSettings.wrapWithScrollFix(
            InAppWebView(
              webViewEnvironment:
                  WindowsWebViewEnvironmentService.instance.environment,
              initialSettings: WebViewSettings.visible
                ..useShouldOverrideUrlLoading = true,
              initialUserScripts: WebViewSettings.compatPolyfillScripts,
              shouldOverrideUrlLoading: _shouldOverrideUrlLoading,
              onReceivedServerTrustAuthRequest: (_, challenge) =>
                  WebViewSettings.handleServerTrustAuthRequest(challenge),
              onWebViewCreated: (controller) async {
                _controller = controller;
                WebViewSettings.registerJsErrorReporter(controller);
                try {
                  await WebViewCookiePriming.instance.prime(
                    runtime.embedUrl.toString(),
                  );
                  if (!mounted || _controller != controller) return;
                  await controller.loadUrl(
                    urlRequest: URLRequest(
                      url: WebUri(runtime.embedUrl.toString()),
                    ),
                  );
                } catch (_) {
                  if (!mounted || _controller != controller) return;
                  setState(() {
                    _loadError = 'initialization';
                    _loading = false;
                  });
                }
              },
              onLoadStart: (_, __) {
                if (!mounted) return;
                setState(() {
                  _loading = true;
                  _progress = 0;
                  _loadError = null;
                });
              },
              onProgressChanged: (_, progress) {
                if (!mounted) return;
                setState(() => _progress = progress / 100);
              },
              onLoadStop: (controller, _) async {
                if (!mounted) return;
                setState(() => _loading = false);
                CookieStoreObserver.instance.notifyExternalChange();
                await WebViewSettings.injectScrollFix(controller);
              },
            ),
            getController: () => _controller,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.app.name),
        actions: [
          IconButton(
            tooltip: zh ? '刷新应用' : 'Reload app',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reload,
          ),
          IconButton(
            tooltip: zh ? '网页打开' : 'Open website',
            icon: const Icon(Icons.open_in_browser_rounded),
            onPressed: _openWebsite,
          ),
        ],
      ),
      body: FutureBuilder<MiniAppRuntime>(
        future: _runtimeFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 44),
                  const SizedBox(height: 12),
                  Text(zh
                      ? '获取应用运行配置失败'
                      : 'Unable to fetch the app runtime'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _retry,
                    child: Text(zh ? '重试' : 'Retry'),
                  ),
                  TextButton(
                    onPressed: _openWebsite,
                    child: Text(zh ? '在网页中打开' : 'Open website'),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildRuntime(snapshot.requireData);
        },
      ),
    );
  }
}
