import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';

import '../models/site_policy_document.dart';
import '../utils/url_helper.dart';
import '../widgets/common/site_info_tabs.dart';
import 'site_about_page.dart';
import 'site_policy_page.dart';
import 'webview_page.dart';

/// The site's four public information sections share one navigation route.
/// Switching sections changes content, never pushes another page.
enum SiteInfoSection { about, guidelines, terms, privacy }

class SiteInfoPage extends StatefulWidget {
  const SiteInfoPage({
    super.key,
    this.initialSection = SiteInfoSection.about,
    this.isActive = true,
  });

  final SiteInfoSection initialSection;
  final bool isActive;

  @override
  State<SiteInfoPage> createState() => _SiteInfoPageState();
}

class _SiteInfoPageState extends State<SiteInfoPage> {
  late SiteInfoSection _section;
  int _refreshToken = 0;
  int _fragmentRequestId = 0;
  String? _requestedFragment;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
  }

  @override
  void didUpdateWidget(covariant SiteInfoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSection != oldWidget.initialSection) {
      _section = widget.initialSection;
      _requestedFragment = null;
    }
  }

  String _title(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return (zh
        ? const ['关于', '准则', '服务条款', '隐私']
        : const ['About', 'Guidelines', 'Terms of Service', 'Privacy']
    )[_section.index];
  }

  String get _sitePath => _section == SiteInfoSection.about
      ? '/about'
      : '/${SitePolicyKind.values[_section.index - 1].path}';

  void _selectTab(int index, String? fragment) {
    if (index < 0 || index >= SiteInfoSection.values.length) return;
    if (index == _section.index && (fragment == null || fragment.isEmpty)) {
      return;
    }
    setState(() {
      _section = SiteInfoSection.values[index];
      _requestedFragment = fragment;
      _fragmentRequestId++;
    });
  }

  void _refresh() {
    setState(() => _refreshToken++);
  }

  void _openOfficial() {
    WebViewPage.open(
      context,
      UrlHelper.resolveUrl(_sitePath),
      title: _title(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return const SizedBox.shrink();
    final zh = Localizations.localeOf(context).languageCode == 'zh';

    return Scaffold(
      appBar: AppBar(
        title: Text(_title(context)),
        actions: [
          IconButton(
            tooltip: zh ? '刷新' : 'Refresh',
            icon: const Icon(Symbols.refresh_rounded),
            onPressed: _refresh,
          ),
          IconButton(
            tooltip: zh ? '查看官方页面' : 'View official page',
            icon: const Icon(Symbols.open_in_new_rounded),
            onPressed: _openOfficial,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SiteInfoTabs(
                selected: _section.index,
                onSelected: (index) => _selectTab(index, null),
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _section.index,
              children: [
                SiteAboutPage(
                  isActive: _section == SiteInfoSection.about,
                  refreshToken: _refreshToken,
                ),
                for (final kind in SitePolicyKind.values)
                  SitePolicyPage(
                    kind: kind,
                    isActive: _section.index == kind.index + 1,
                    refreshToken: _refreshToken,
                    onNavigate: _selectTab,
                    requestedFragment:
                        _section.index == kind.index + 1
                            ? _requestedFragment
                            : null,
                    fragmentRequestId: _fragmentRequestId,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
