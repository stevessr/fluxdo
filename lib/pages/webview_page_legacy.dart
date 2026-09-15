import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_ui/m3e_ui.dart';
import '../utils/frame_jank_monitor.dart';
import '../utils/link_launcher.dart';
import '../services/deep_link_service.dart';
import '../services/toast_service.dart';
import '../services/app_link_service.dart';
import '../services/network/cookie/cookie_store_observer.dart';
import '../services/network/cookie/site_cookie_cleanup_service.dart';
import '../services/network/cookie/webview_cookie_priming.dart';
import '../services/webview_settings.dart';
import '../services/windows_webview_environment_service.dart';
import '../widgets/common/app_link_confirm_dialog.dart';
import '../widgets/common/smart_avatar.dart';
import '../widgets/user/account_switcher_sheet.dart';
import '../providers/discourse_providers.dart';
import '../providers/web_bookmark_provider.dart';
import '../providers/web_history_provider.dart';
import '../providers/download_provider.dart';
import 'package:common_ui/common_ui.dart';
import '../l10n/s.dart';
import '../utils/dialog_utils.dart';

/// 通用内置浏览器页面
class WebViewPage extends ConsumerStatefulWidget {
  final String url;
  final String? title;
  final String? injectCss;

  const WebViewPage({super.key, required this.url, this.title, this.injectCss});

