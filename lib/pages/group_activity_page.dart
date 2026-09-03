import 'dart:collection';

import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discourse_parity_providers.dart';
import '../providers/discourse_providers.dart';
import '../utils/time_utils.dart';
import '../utils/url_helper.dart';
import '../widgets/common/error_view.dart';
import '../widgets/common/relative_time_text.dart';
import '../widgets/common/smart_avatar.dart';
import '../widgets/content/collapsed_html_content.dart';
import 'group_requests_page.dart';
import 'topic_detail_page/topic_detail_page.dart';

/// Native Discourse group activity view (`/g/:name/activity/posts|mentions`).
///
/// Upstream uses GroupPostSerializer and cursor pagination via `before_post_id`.
/// The parser intentionally ignores unknown fields rather than rejecting the
/// payload, so site/plugin serializer additions remain forward-compatible.
class GroupActivityPage extends ConsumerStatefulWidget {
  const GroupActivityPage({
    super.key,
    required this.groupName,
    this.groupLabel,
  });

  final String groupName;
  final String? groupLabel;

  @override
  ConsumerState<GroupActivityPage> createState() => _GroupActivityPageState();
}

class _GroupActivityPageState extends ConsumerState<GroupActivityPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final Map<GroupActivityKind, List<_GroupActivityEntry>> _entries = {};
  final Map<GroupActivityKind, bool> _loading = {};
  final Map<GroupActivityKind, bool> _loadingMore = {};
  final Map<GroupActivityKind, bool> _hasMore = {};
  final Map<GroupActivityKind, Object?> _errors = {};
  int? _manageableGroupId;

  static const _kinds = [
    GroupActivityKind.posts,
    GroupActivityKind.mentions,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _kinds.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    Future.microtask(() {
      _refresh(GroupActivityKind.posts);
      _loadManagementCapability();
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadManagementCapability() async {
    try {
      final group = await ref.read(discourseServiceProvider).fetchGroup(
            widget.groupName,
          );
      if (!mounted) return;
      setState(() {
        _manageableGroupId = group.canManageMembers ? group.id : null;
      });
    } catch (_) {
      // Activity itself may still be visible even when a separate group refresh
      // fails. Do not turn an optional management capability probe into a page
      // loading failure.
    }
  }

  void _openMembershipRequests() {
    final groupId = _manageableGroupId;
    if (groupId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupRequestsPage(
          groupId: groupId,
          groupName: widget.groupName,
          groupLabel: widget.groupLabel,
        ),
      ),
    );
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final kind = _kinds[_tabController.index];
    if (!_entries.containsKey(kind) && _loading[kind] != true) {
      _refresh(kind);
    }
  }

  Future<List<_GroupActivityEntry>> _fetch(
    GroupActivityKind kind, {
    int? beforePostId,
  }) async {
    final payload = await ref.read(
      groupActivityProvider(
        GroupActivityQuery(
          groupName: widget.groupName,
          kind: kind,
          beforePostId: beforePostId,
        ),
      ).future,
    );
    final rawPosts = payload['posts'] as List? ?? const [];
    return rawPosts
        .whereType<Map>()
        .map((raw) => _GroupActivityEntry.fromJson(
              Map<String, dynamic>.from(raw),
            ))
        .where((entry) => entry.id > 0 && entry.topicId > 0)
        .toList(growable: false);
  }

  Future<void> _refresh(GroupActivityKind kind) async {
    if (_loading[kind] == true) return;
    setState(() {
      _loading[kind] = true;
      _errors[kind] = null;
    });
    try {
      final next = await _fetch(kind);
      if (!mounted) return;
      setState(() {
        _entries[kind] = next;
        // GroupsController limits the result to 20 entries.
        _hasMore[kind] = next.length >= 20;
      });
    } catch (error) {
      if (mounted) setState(() => _errors[kind] = error);
    } finally {
      if (mounted) setState(() => _loading[kind] = false);
    }
  }

  Future<void> _loadMore(GroupActivityKind kind) async {
    if (_loadingMore[kind] == true || _hasMore[kind] != true) return;
    final current = _entries[kind] ?? const <_GroupActivityEntry>[];
    if (current.isEmpty) return;

    setState(() => _loadingMore[kind] = true);
    try {
      final next = await _fetch(kind, beforePostId: current.last.id);
      if (!mounted) return;
      final byId = LinkedHashMap<int, _GroupActivityEntry>();
      for (final entry in [...current, ...next]) {
        byId[entry.id] = entry;
      }
      setState(() {
        _entries[kind] = byId.values.toList(growable: false);
        _hasMore[kind] = next.length >= 20;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore[kind] = false);
    }
  }

  void _openEntry(_GroupActivityEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TopicDetailPage(
          topicId: entry.topicId,
          initialTitle: entry.topicTitle,
          scrollToPostNumber: entry.postNumber,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupLabel ?? widget.groupName),
        actions: [
          if (_manageableGroupId != null)
            IconButton(
              tooltip: copy.membershipRequests,
              onPressed: _openMembershipRequests,
              icon: const Icon(Icons.how_to_reg_rounded),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: copy.posts),
            Tab(text: copy.mentions),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          for (final kind in _kinds) _buildTab(kind, copy),
        ],
      ),
    );
  }

  Widget _buildTab(GroupActivityKind kind, _GroupActivityCopy copy) {
    final entries = _entries[kind];
    final loading = _loading[kind] == true;
    final error = _errors[kind];

    if (entries == null && loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (entries == null && error != null) {
      return ErrorView(error: error, onRetry: () => _refresh(kind));
    }
    final data = entries ?? const <_GroupActivityEntry>[];

    return RefreshIndicator(
      onRefresh: () => _refresh(kind),
      child: data.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.55,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          kind == GroupActivityKind.mentions
                              ? Symbols.alternate_email_rounded
                              : Symbols.article_rounded,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(copy.empty),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: data.length + 1,
              separatorBuilder: (_, index) =>
                  index < data.length - 1 ? const Divider(height: 1) : const SizedBox.shrink(),
              itemBuilder: (context, index) {
                if (index == data.length) {
                  if (_loadingMore[kind] == true) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator.adaptive()),
                    );
                  }
                  if (_hasMore[kind] == true) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: FilledButton.tonal(
                          onPressed: () => _loadMore(kind),
                          child: Text(copy.loadMore),
                        ),
                      ),
                    );
                  }
                  return const SizedBox(height: 12);
                }

                final entry = data[index];
                return InkWell(
                  onTap: () => _openEntry(entry),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SmartAvatar(
                          imageUrl: entry.avatarUrl,
                          radius: 20,
                          fallbackText: entry.username ?? '?',
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      entry.displayName,
                                      style: Theme.of(context).textTheme.labelLarge,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (entry.createdAt != null)
                                    RelativeTimeText(
                                      dateTime: entry.createdAt!,
                                      style: Theme.of(context).textTheme.labelSmall,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                entry.topicTitle,
                                style: Theme.of(context).textTheme.titleSmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (entry.excerpt?.trim().isNotEmpty == true) ...[
                                const SizedBox(height: 6),
                                CollapsedHtmlContent(
                                  html: entry.excerpt!,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  textStyle: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Symbols.chevron_right_rounded),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _GroupActivityEntry {
  const _GroupActivityEntry({
    required this.id,
    required this.topicId,
    required this.topicTitle,
    this.postNumber,
    this.username,
    this.name,
    this.avatarTemplate,
    this.excerpt,
    this.createdAt,
  });

  final int id;
  final int topicId;
  final String topicTitle;
  final int? postNumber;
  final String? username;
  final String? name;
  final String? avatarTemplate;
  final String? excerpt;
  final DateTime? createdAt;

  String get displayName {
    final value = name?.trim();
    if (value != null && value.isNotEmpty) return value;
    final user = username?.trim();
    return user == null || user.isEmpty ? '—' : user;
  }

  String? get avatarUrl {
    final template = avatarTemplate;
    if (template == null || template.isEmpty) return null;
    return UrlHelper.resolveUrlWithCdn(template.replaceAll('{size}', '96'));
  }

  factory _GroupActivityEntry.fromJson(Map<String, dynamic> json) {
    return _GroupActivityEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      topicId: (json['topic_id'] as num?)?.toInt() ?? 0,
      topicTitle: json['topic_title']?.toString() ?? '',
      postNumber: (json['post_number'] as num?)?.toInt(),
      username: json['username']?.toString(),
      name: json['name']?.toString(),
      avatarTemplate: json['avatar_template']?.toString(),
      excerpt: json['excerpt']?.toString(),
      createdAt: TimeUtils.parseUtcTime(json['created_at']?.toString()),
    );
  }
}

class _GroupActivityCopy {
  const _GroupActivityCopy(this.zh);
  final bool zh;

  String get posts => zh ? '帖子' : 'Posts';
  String get mentions => zh ? '提及' : 'Mentions';
  String get membershipRequests => zh ? '加入申请' : 'Membership requests';
  String get empty => zh ? '暂无内容' : 'Nothing here yet';
  String get loadMore => zh ? '加载更多' : 'Load more';
}

_GroupActivityCopy _copy(BuildContext context) => _GroupActivityCopy(
      Localizations.localeOf(context).languageCode.toLowerCase() == 'zh',
    );
