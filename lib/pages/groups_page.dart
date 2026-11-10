import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group.dart';
import '../providers/discourse_providers.dart';
import '../widgets/common/flair_badge.dart';
import '../widgets/common/group_leave_confirmation_dialog.dart';
import 'group_page.dart';

/// Discourse 原生群组目录（网页 `/g`，API `/groups.json`）。
class GroupsPage extends ConsumerStatefulWidget {
  const GroupsPage({super.key, this.isActive = true});

  final bool isActive;

  @override
  ConsumerState<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends ConsumerState<GroupsPage> {
  final TextEditingController _filterController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  List<DiscourseGroup> _groups = const [];
  final Set<int> _membershipChanging = <int>{};
  final Set<int> _membershipConfirmationPending = <int>{};
  String _filter = '';
  String _type = '';
  int _nextPage = 0;
  int _total = 0;
  bool _hasMore = false;
  bool _loading = false;
  bool _reloadQueued = false;
  int _membershipRevision = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    if (widget.isActive) scheduleMicrotask(() => _load(reset: true));
  }

  @override
  void didUpdateWidget(covariant GroupsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive && _groups.isEmpty) {
      scheduleMicrotask(() => _load(reset: true));
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    if (!mounted) return;
    if (_loading) {
      if (reset) _reloadQueued = true;
      return;
    }
    if (!reset && !_hasMore) return;

    final page = reset ? 0 : _nextPage;
    final requestedFilter = _filter;
    final requestedType = _type;
    final requestedRevision = _membershipRevision;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await ref
          .read(discourseServiceProvider)
          .fetchGroups(
            page: page,
            filter: requestedFilter.isEmpty ? null : requestedFilter,
            type: requestedType.isEmpty ? null : requestedType,
          );
      if (!mounted ||
          requestedFilter != _filter ||
          requestedType != _type ||
          requestedRevision != _membershipRevision) {
        return;
      }

      final merged = reset
          ? result.groups
          : _mergeGroups(_groups, result.groups);
      setState(() {
        _groups = merged;
        _total = result.total;
        _hasMore = result.hasMore;
        _nextPage = page + 1;
      });
    } catch (error) {
      if (!mounted ||
          requestedFilter != _filter ||
          requestedType != _type ||
          requestedRevision != _membershipRevision) {
        return;
      }
      setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_reloadQueued) {
          _reloadQueued = false;
          scheduleMicrotask(() => _load(reset: true));
        }
      }
    }
  }

  List<DiscourseGroup> _mergeGroups(
    List<DiscourseGroup> oldGroups,
    List<DiscourseGroup> newGroups,
  ) {
    final byId = <int, DiscourseGroup>{};
    for (final group in [...oldGroups, ...newGroups]) {
      byId[group.id] = group;
    }
    return byId.values.toList(growable: false);
  }

  void _maybeLoadMore() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 520 &&
        !_loading &&
        _hasMore) {
      _load(reset: false);
    }
  }

  void _applyFilter() {
    _searchDebounce?.cancel();
    final next = _filterController.text.trim();
    if (next == _filter) return;
    setState(() {
      _filter = next;
      _groups = const [];
      _hasMore = false;
      _nextPage = 0;
    });
    _load(reset: true);
  }

  void _changeType(String type) {
    if (_type == type) return;
    setState(() {
      _type = type;
      _groups = const [];
      _hasMore = false;
      _nextPage = 0;
    });
    _load(reset: true);
  }

  Future<void> _openGroup(DiscourseGroup group) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => GroupPage(groupName: group.name)));
    if (mounted) _load(reset: true);
  }

  Future<void> _changeMembership(
    DiscourseGroup group, {
    required bool join,
  }) async {
    if (_membershipChanging.contains(group.id) ||
        _membershipConfirmationPending.contains(group.id)) {
      return;
    }
    if (join ? !group.canJoin : !group.canLeave) return;

    if (!join) {
      setState(() => _membershipConfirmationPending.add(group.id));
      bool confirmed;
      try {
        confirmed = await confirmLeaveGroup(context, groupLabel: group.label);
      } finally {
        if (mounted) {
          setState(() => _membershipConfirmationPending.remove(group.id));
        }
      }
      if (!confirmed || !mounted) return;
    }

    // The directory can refresh while the confirmation is open.
    final matches = _groups.where((item) => item.id == group.id);
    if (matches.isEmpty) return;
    final latest = matches.first;
    if (_membershipChanging.contains(latest.id) ||
        (join ? !latest.canJoin : !latest.canLeave)) {
      return;
    }

    setState(() => _membershipChanging.add(latest.id));
    try {
      final service = ref.read(discourseServiceProvider);
      if (join) {
        await service.joinGroup(latest.id);
      } else {
        await service.leaveGroup(latest.id);
      }
      if (!mounted) return;

      final currentCount = latest.userCount;
      final nextCount = currentCount == null
          ? null
          : join
          ? currentCount + 1
          : (currentCount > 0 ? currentCount - 1 : 0);
      final updated = latest.copyWith(
        userCount: nextCount,
        isGroupUser: join,
        isGroupOwner: false,
      );
      setState(() {
        _membershipRevision++;
        _groups = [
          for (final item in _groups)
            if (item.id == latest.id) updated else item,
        ];
      });

      final copy = _copy(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(join ? copy.joined : copy.left)));
      // 筛选中的「我的群组」等集合可能改变，始终重新向服务端校准。
      await _load(reset: true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _membershipChanging.remove(group.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return const SizedBox.shrink();
    final copy = _copy(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(copy.title),
        actions: [
          IconButton(
            tooltip: copy.refresh,
            onPressed: _loading ? null : () => _load(reset: true),
            icon: const Icon(Symbols.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final search = SearchBar(
                  key: const ValueKey('groups-search'),
                  controller: _filterController,
                  hintText: copy.searchHint,
                  leading: const Icon(Symbols.search_rounded),
                  trailing: [
                    if (_filterController.text.isNotEmpty)
                      IconButton(
                        tooltip: copy.clear,
                        onPressed: () {
                          _filterController.clear();
                          _applyFilter();
                          setState(() {});
                        },
                        icon: const Icon(Symbols.close_rounded),
                      ),
                  ],
                  onChanged: (_) {
                    setState(() {});
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 350),
                      _applyFilter,
                    );
                  },
                  onSubmitted: (_) => _applyFilter(),
                );
                final typePicker = PopupMenuButton<String>(
                  key: const ValueKey('groups-type-filter'),
                  tooltip: copy.typeHint,
                  initialValue: _type,
                  onSelected: _changeType,
                  itemBuilder: (_) => [
                    for (final type in const ['', 'my', 'owner', 'public', 'close'])
                      PopupMenuItem<String>(
                        key: ValueKey('groups-filter-' + (type.isEmpty ? 'all' : type)),
                        value: type,
                        child: Row(
                          children: [
                            if (_type == type) ...[
                              Icon(Icons.check_rounded, size: 18, color: scheme.primary),
                              const SizedBox(width: 8),
                            ],
                            Text(copy.typeLabel(type)),
                          ],
                        ),
                      ),
                  ],
                  child: Container(
                    height: 54,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _type.isEmpty ? copy.typeHint : copy.typeLabel(_type),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.keyboard_arrow_down_rounded),
                      ],
                    ),
                  ),
                );
                if (constraints.maxWidth < 570) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      search,
                      const SizedBox(height: 8),
                      typePicker,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: typePicker,
                    ),
                  ],
                );
              },
            ),
          ),
          if (_total > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  copy.total(_total),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(child: _buildBody(context, copy)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, _GroupsCopy copy) {
    if (_groups.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_groups.isEmpty && _error != null) {
      return _ErrorState(
        message: copy.loadFailed,
        detail: _error.toString(),
        retryLabel: copy.retry,
        retry: () => _load(reset: true),
      );
    }
    if (_groups.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 130),
            const Icon(Symbols.groups_rounded, size: 48),
            const SizedBox(height: 12),
            Center(child: Text(copy.empty)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 430,
                  mainAxisExtent: 248,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildGroupCard(
                    context,
                    _groups[index],
                    copy,
                  ),
                  childCount: _groups.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                child: Center(
                  child: _loading
                      ? const CircularProgressIndicator.adaptive()
                      : _hasMore
                      ? FilledButton.tonal(
                          onPressed: () => _load(reset: false),
                          child: Text(copy.loadMore),
                        )
                      : const SizedBox(height: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(
    BuildContext context,
    DiscourseGroup group,
    _GroupsCopy copy,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasFlair = group.flairUrl?.trim().isNotEmpty == true;
    final preview = group.bioPreview;

    return Card(
      key: ValueKey('group-card-' + group.name),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openGroup(group),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasFlair) ...[
                    FlairBadge(
                      flairUrl: group.flairUrl,
                      flairName: group.label,
                      flairBgColor: group.flairBackgroundColor,
                      flairColor: group.flairColor,
                      size: 46,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.label,
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@' + group.name,
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (group.userCount != null) ...[
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Symbols.person_rounded,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            group.userCount.toString(),
                            style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    preview,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildMembershipControl(group, copy),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMembershipControl(DiscourseGroup group, _GroupsCopy copy) {
    final busy = _membershipChanging.contains(group.id);
    final disabled = busy || _membershipConfirmationPending.contains(group.id);
    final scheme = Theme.of(context).colorScheme;
    final waiting = const SizedBox.square(
      dimension: 16,
      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
    );

    if (group.canJoin) {
      return OutlinedButton.icon(
        onPressed: disabled ? null : () => _changeMembership(group, join: true),
        icon: busy ? waiting : const Icon(Icons.person_add_alt_1_rounded, size: 18),
        label: Text(copy.join),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      );
    }
    if (group.canLeave) {
      return OutlinedButton.icon(
        onPressed: disabled ? null : () => _changeMembership(group, join: false),
        icon: busy ? waiting : const Icon(Icons.person_remove_rounded, size: 18),
        label: Text(copy.leave),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          foregroundColor: scheme.error,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      );
    }
    if (group.isGroupUser) {
      return Tooltip(
        message: group.isGroupOwner ? copy.owner : copy.member,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_rounded, color: Colors.green, size: 20),
            const SizedBox(width: 6),
            Text(copy.member, style: TextStyle(color: scheme.primary)),
          ],
        ),
      );
    }
    if (group.allowMembershipRequests) {
      return OutlinedButton.icon(
        onPressed: () => _openGroup(group),
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
        label: Text(copy.requestMembership),
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.block_rounded, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          copy.closed,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.detail,
    required this.retryLabel,
    required this.retry,
  });

  final String message;
  final String detail;
  final String retryLabel;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Symbols.error_rounded, size: 42),
            const SizedBox(height: 12),
            Text(message, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: retry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}

class _GroupsCopy {
  const _GroupsCopy({required this.zh});
  final bool zh;

  String get title => zh ? '群组' : 'Groups';
  String get refresh => zh ? '刷新' : 'Refresh';
  String get retry => zh ? '重试' : 'Retry';
  String get searchHint => zh ? '所有群组' : 'All groups';
  String get typeHint => zh ? '根据群组类型筛选' : 'Filter by group type';
  String typeLabel(String type) => switch (type) {
    'my' => zh ? '我的群组' : 'My groups',
    'owner' => zh ? '我拥有的群组' : 'Groups I own',
    'public' => zh ? '公开群组' : 'Public groups',
    'close' => zh ? '已关闭的群组' : 'Closed groups',
    _ => zh ? '所有群组' : 'All groups',
  };
  String get clear => zh ? '清除' : 'Clear';
  String get empty => zh ? '没有可见群组' : 'No visible groups';
  String get loadMore => zh ? '加载更多' : 'Load more';
  String get loadFailed => zh ? '群组加载失败' : 'Failed to load groups';
  String get join => zh ? '加入' : 'Join';
  String get member => zh ? '成员' : 'Member';
  String get closed => zh ? '已关闭' : 'Closed';
  String get requestMembership => zh ? '申请加入' : 'Request to join';
  String get owner => zh ? '群主' : 'Owner';
  String memberCount(int count) => zh ? '$count 位成员' : '$count members';
  String get leave => zh ? '离开' : 'Leave';
  String get joined => zh ? '已加入群组' : 'Joined group';
  String get left => zh ? '已退出群组' : 'Left group';
  String total(int value) => zh ? '共 $value 个群组' : '$value groups';
}

_GroupsCopy _copy(BuildContext context) => _GroupsCopy(
  zh: Localizations.localeOf(context).languageCode.toLowerCase() == 'zh',
);
