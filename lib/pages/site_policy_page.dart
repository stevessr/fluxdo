import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluxdo_render/fluxdo_render.dart';

import '../models/site_policy_document.dart';
import '../providers/discourse_providers.dart';
import '../utils/link_launcher.dart';
import '../utils/url_helper.dart';
import '../widgets/common/site_info_tabs.dart';
import 'site_about_page.dart';
import 'webview_page.dart';

/// Native Guidelines / Terms of Service / Privacy document reader.
///
/// Discourse StaticController renders cooked topic HTML for these URLs when
/// X-Requested-With is XMLHttpRequest. There is no /guidelines.json or similar
/// API. Fetch the actual site page instead of bundling legal text.
class SitePolicyPage extends ConsumerStatefulWidget {
  const SitePolicyPage({
    super.key,
    required this.kind,
    this.isActive = true,
  });

  final SitePolicyKind kind;
  final bool isActive;

  @override
  ConsumerState<SitePolicyPage> createState() => _SitePolicyPageState();
}

class _SitePolicyPageState extends ConsumerState<SitePolicyPage> {
  SitePolicyDocument? _document;
  List<GlobalKey> _sectionKeys = [];
  bool _loading = false;
  Object? _error;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  String _tr(String zh, String en) => _zh ? zh : en;

  String get _title => switch (widget.kind) {
    SitePolicyKind.guidelines => _tr('准则', 'Guidelines'),
    SitePolicyKind.terms => _tr('服务条款', 'Terms of Service'),
    SitePolicyKind.privacy => _tr('隐私', 'Privacy'),
  };

  @override
  void initState() {
    super.initState();
    if (widget.isActive) scheduleMicrotask(_load);
  }

  @override
  void didUpdateWidget(covariant SitePolicyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) {
      _document = null;
      _error = null;
      _sectionKeys = [];
      scheduleMicrotask(_load);
    } else if (!oldWidget.isActive && widget.isActive && _document == null) {
      scheduleMicrotask(_load);
    }
  }

  Future<void> _load() async {
    if (!mounted || _loading) return;
    final requestedKind = widget.kind;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await ref.read(discourseServiceProvider).dio.get<String>(
        '/' + requestedKind.path,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Accept': 'text/html',
            'X-Requested-With': 'XMLHttpRequest',
          },
        ),
      );
      final document = SitePolicyDocument.fromHtml(response.data ?? '');
      if (!mounted || widget.kind != requestedKind) return;
      setState(() {
        _document = document;
        _sectionKeys = List.generate(
          document.sections.length,
          (index) => GlobalKey(debugLabel: 'policy-section-' + '$index'),
        );
      });
    } catch (error) {
      if (!mounted || widget.kind != requestedKind) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectTab(int index) {
    if (index == 0) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SiteAboutPage()),
      );
      return;
    }
    final target = SitePolicyKind.values[index - 1];
    if (target == widget.kind) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SitePolicyPage(kind: target),
      ),
    );
  }

  Future<void> _jumpTo(String fragment) async {
    final id = Uri.decodeComponent(fragment);
    final index = _document?.anchors[id];
    if (index == null || index >= _sectionKeys.length) return;
    final targetContext = _sectionKeys[index].currentContext;
    if (targetContext == null) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.03,
    );
  }

  void _openLink(BuildContext context, String href) {
    final value = href.trim();
    if (value.isEmpty) return;
    if (value.startsWith('#')) {
      unawaited(_jumpTo(value.substring(1)));
      return;
    }

    final uri = Uri.tryParse(UrlHelper.resolveUrl(value));
    if (uri == null) return;
    final sameOrigin = uri.host == Uri.parse(
      UrlHelper.resolveUrl('/'),
    ).host;
    if (sameOrigin && uri.path == '/' + widget.kind.path &&
        uri.fragment.isNotEmpty) {
      unawaited(_jumpTo(uri.fragment));
      return;
    }
    if (sameOrigin && uri.fragment.isEmpty) {
      for (final kind in SitePolicyKind.values) {
        if (uri.path == '/' + kind.path) {
          _selectTab(kind.index + 1);
          return;
        }
      }
      if (uri.path == '/about') {
        _selectTab(0);
        return;
      }
    }

    if (uri.scheme == 'https' ||
        uri.scheme == 'http' ||
        uri.scheme == 'mailto') {
      unawaited(launchContentLink(context, uri.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: _tr('刷新', 'Refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Symbols.refresh_rounded),
          ),
          IconButton(
            tooltip: _tr('查看官方页面', 'View official page'),
            onPressed: () => WebViewPage.open(
              context,
              UrlHelper.resolveUrl('/' + widget.kind.path),
              title: _title,
            ),
            icon: const Icon(Symbols.open_in_new_rounded),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final document = _document;
    if (document == null) {
      if (_loading) {
        return const Center(child: CircularProgressIndicator.adaptive());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Symbols.error_outline_rounded, size: 40),
              const SizedBox(height: 14),
              Text(_tr('无法读取站点文档', 'Unable to load site document')),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error.toString(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: _load,
                child: Text(_tr('重试', 'Retry')),
              ),
            ],
          ),
        ),
      );
    }

    final headings = <(int, SitePolicySection)>[
      for (var i = 0; i < document.sections.length; i++)
        if (document.sections[i].heading?.isNotEmpty ?? false)
          (i, document.sections[i]),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SiteInfoTabs(
              selected: widget.kind.index + 1,
              onSelected: _selectTab,
            ),
            const SizedBox(height: 20),
            Text(
              _title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (headings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                clipBehavior: Clip.antiAlias,
                margin: EdgeInsets.zero,
                child: ExpansionTile(
                  leading: const Icon(Symbols.list_rounded),
                  title: Text(_tr('目录', 'Contents')),
                  children: [
                    for (final item in headings)
                      ListTile(
                        dense: true,
                        title: Text(item.$2.heading ?? ''),
                        onTap: () {
                          final targetContext =
                              _sectionKeys[item.$1].currentContext;
                          if (targetContext != null) {
                            unawaited(Scrollable.ensureVisible(
                              targetContext,
                              duration: const Duration(milliseconds: 300),
                              alignment: 0.03,
                            ));
                          }
                        },
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            for (var i = 0; i < document.sections.length; i++)
              Padding(
                key: _sectionKeys[i],
                padding: const EdgeInsets.only(bottom: 4),
                child: FluxdoRender(
                  cookedHtml: document.sections[i].html,
                  baseTextStyle: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(height: 1.6),
                  linkHandler: _openLink,
                  selectionEnabled: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
