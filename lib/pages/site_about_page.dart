import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/site_about.dart';
import '../models/site_policy_document.dart';
import '../widgets/common/site_info_tabs.dart';
import '../providers/discourse_providers.dart';
import '../services/discourse_cache_manager.dart';
import '../utils/url_helper.dart';
import '../widgets/common/smart_avatar.dart';
import 'user_profile_page.dart';
import 'webview_page.dart';
import 'site_policy_page.dart';

/// Native rendering of the public Discourse /about page.
///
/// This is intentionally separate from AboutPage, which describes the FluxDO
/// application. Data and visible staff come from /about.json, never a snapshot
/// of the forum's statistics or personnel.
class SiteAboutPage extends ConsumerStatefulWidget {
  const SiteAboutPage({super.key, this.isActive = true});

  final bool isActive;

  @override
  ConsumerState<SiteAboutPage> createState() => _SiteAboutPageState();
}

class _SiteAboutPageState extends ConsumerState<SiteAboutPage> {
  static final _numberFormatter = NumberFormat.decimalPattern('en');

  SiteAboutData? _data;
  Object? _error;
  bool _loading = false;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  String _tr(String zh, String en) => _zh ? zh : en;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) scheduleMicrotask(_load);
  }

  @override
  void didUpdateWidget(covariant SiteAboutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive && _data == null) {
      scheduleMicrotask(_load);
    }
  }

  Future<void> _load() async {
    if (!mounted || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ref
          .read(discourseServiceProvider)
          .dio
          .get<dynamic>('/about.json');
      if (response.data is! Map) {
        throw const FormatException('Unexpected /about.json response');
      }
      final about = SiteAboutData.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
      if (!mounted) return;
      setState(() => _data = about);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openSection(String path, String title) {
    WebViewPage.open(
      context,
      UrlHelper.resolveUrl(path),
      title: title,
    );
  }

  void _openUser(SiteAboutUser user) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfilePage(username: user.username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('关于 LINUX DO', 'About LINUX DO')),
        actions: [
          IconButton(
            icon: const Icon(Symbols.refresh_rounded),
            tooltip: _tr('刷新', 'Refresh'),
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            icon: const Icon(Symbols.open_in_new_rounded),
            tooltip: _tr('查看官方页面', 'View official page'),
            onPressed: () => _openSection(
              '/about',
              _tr('关于 LINUX DO', 'About LINUX DO'),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final data = _data;
    if (data == null) {
      if (_loading) {
        return const Center(child: CircularProgressIndicator.adaptive());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.error_outline_rounded,
                size: 42,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(_tr('站点信息加载失败', 'Could not load site information')),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error.toString(),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _load,
                child: Text(_tr('重试', 'Retry')),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildNavigation(),
          const SizedBox(height: 20),
          if (data.bannerUrl.isNotEmpty) ...[
            _buildBanner(data.bannerUrl),
            const SizedBox(height: 16),
          ],
          Text(
            data.title.isEmpty ? 'LINUX DO' : data.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (data.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              data.description,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
          const SizedBox(height: 20),
          _buildOverview(data),
          if (data.extendedDescription.isNotEmpty) ...[
            const SizedBox(height: 24),
            _sectionTitle(_tr('关于', 'About')),
            const SizedBox(height: 10),
            SelectableText(
              data.extendedDescription,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: 1.65,
              ),
            ),
          ],
          if (data.adminIds.isNotEmpty) ...[
            const SizedBox(height: 26),
            _buildStaff(
              _tr('管理员', 'Admins'),
              data.admins,
            ),
          ],
          if (data.moderatorIds.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildStaff(
              _tr('版主', 'Moderators'),
              data.moderators,
            ),
          ],
          const SizedBox(height: 26),
          _sectionTitle(_tr('站点统计', 'Site Statistics')),
          const SizedBox(height: 10),
          _buildStatistics(data),
          if (data.contactEmail.isNotEmpty) ...[
            const SizedBox(height: 24),
            _sectionTitle(_tr('联系', 'Contact')),
            const SizedBox(height: 8),
            SelectableText(data.contactEmail),
          ],
        ],
      ),
    );
  }

  Widget _buildNavigation() => SiteInfoTabs(
    selected: 0,
    onSelected: (index) {
      final kind = SitePolicyKind.values[index - 1];
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SitePolicyPage(kind: kind)),
      );
    },
  );

  Widget _buildBanner(String url) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image(
        image: sharedImageProvider(UrlHelper.resolveUrlWithCdn(url)),
        height: 152,
        fit: BoxFit.cover,
        errorBuilder: (_, error, stack) => Container(
          height: 152,
          alignment: Alignment.center,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            Symbols.image_rounded,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildOverview(SiteAboutData data) {
    final createdAt = data.createdAt;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (data.stat('users', 'count') case final int members)
          _summaryTile(
            Symbols.groups_rounded,
            _tr('成员', 'Members'),
            _numberFormatter.format(members),
          ),
        _summaryTile(
          Symbols.admin_panel_settings_rounded,
          _tr('管理员', 'Admins'),
          _numberFormatter.format(data.adminIds.length),
        ),
        _summaryTile(
          Symbols.shield_rounded,
          _tr('版主', 'Moderators'),
          _numberFormatter.format(data.moderatorIds.length),
        ),
        if (createdAt != null)
          _summaryTile(
            Symbols.calendar_month_rounded,
            _tr('创建日期', 'Created'),
            DateFormat('yyyy-MM-dd').format(createdAt.toLocal()),
          ),
      ],
    );
  }

  Widget _summaryTile(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(
    title,
    style: Theme.of(context).textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _buildStaff(String heading, List<SiteAboutUser> people) {
    if (people.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(heading),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final person in people)
                ListTile(
                  leading: SmartAvatar(
                    imageUrl: person.avatarTemplate.isEmpty
                        ? null
                        : UrlHelper.resolveUrl(
                            person.avatarPath(),
                          ),
                    radius: 22,
                    fallbackText: person.username,
                  ),
                  title: Text(
                    person.name.isEmpty
                        ? person.username
                        : person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    person.title.isEmpty
                        ? '@' + person.username
                        : '@' + person.username + ' · ' + person.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Symbols.chevron_right_rounded),
                  onTap: () => _openUser(person),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatistics(SiteAboutData data) {
    final names = <String, String>{
      'topics': _tr('话题', 'Topics'),
      'posts': _tr('帖子', 'Posts'),
      'users': _tr('注册', 'Sign-ups'),
      'active_users': _tr('活跃用户', 'Active users'),
      'likes': _tr('赞', 'Likes'),
    };
    final columns = <String, String>{
      'count': _tr('总计', 'All time'),
      'last_day': _tr('24 小时', '24 hours'),
      '7_days': _tr('7 天', '7 days'),
      '30_days': _tr('30 天', '30 days'),
    };
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 48,
            dataRowMinHeight: 44,
            dataRowMaxHeight: 52,
            headingTextStyle: theme.textTheme.labelLarge,
            columns: [
              DataColumn(label: Text(_tr('项目', 'Metric'))),
              for (final period in columns.values)
                DataColumn(label: Text(period), numeric: true),
            ],
            rows: [
              for (final metric in names.entries)
                DataRow(
                  cells: [
                    DataCell(Text(metric.value)),
                    for (final period in columns.keys)
                      DataCell(
                        Text(
                          _statText(data.stat(metric.key, period)),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _statText(int? value) =>
      value == null ? '—' : _numberFormatter.format(value);
}
