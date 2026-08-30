import 'package:app_icons/app_icons.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/network/discourse_dio.dart';
import '../utils/time_utils.dart';
import 'invite_links_page.dart';

/// 与 Discourse `/u/:username/invited` 对齐的邀请记录页。
///
/// 原版将邀请分成待处理、已兑换和已过期三类；这里直接复用同一组 JSON
/// 接口，避免把“查看邀请”错误地等同于“生成一个邀请链接”。
class UserInvitesPage extends StatefulWidget {
  const UserInvitesPage({super.key, required this.username});

  final String username;

  @override
  State<UserInvitesPage> createState() => _UserInvitesPageState();
}

class _UserInvitesPageState extends State<UserInvitesPage>
    with SingleTickerProviderStateMixin {
  static const _pageSizeHint = 30;

  late final TabController _tabController;
  final Dio _dio = DiscourseDio.create();
  final Map<_InviteFilter, _InviteBucket> _buckets = {
    for (final filter in _InviteFilter.values) filter: _InviteBucket(),
  };
  Map<_InviteFilter, int> _counts = const {};
  bool _canSeeInviteDetails = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _InviteFilter.values.length, vsync: this);
    for (final filter in _InviteFilter.values) {
      _load(filter, refresh: true);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dio.close(force: true);
    super.dispose();
  }

  Future<void> _load(_InviteFilter filter, {bool refresh = false}) async {
    final bucket = _buckets[filter]!;
    if (bucket.loading) return;
    if (!refresh && !bucket.hasMore) return;

    setState(() {
      bucket.loading = true;
      bucket.error = null;
      if (refresh) {
        bucket.hasMore = true;
      }
    });

    try {
      final offset = refresh ? 0 : bucket.items.length;
      final response = await _dio.get<Map<String, dynamic>>(
        '/u/${Uri.encodeComponent(widget.username)}/invited.json',
        queryParameters: {
          'filter': filter.apiValue,
          if (offset > 0) 'offset': offset,
        },
      );
      final json = response.data ?? const <String, dynamic>{};
      final rawInvites = json['invites'];
      final nextItems = rawInvites is List
          ? rawInvites
                .whereType<Map>()
                .map((e) => _InviteRecord.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : <_InviteRecord>[];

      final rawCounts = json['counts'];
      final counts = <_InviteFilter, int>{};
      if (rawCounts is Map) {
        for (final candidate in _InviteFilter.values) {
          final value = rawCounts[candidate.apiValue];
          if (value is int) counts[candidate] = value;
          if (value is num) counts[candidate] = value.toInt();
        }
      }

      if (!mounted) return;
      setState(() {
        if (refresh) {
          bucket.items
            ..clear()
            ..addAll(nextItems);
        } else {
          final existing = bucket.items.map((item) => item.identity).toSet();
          bucket.items.addAll(
            nextItems.where((item) => existing.add(item.identity)),
          );
        }
        // Discourse 的 invited 接口使用 offset 分页。少于常规页大小即可
        // 判定结束；若服务端改变 page size，下一次滚到底得到空页后也会停止。
        bucket.hasMore = nextItems.length >= _pageSizeHint;
        bucket.loading = false;
        bucket.loaded = true;
        _canSeeInviteDetails = json['can_see_invite_details'] != false;
        if (counts.isNotEmpty) _counts = counts;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        bucket.loading = false;
        bucket.loaded = true;
        bucket.error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_strings(context).title),
        actions: [
          IconButton(
            tooltip: _strings(context).create,
            icon: const Icon(Symbols.person_add_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const InviteLinksPage()),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            for (final filter in _InviteFilter.values)
              Tab(
                text: _tabText(context, filter),
                icon: Icon(filter.icon, size: 20),
              ),
          ],
        ),
      ),
      body: !_canSeeInviteDetails
          ? _PermissionView(strings: _strings(context))
          : TabBarView(
              controller: _tabController,
              children: [
                for (final filter in _InviteFilter.values)
                  _buildList(context, theme, filter),
              ],
            ),
    );
  }

  String _tabText(BuildContext context, _InviteFilter filter) {
    final strings = _strings(context);
    final count = _counts[filter];
    final label = strings.label(filter);
    return count == null ? label : '$label ($count)';
  }

  Widget _buildList(
    BuildContext context,
    ThemeData theme,
    _InviteFilter filter,
  ) {
    final bucket = _buckets[filter]!;
    final strings = _strings(context);

    if (!bucket.loaded && bucket.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (bucket.error != null && bucket.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.error_outline_rounded,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                strings.loadFailed,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _load(filter, refresh: true),
                icon: const Icon(Symbols.refresh_rounded),
                label: Text(strings.retry),
              ),
            ],
          ),
        ),
      );
    }

    if (bucket.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(filter, refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
            Icon(
              filter.icon,
              size: 56,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                strings.empty(filter),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(filter, refresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical &&
              notification.metrics.extentAfter < 320 &&
              !bucket.loading &&
              bucket.hasMore) {
            _load(filter);
          }
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount: bucket.items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == bucket.items.length) {
              if (bucket.loading) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (bucket.error != null) {
                return TextButton.icon(
                  onPressed: () => _load(filter),
                  icon: const Icon(Symbols.refresh_rounded),
                  label: Text(strings.retry),
                );
              }
              return const SizedBox(height: 8);
            }
            return _InviteCard(
              record: bucket.items[index],
              filter: filter,
              strings: strings,
            );
          },
        ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.record,
    required this.filter,
    required this.strings,
  });

  final _InviteRecord record;
  final _InviteFilter filter;
  final _InviteStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = record.displayTitle(strings);
    final subtitle = record.description?.trim();
    final date = filter == _InviteFilter.redeemed
        ? record.redeemedAt
        : record.createdAt;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    filter.icon,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (record.redemptionCount != null ||
                    record.maxRedemptionsAllowed != null)
                  _InfoChip(
                    icon: Symbols.group_rounded,
                    text: strings.redemptions(
                      record.redemptionCount ?? 0,
                      record.maxRedemptionsAllowed,
                    ),
                  ),
                if (record.expiresAt != null)
                  _InfoChip(
                    icon: Symbols.event_rounded,
                    text: strings.expires(
                      TimeUtils.formatDetailTime(record.expiresAt),
                    ),
                  ),
                if (date != null)
                  _InfoChip(
                    icon: Symbols.schedule_rounded,
                    text: filter == _InviteFilter.redeemed
                        ? strings.redeemedAt(TimeUtils.formatDetailTime(date))
                        : strings.createdAt(TimeUtils.formatDetailTime(date)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionView extends StatelessWidget {
  const _PermissionView({required this.strings});

  final _InviteStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.lock_rounded,
              size: 52,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(strings.permissionDenied, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

enum _InviteFilter { pending, redeemed, expired }

extension on _InviteFilter {
  String get apiValue => switch (this) {
    _InviteFilter.pending => 'pending',
    _InviteFilter.redeemed => 'redeemed',
    _InviteFilter.expired => 'expired',
  };

  IconData get icon => switch (this) {
    _InviteFilter.pending => Symbols.hourglass_top_rounded,
    _InviteFilter.redeemed => Symbols.how_to_reg_rounded,
    _InviteFilter.expired => Symbols.event_busy_rounded,
  };
}

class _InviteBucket {
  final List<_InviteRecord> items = [];
  bool loaded = false;
  bool loading = false;
  bool hasMore = true;
  Object? error;
}

class _InviteRecord {
  const _InviteRecord({
    this.id,
    this.inviteKey,
    this.link,
    this.description,
    this.email,
    this.domain,
    this.username,
    this.name,
    this.createdAt,
    this.expiresAt,
    this.redeemedAt,
    this.maxRedemptionsAllowed,
    this.redemptionCount,
  });

  final int? id;
  final String? inviteKey;
  final String? link;
  final String? description;
  final String? email;
  final String? domain;
  final String? username;
  final String? name;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final DateTime? redeemedAt;
  final int? maxRedemptionsAllowed;
  final int? redemptionCount;

  String get identity => [
    id,
    inviteKey,
    username,
    email,
    domain,
    redeemedAt?.millisecondsSinceEpoch,
  ].join(':');

  factory _InviteRecord.fromJson(Map<String, dynamic> json) {
    final user = json['user'] is Map
        ? Map<String, dynamic>.from(json['user'] as Map)
        : const <String, dynamic>{};
    return _InviteRecord(
      id: _asInt(json['id']),
      inviteKey: json['invite_key'] as String?,
      link: json['link'] as String?,
      description: json['description'] as String?,
      email: json['email'] as String?,
      domain: json['domain'] as String?,
      username: user['username'] as String?,
      name: user['name'] as String?,
      createdAt: TimeUtils.parseUtcTime(json['created_at'] as String?),
      expiresAt: TimeUtils.parseUtcTime(json['expires_at'] as String?),
      redeemedAt: TimeUtils.parseUtcTime(json['redeemed_at'] as String?),
      maxRedemptionsAllowed: _asInt(json['max_redemptions_allowed']),
      redemptionCount: _asInt(json['redemption_count']),
    );
  }

  String displayTitle(_InviteStrings strings) {
    if (username != null && username!.isNotEmpty) {
      if (name != null && name!.isNotEmpty) return '$name (@$username)';
      return '@$username';
    }
    if (email != null && email!.isNotEmpty) return email!;
    if (domain != null && domain!.isNotEmpty) return domain!;
    if (link != null && link!.isNotEmpty) return link!;
    if (inviteKey != null && inviteKey!.isNotEmpty) return inviteKey!;
    return strings.inviteFallback(id);
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

/// 本页暂不新增生成代码依赖的 ARB getter，避免为了三个 Discourse 状态词
/// 扩大 generated l10n diff；仍覆盖项目现有的四类语言环境。
_InviteStrings _strings(BuildContext context) {
  final locale = Localizations.localeOf(context);
  final tag = locale.toLanguageTag().toLowerCase();
  if (tag.startsWith('zh-hk')) return const _InviteStrings.zhHk();
  if (tag.startsWith('zh-tw')) return const _InviteStrings.zhTw();
  if (tag.startsWith('zh')) return const _InviteStrings.zh();
  return const _InviteStrings.en();
}

class _InviteStrings {
  const _InviteStrings({
    required this.title,
    required this.create,
    required this.pending,
    required this.redeemed,
    required this.expired,
    required this.pendingEmpty,
    required this.redeemedEmpty,
    required this.expiredEmpty,
    required this.loadFailed,
    required this.retry,
    required this.permissionDenied,
    required this.inviteLabel,
    required this.redemptionsTemplate,
    required this.expiresTemplate,
    required this.createdTemplate,
    required this.redeemedAtTemplate,
  });

  const _InviteStrings.zh()
      : this(
          title: '邀请',
          create: '创建邀请',
          pending: '待处理',
          redeemed: '已兑换',
          expired: '已过期',
          pendingEmpty: '暂无待处理邀请',
          redeemedEmpty: '暂无已兑换邀请',
          expiredEmpty: '暂无已过期邀请',
          loadFailed: '加载邀请记录失败',
          retry: '重试',
          permissionDenied: '当前账号无权查看邀请详情',
          inviteLabel: '邀请',
          redemptionsTemplate: '已使用 {used}/{max}',
          expiresTemplate: '到期 {time}',
          createdTemplate: '创建 {time}',
          redeemedAtTemplate: '兑换 {time}',
        );

  const _InviteStrings.zhHk()
      : this(
          title: '邀請',
          create: '建立邀請',
          pending: '待處理',
          redeemed: '已兌換',
          expired: '已過期',
          pendingEmpty: '暫無待處理邀請',
          redeemedEmpty: '暫無已兌換邀請',
          expiredEmpty: '暫無已過期邀請',
          loadFailed: '載入邀請記錄失敗',
          retry: '重試',
          permissionDenied: '目前帳號無權查看邀請詳情',
          inviteLabel: '邀請',
          redemptionsTemplate: '已使用 {used}/{max}',
          expiresTemplate: '到期 {time}',
          createdTemplate: '建立 {time}',
          redeemedAtTemplate: '兌換 {time}',
        );

  const _InviteStrings.zhTw()
      : this(
          title: '邀請',
          create: '建立邀請',
          pending: '待處理',
          redeemed: '已兌換',
          expired: '已過期',
          pendingEmpty: '暫無待處理邀請',
          redeemedEmpty: '暫無已兌換邀請',
          expiredEmpty: '暫無已過期邀請',
          loadFailed: '載入邀請紀錄失敗',
          retry: '重試',
          permissionDenied: '目前帳號無權查看邀請詳情',
          inviteLabel: '邀請',
          redemptionsTemplate: '已使用 {used}/{max}',
          expiresTemplate: '到期 {time}',
          createdTemplate: '建立 {time}',
          redeemedAtTemplate: '兌換 {time}',
        );

  const _InviteStrings.en()
      : this(
          title: 'Invites',
          create: 'Create invite',
          pending: 'Pending',
          redeemed: 'Redeemed',
          expired: 'Expired',
          pendingEmpty: 'No pending invites',
          redeemedEmpty: 'No redeemed invites',
          expiredEmpty: 'No expired invites',
          loadFailed: 'Failed to load invite history',
          retry: 'Retry',
          permissionDenied: 'This account cannot view invite details',
          inviteLabel: 'Invite',
          redemptionsTemplate: 'Used {used}/{max}',
          expiresTemplate: 'Expires {time}',
          createdTemplate: 'Created {time}',
          redeemedAtTemplate: 'Redeemed {time}',
        );

  final String title;
  final String create;
  final String pending;
  final String redeemed;
  final String expired;
  final String pendingEmpty;
  final String redeemedEmpty;
  final String expiredEmpty;
  final String loadFailed;
  final String retry;
  final String permissionDenied;
  final String inviteLabel;
  final String redemptionsTemplate;
  final String expiresTemplate;
  final String createdTemplate;
  final String redeemedAtTemplate;

  String label(_InviteFilter filter) => switch (filter) {
    _InviteFilter.pending => pending,
    _InviteFilter.redeemed => redeemed,
    _InviteFilter.expired => expired,
  };

  String empty(_InviteFilter filter) => switch (filter) {
    _InviteFilter.pending => pendingEmpty,
    _InviteFilter.redeemed => redeemedEmpty,
    _InviteFilter.expired => expiredEmpty,
  };

  String inviteFallback(int? id) => id == null ? inviteLabel : '$inviteLabel #$id';

  String redemptions(int used, int? max) => redemptionsTemplate
      .replaceAll('{used}', '$used')
      .replaceAll('{max}', max == null ? '∞' : '$max');

  String expires(String time) => expiresTemplate.replaceAll('{time}', time);
  String createdAt(String time) => createdTemplate.replaceAll('{time}', time);
  String redeemedAt(String time) =>
      redeemedAtTemplate.replaceAll('{time}', time);
}