  /// 打开浏览器，url 为空字符串时显示空白页
  static Future<T?> open<T extends Object?>(
    BuildContext context,
    String url, {
    String? title,
    String? injectCss,
  }) {
    return Navigator.push<T>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            WebViewPage(url: url, title: title, injectCss: injectCss),
      ),
    );
  }

  @override
  ConsumerState<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends ConsumerState<WebViewPage> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  String _currentUrl = '';
  String _currentTitle = '';
  double _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _historyStateSettled = false;
  int _navigationRevision = 0;

  /// 对话框期间用静态截图盖住 WebView，避免 BackdropFilter 对
  /// hybrid composition（Android）/HWND（Windows）实时回读造成卡顿。
  Uint8List? _webViewSnapshot;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _currentTitle = widget.title ?? '';
    FrameJankMonitor.logEvent('WEBVIEW', 'WebViewPage mount');
  }

  @override
  void dispose() {
    FrameJankMonitor.logEvent('WEBVIEW', 'WebViewPage dispose');
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final windowsWebViewEnvironment =
        WindowsWebViewEnvironmentService.instance.environment;
    final theme = Theme.of(context);
    final currentUser = ref.watch(currentUserProvider).value;
    final isBookmarked = ref.watch(
      webBookmarkProvider.select(
        (list) => list.any((e) => e.url == _currentUrl),
      ),
    );

    return PopScope(
      canPop: _historyStateSettled && !_canGoBack,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackNavigation();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: GestureDetector(
            onTap: _showUrlInput,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(
                    Symbols.lock_rounded,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _currentTitle.isNotEmpty
                          ? _currentTitle
                          : (_currentUrl.isNotEmpty
                                ? _currentUrl
                                : context.l10n.webview_inputUrl),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            _currentTitle.isNotEmpty || _currentUrl.isNotEmpty
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          leading: Center(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Symbols.close_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          leadingWidth: 48,
          actions: [
            IconButton(
              icon: Icon(
                Symbols.chevron_left_rounded,
                color: _canGoBack ? null : theme.disabledColor,
              ),
              onPressed: _canGoBack ? () => _controller?.goBack() : null,
              tooltip: context.l10n.webview_goBack,
            ),
            IconButton(
              icon: Icon(
                Symbols.chevron_right_rounded,
                color: _canGoForward ? null : theme.disabledColor,
              ),
              onPressed: _canGoForward ? () => _controller?.goForward() : null,
              tooltip: context.l10n.webview_goForward,
            ),
            IconButton(
              icon: const Icon(Symbols.refresh_rounded),
              onPressed: () => _controller?.reload(),
              tooltip: context.l10n.common_refresh,
            ),
            SwipeDismissiblePopupMenuButton<String>(
              onSelected: _handleMenuAction,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'toggle_bookmark',
                  child: Row(
                    children: [
                      Icon(
                        Symbols.star_rounded,
                        fill: isBookmarked ? 1 : 0,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isBookmarked
                            ? context.l10n.webview_removeBookmark
                            : context.l10n.webview_addBookmark,
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'copy_url',
                  child: Row(
                    children: [
                      const Icon(Symbols.content_copy_rounded),
                      const SizedBox(width: 8),
                      Text(context.l10n.common_copyLink),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'clear_site_cookies',
                  child: Row(
                    children: [
                      const Icon(Symbols.cookie_rounded),
                      const SizedBox(width: 8),
                      const Text('Cookie'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'open_external',
                  child: Row(
                    children: [
                      const Icon(Symbols.open_in_browser_rounded),
                      const SizedBox(width: 8),
                      Text(context.l10n.webview_openExternal),
                    ],
                  ),
                ),
              ],
            ),
            if (currentUser != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Tooltip(
                  message: context.l10n.accountManage_title,
                  child: Material(
                    type: MaterialType.transparency,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => unawaited(
                        AccountSwitcherSheet.showClassic(context),
                      ),
                      onLongPress: () => unawaited(
                        AccountSwitcherSheet.show(
                          context,
                          placement: AccountQuickSwitcherPlacement.topRight,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: SmartAvatar(
                          imageUrl: currentUser.getAvatarUrl(),
                          radius: 14,
                          fallbackText: currentUser.username,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            if (_isLoading)
              M3eLinearProgress(
                value: _progress,
                trackColor: theme.colorScheme.surfaceContainerHighest,
              ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Offstage(
                    offstage: _webViewSnapshot != null,
                    child: WebViewSettings.wrapWithScrollFix(
                      InAppWebView(
                        webViewEnvironment: windowsWebViewEnvironment,
                        initialSettings: WebViewSettings.visible
                          ..useShouldOverrideUrlLoading = true,
                        initialUserScripts: WebViewSettings.compatPolyfillScripts,
                        shouldOverrideUrlLoading: _shouldOverrideUrlLoading,
                        onReceivedServerTrustAuthRequest: (_, challenge) =>
                            WebViewSettings.handleServerTrustAuthRequest(
                              challenge,
                            ),
                        onWebViewCreated: (controller) async {
                          _controller = controller;
                          WebViewSettings.registerJsErrorReporter(controller);
                          if (widget.url.isNotEmpty) {
                            await WebViewCookiePriming.instance.prime(widget.url);
                            await controller.loadUrl(
                              urlRequest: URLRequest(url: WebUri(widget.url)),
                            );
                          }
                          if (io.Platform.isAndroid) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              const MethodChannel('com.fluxdo/webauthn')
                                  .invokeMethod('enableWebAuthentication');
                            });
                          }
                        },
                        onLoadStart: (controller, url) {
                          setState(() {
                            _navigationRevision += 1;
                            _historyStateSettled = false;
                            _isLoading = true;
                            _currentUrl = url?.toString() ?? '';
                          });
                        },
                        onProgressChanged: (controller, progress) {
                          setState(() => _progress = progress / 100);
                        },
                        onLoadStop: (controller, url) async {
                          final revision = _navigationRevision;
                          setState(() => _isLoading = false);
                          CookieStoreObserver.instance.notifyExternalChange();
                          await WebViewSettings.injectScrollFix(controller);
                          final title = await controller.getTitle();
                          final canGoBack = await controller.canGoBack();
                          final canGoForward = await controller.canGoForward();
                          if (!mounted || revision != _navigationRevision) {
                            return;
                          }
                          final urlString = url?.toString();
                          setState(() {
                            _currentUrl = urlString ?? '';
                            _canGoBack = canGoBack;
                            _canGoForward = canGoForward;
                            _historyStateSettled = true;
                            if (title != null && title.isNotEmpty) {
                              _currentTitle = title;
                            }
                          });
                          if (widget.injectCss != null) {
                            await controller.injectCSSCode(
                              source: widget.injectCss!,
                            );
                          }
                          if (urlString != null && urlString.isNotEmpty) {
                            ref
                                .read(webHistoryProvider.notifier)
                                .record(urlString, _currentTitle);
                          }
                        },
                        onUpdateVisitedHistory:
                            (controller, url, isReload) async {
                              final revision = _navigationRevision;
                              final canGoBack = await controller.canGoBack();
                              final canGoForward = await controller.canGoForward();
                              if (!mounted || revision != _navigationRevision) {
                                return;
                              }
                              final urlString = url?.toString();
                              setState(() {
                                _currentUrl = urlString ?? '';
                                _canGoBack = canGoBack;
                                _canGoForward = canGoForward;
                                _historyStateSettled = true;
                              });
                            },
                        onTitleChanged: (controller, title) {
                          if (title != null && title.isNotEmpty) {
                            setState(() => _currentTitle = title);
                          }
                        },
                        onDownloadStarting: (controller, request) {
                          final url = request.url.toString();
                          ref
                              .read(downloadProvider.notifier)
                              .startDownload(
                                url: url,
                                suggestedFilename: request.suggestedFilename,
                                mimeType: request.mimeType,
                                contentLength: request.contentLength,
                              );
                          return null;
                        },
                      ),
                      getController: () => _controller,
                    ),
                  ),
                  if (_webViewSnapshot != null)
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: Image.memory(
                          _webViewSnapshot!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 允许 WebView 内部加载的 scheme
  static const _allowedSchemes = {'http', 'https', 'about', 'data', 'blob'};

  /// 拦截 URL 加载：对非 HTTP(S) 的应用链接弹出确认对话框
  Future<NavigationActionPolicy> _shouldOverrideUrlLoading(
    InAppWebViewController controller,
    NavigationAction navigationAction,
  ) async {
    final url = navigationAction.request.url;
    if (url == null) return NavigationActionPolicy.ALLOW;

    final scheme = url.scheme.toLowerCase();
    if (_allowedSchemes.contains(scheme)) {
      return NavigationActionPolicy.ALLOW;
    }
    if (scheme == 'javascript') {
      return NavigationActionPolicy.CANCEL;
    }
    if (scheme == 'fluxdo' || scheme == 'discourse') {
      DeepLinkService.instance.handleUri(url);
      return NavigationActionPolicy.CANCEL;
    }

    final urlString = url.toString();
    if (!mounted) return NavigationActionPolicy.CANCEL;
    final appInfo = await AppLinkService.resolveAppLink(urlString);
    if (!mounted) return NavigationActionPolicy.CANCEL;

    final confirmed = await showAppLinkConfirmDialog(
      context,
      urlString,
      appName: appInfo.appName,
      appIcon: appInfo.appIcon,
    );
    if (confirmed == true) {
      final success = await AppLinkService.launchAppLink(urlString);
      if (!success && mounted) {
        ToastService.showError(S.current.webview_noAppForLink);
      }
    }
    return NavigationActionPolicy.CANCEL;
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'toggle_bookmark':
        _toggleBookmark();
        break;
      case 'copy_url':
        _copyUrl();
        break;
      case 'clear_site_cookies':
        unawaited(_showSiteCookieCleanup());
        break;
      case 'open_external':
        _openInExternalBrowser();
        break;
    }
  }

  Future<void> _showUrlInput() async {
    final snapshot = await _controller?.takeScreenshot();
    if (!mounted) return;
    if (snapshot != null) {
      setState(() => _webViewSnapshot = snapshot);
    }

    final textController = TextEditingController(text: _currentUrl);
    final focusNode = FocusNode();
    try {
      await showAppDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(S.current.webview_inputUrl),
          content: TextField(
            controller: textController,
            focusNode: focusNode,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: 'https://',
              suffixIcon: IconButton(
                icon: const Icon(Symbols.clear_rounded, size: 18),
                onPressed: () => textController.clear(),
              ),
            ),
            onSubmitted: (value) {
              Navigator.pop(ctx);
              _navigateToUrl(value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(S.current.common_cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _navigateToUrl(textController.text);
              },
              child: Text(S.current.webview_go),
            ),
          ],
        ),
      );
    } finally {
      focusNode.dispose();
      textController.dispose();
      if (mounted && _webViewSnapshot != null) {
        setState(() => _webViewSnapshot = null);
      }
    }
  }

  Future<void> _showSiteCookieCleanup() async {
    final uri = Uri.tryParse(_currentUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return;
    }

    final currentHost = uri.host.toLowerCase();
    final hosts = await SiteCookieCleanupService.instance.discoverRelatedHosts(
      _currentUrl,
    );
    if (!mounted || hosts.isEmpty) return;

    final selected = <String>{currentHost};
    final snapshot = await _controller?.takeScreenshot();
    if (!mounted) return;
    if (snapshot != null) {
      setState(() => _webViewSnapshot = snapshot);
    }

    try {
      final confirmed = await showAppDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Cookie'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420, minWidth: 320),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final host in hosts)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: selected.contains(host),
                        title: Text(host),
                        secondary: host == currentHost
                            ? const Icon(Symbols.language_rounded)
                            : null,
                        onChanged: host == currentHost
                            ? null
                            : (value) {
                                setDialogState(() {
                                  if (value == true) {
                                    selected.add(host);
                                  } else {
                                    selected.remove(host);
                                  }
                                });
                              },
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.l10n.common_cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(context.l10n.common_clear),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true) return;

      await SiteCookieCleanupService.instance.clearHosts(selected);
      if (!mounted) return;
      await _controller?.reload();
      ToastService.showSuccess('Cookie (${selected.length})');
    } catch (e) {
      if (mounted) {
        ToastService.showError(context.l10n.common_clearFailed(e.toString()));
      }
    } finally {
      if (mounted && _webViewSnapshot != null) {
        setState(() => _webViewSnapshot = null);
      }
    }
  }

  void _navigateToUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  void _toggleBookmark() {
    if (_currentUrl.isEmpty) return;
    final added = ref
        .read(webBookmarkProvider.notifier)
        .toggle(_currentUrl, _currentTitle);
    ToastService.showSuccess(
      added
          ? S.current.webview_bookmarkAdded
          : S.current.webview_bookmarkRemoved,
    );
  }

  Future<void> _handleBackNavigation() async {
    final controller = _controller;
    if (controller == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final canGoBack = await controller.canGoBack();
    if (canGoBack) {
      await controller.goBack();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _copyUrl() async {
    if (_currentUrl.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: _currentUrl));
      if (mounted) {
        ToastService.showSuccess(S.current.common_linkCopied);
      }
    }
  }

  Future<void> _openInExternalBrowser() async {
    if (_currentUrl.isEmpty) return;
    try {
      final success = await launchInExternalBrowser(_currentUrl);
      if (!success && mounted) {
        ToastService.showError(S.current.webview_cannotOpenBrowser);
      }
    } catch (e) {
      if (mounted) {
        ToastService.showError(S.current.webview_openFailed(e.toString()));
      }
    }
  }
}
