import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group.dart';
import '../providers/discourse_providers.dart';
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

  List<DiscourseGroup> _groups = const [];
  final Set<int> _membershipChanging = <int>{};
  String _filter = '';
  int _nextPage = 0;
  int _total = 0;
  bool _hasMore = false;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
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
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || !mounted) return;
    if (!reset && !_hasMore) return;

    final page = reset ? 0 : _nextPage;
    final requestedFilter = _filter;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await ref.read(discourseServiceProvider).fetchGroups(
        page: page,
        filter: requestedFilter.isEmpty ? null : requestedFilter,
      );
      if (!mounted || requestedFilter != _filter) return;

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
      if (!mounted || requestedFilter != _filter) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
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

  void _applyFilter() {
    final next = _filterController.text.trim();
    if (next == _filter) {
      _load(reset: true);
      return;
    }
    setState(() {
      _filter = next;
      _groups = const [];
      _hasMore = false;
      _nextPage = 0;
    });
    _load(reset: true);
  }

  Future<void> _openGroup(DiscourseGroup group) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GroupPage(groupName: group.name)),
    );
    if (mounted) _load(reset: true);
  }

  Future<void> _changeMembership(
    DiscourseGroup group, {
    required bool join,
  }) async {
    if (_membershipChanging.contains(group.id)) return;
    if (join ? !group.canJoin : !group.canLeave) return;

    setState(() => _membershipChanging.add(group.id));
    try {
      final service = ref.read(discourseServiceProvider);
      if (join) {
        await service.joinGroup(group.id);
      } else {
        await service.leaveGroup(group.id);
      }
      if (!mounted) return;

      final currentCount = group.userCount;
      final nextCount = currentCount == null
          ? null
          : join
              ? currentCount + 1
              : (currentCount > 0 ? currentCount - 1 : 0);
      final updated = group.copyWith(
        userCount: nextCount,
        isGroupUser: join,
        isGroupOwner: false,
      );
      setState(() {
        _groups = [
          for (final item in _groups)
            if (item.id == group.id) updated else item,
        ];
      });

      final copy = _copy(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(join ? copy.joined : copy.left)),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SearchBar(
              controller: _filterController,
              hintText: copy.searchHint,
              leading: const Icon(Symbols.search_rounded),
              trailing: [
                if (_filterController.text.isNotEmpty || _filter.isNotEmpty)
                  IconButton(
                    tooltip: copy.clear,
                    onPressed: () {
                      _filterController.clear();
                      if (_filter.isNotEmpty) _applyFilter();
                      setState(() {});
                    },
                    icon: const Icon(Symbols.close_rounded),
                  ),
              ],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _applyFilter(),
            ),
          ),
          if (_total > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  copy.total(_total),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        retry: () => _load(reset: true),
      );
    }
    if (_groups.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 150),
            const Icon(Symbols.groups_rounded, size: 48),
            const SizedBox(height: 12),
            Center(child: Text(copy.empty)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
        itemCount: _groups.length + 1,
        separatorBuilder: (_, index) => index < _groups.length - 1
            ? const Divider(height: 1, indent: 64)
            : const SizedBox.shrink(),
        itemBuilder: (context, index) {
          if (index == _groups.length) {
            if (_loading) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator.adaptive()),
              );
            }
            if (_hasMore) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: FilledButton.tonal(
                    onPressed: () => _load(reset: false),
                    child: Text(copy.loadMore),
                  ),
                ),
              );
            }
            return const SizedBox(height: 16);
          }

          final group = _groups[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              child: Icon(
                Symbols.groups_rounded,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
            title: Text(group.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              group.fullName != null && group.fullName!.trim().isNotEmpty
                  ? '@${group.name}'
                  : (group.bioRaw?.trim().isNotEmpty == true
                        ? group.bioRaw!.trim()
                        : '@${group.name}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _buildGroupTrailing(context, group, copy),
            onTap: () => _openGroup(group),
          );
        },
      ),
    );
  }

  Widget _buildGroupTrailing(
    BuildContext context,
    DiscourseGroup group,
    _GroupsCopy copy,
  ) {
    final busy = _membershipChanging.contains(group.id);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (group.canJoin || group.canLeave) ...[
          SizedBox(
            height: 34,
            child: group.canJoin
                ? FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: busy
                        ? null
                        : () => _changeMembership(group, join: true),
                    child: busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          )
                        : Text(copy.join),
                  )
                : OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: busy
                        ? null
                        : () => _changeMembership(group, join: false),
                    child: busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          )
                        : Text(copy.leave),
                  ),
          ),
          const SizedBox(width: 10),
        ],
        if (group.userCount != null) ...[
          const Icon(Symbols.person_rounded, size: 18),
          const SizedBox(width: 4),
          Text('${group.userCount}'),
          const SizedBox(width: 6),
        ],
        const Icon(Symbols.chevron_right_rounded),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.detail,
    required this.retry,
  });

  final String message;
  final String detail;
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
            FilledButton.tonal(onPressed: retry, child: const Text('Retry')),
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
  String get searchHint => zh ? '搜索群组' : 'Search groups';
  String get clear => zh ? '清除' : 'Clear';
  String get empty => zh ? '没有可见群组' : 'No visible groups';
  String get loadMore => zh ? '加载更多' : 'Load more';
  String get loadFailed => zh ? '群组加载失败' : 'Failed to load groups';
  String get join => zh ? '进入' : 'Join';
  String get leave => zh ? '退出' : 'Leave';
  String get joined => zh ? '已进入群组' : 'Joined group';
  String get left => zh ? '已退出群组' : 'Left group';
  String total(int value) => zh ? '共 $value 个群组' : '$value groups';
}

_GroupsCopy _copy(BuildContext context) => _GroupsCopy(
  zh: Localizations.localeOf(context).languageCode.toLowerCase() == 'zh',
);
