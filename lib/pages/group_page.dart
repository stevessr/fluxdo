import 'dart:collection';

import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group.dart';
import '../providers/discourse_providers.dart';
import '../widgets/common/smart_avatar.dart';
import 'user_profile_page.dart';

/// Discourse 原生群组详情 / 成员页。
class GroupPage extends ConsumerStatefulWidget {
  const GroupPage({super.key, required this.groupName});

  final String groupName;

  @override
  ConsumerState<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends ConsumerState<GroupPage> {
  final TextEditingController _memberFilterController = TextEditingController();

  DiscourseGroup? _group;
  List<GroupMember> _members = const [];
  String _memberFilter = '';
  int _nextOffset = 0;
  bool _hasMore = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _adding = false;
  bool _membershipChanging = false;
  bool _membershipRequesting = false;
  bool _membershipRequested = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  @override
  void dispose() {
    _memberFilterController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (_loading || !mounted) return;
    final requestedFilter = _memberFilter;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = ref.read(discourseServiceProvider);
      final group = await service.fetchGroup(widget.groupName);
      GroupMembersResult? members;
      if (group.canSeeMembers) {
        members = await service.fetchGroupMembers(
          group.name,
          filter: requestedFilter.isEmpty ? null : requestedFilter,
        );
      }
      if (!mounted || requestedFilter != _memberFilter) return;
      setState(() {
        _group = group;
        _members = members?.members ?? const [];
        _nextOffset = members?.nextOffset ?? 0;
        _hasMore = members?.hasMore ?? false;
        if (group.isGroupUser) _membershipRequested = false;
      });
    } catch (error) {
      if (mounted && requestedFilter == _memberFilter) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final group = _group;
    if (group == null || _loadingMore || !_hasMore || !group.canSeeMembers) {
      return;
    }
    final requestedFilter = _memberFilter;
    setState(() => _loadingMore = true);
    try {
      final result = await ref.read(discourseServiceProvider).fetchGroupMembers(
        group.name,
        offset: _nextOffset,
        filter: requestedFilter.isEmpty ? null : requestedFilter,
      );
      if (!mounted || requestedFilter != _memberFilter) return;
      final byId = LinkedHashMap<int, GroupMember>();
      for (final member in [..._members, ...result.members]) {
        byId[member.id] = member;
      }
      setState(() {
        _members = byId.values.toList(growable: false);
        _nextOffset = result.nextOffset;
        _hasMore = result.hasMore;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _applyMemberFilter() {
    final next = _memberFilterController.text.trim();
    if (next == _memberFilter) {
      _reload();
      return;
    }
    setState(() {
      _memberFilter = next;
      _members = const [];
      _hasMore = false;
      _nextOffset = 0;
    });
    _reload();
  }

  Future<bool> _confirmMembershipChange({
    required bool join,
    required DiscourseGroup group,
  }) async {
    final copy = _copy(context);
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(join ? copy.confirmJoinTitle : copy.confirmLeaveTitle),
            content: Text(
              join
                  ? copy.confirmJoin(group.label)
                  : copy.confirmLeave(group.label),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(copy.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(join ? copy.join : copy.leave),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _changeMembership({required bool join}) async {
    final group = _group;
    if (group == null || _membershipChanging) return;
    if (join ? !group.canJoin : !group.canLeave) return;

    final confirmed = await _confirmMembershipChange(join: join, group: group);
    if (!confirmed || !mounted) return;

    // 确认框打开期间群组状态可能已刷新，因此执行前再使用最新状态校验一次。
    final latest = _group;
    if (latest == null || _membershipChanging) return;
    if (join ? !latest.canJoin : !latest.canLeave) return;

    setState(() => _membershipChanging = true);
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
      setState(() {
        _group = latest.copyWith(
          userCount: nextCount,
          isGroupUser: join,
          isGroupOwner: false,
        );
        _membershipRequested = false;
      });

      final copy = _copy(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(join ? copy.joined : copy.left)),
      );
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _membershipChanging = false);
    }
  }

  Future<void> _requestMembership() async {
    final group = _group;
    if (group == null ||
        group.isGroupUser ||
        group.canJoin ||
        !group.allowMembershipRequests ||
        _membershipRequesting ||
        _membershipRequested) {
      return;
    }

    final copy = _copy(context);
    final controller = TextEditingController();
    String? reason;
    try {
      reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(copy.requestMembershipTitle),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: copy.requestReason,
                hintText: copy.requestReasonHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(copy.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(copy.sendRequest),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (reason == null || !mounted) return;

    // Dialog 打开期间权限可能变化，提交前再次使用最新 serializer 状态。
    final latest = _group;
    if (latest == null ||
        latest.isGroupUser ||
        latest.canJoin ||
        !latest.allowMembershipRequests ||
        _membershipRequesting ||
        _membershipRequested) {
      return;
    }

    setState(() => _membershipRequesting = true);
    try {
      await ref.read(discourseServiceProvider).requestGroupMembership(
            latest.name,
            reason: reason,
          );
      if (!mounted) return;
      setState(() => _membershipRequested = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(copy.requestSent)),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _membershipRequesting = false);
    }
  }

  Future<void> _showAddMembers() async {
    final group = _group;
    if (group == null || !group.canManageMembers || _adding) return;
    final request = await showDialog<_AddMembersRequest>(
      context: context,
      builder: (_) => _AddMembersDialog(groupLabel: group.label),
    );
    if (request == null || request.usernames.isEmpty || !mounted) return;

    // 对话框打开后权限可能已经被服务端撤销；UI 再校验一次，服务端 PUT
    // 仍是最终权限边界。
    final latest = _group;
    if (latest == null || !latest.canManageMembers) return;

    setState(() => _adding = true);
    try {
      final added = await ref.read(discourseServiceProvider).addGroupMembers(
        groupId: latest.id,
        usernames: request.usernames,
        notifyUsers: request.notifyUsers,
      );
      if (!mounted) return;
      final copy = _copy(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(copy.added(added.length))),
      );
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _openUser(GroupMember member) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfilePage(username: member.username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy(context);
    final group = _group;

    return Scaffold(
      appBar: AppBar(
        title: Text(group?.label ?? widget.groupName),
        actions: [
          if (group?.canManageMembers == true)
            IconButton(
              tooltip: copy.addMembers,
              onPressed: _adding ? null : _showAddMembers,
              icon: _adding
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    )
                  : const Icon(Symbols.person_add_rounded),
            ),
          IconButton(
            tooltip: copy.refresh,
            onPressed: _loading || _membershipChanging ? null : _reload,
            icon: const Icon(Symbols.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(context, copy),
    );
  }

  Widget _buildBody(BuildContext context, _GroupCopy copy) {
    final group = _group;
    if (group == null && _loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (group == null && _error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Symbols.error_rounded, size: 42),
              const SizedBox(height: 12),
              Text(copy.loadFailed),
              const SizedBox(height: 8),
              Text(
                _error.toString(),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: _reload, child: Text(copy.retry)),
            ],
          ),
        ),
      );
    }
    if (group == null) return const SizedBox.shrink();

    return RefreshIndicator(
      onRefresh: _reload,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _GroupHeader(
              group: group,
              membershipChanging: _membershipChanging,
              membershipRequesting: _membershipRequesting,
              membershipRequested: _membershipRequested,
              onJoin: () => _changeMembership(join: true),
              onLeave: () => _changeMembership(join: false),
              onRequestMembership: _requestMembership,
            ),
          ),
          if (group.canSeeMembers) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: SearchBar(
                  controller: _memberFilterController,
                  hintText: copy.searchMembers,
                  leading: const Icon(Symbols.search_rounded),
                  trailing: [
                    if (_memberFilterController.text.isNotEmpty ||
                        _memberFilter.isNotEmpty)
                      IconButton(
                        tooltip: copy.clear,
                        onPressed: () {
                          _memberFilterController.clear();
                          if (_memberFilter.isNotEmpty) _applyMemberFilter();
                          setState(() {});
                        },
                        icon: const Icon(Symbols.close_rounded),
                      ),
                  ],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _applyMemberFilter(),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: Divider(height: 1)),
            ..._buildMemberSlivers(context, copy),
          ] else
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Symbols.lock_rounded, size: 44),
                      const SizedBox(height: 12),
                      Text(copy.membersHidden),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildMemberSlivers(BuildContext context, _GroupCopy copy) {
    if (_members.isEmpty && _loading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator.adaptive()),
        ),
      ];
    }
    if (_members.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Symbols.person_rounded, size: 42),
                const SizedBox(height: 12),
                Text(copy.noMembers),
              ],
            ),
          ),
        ),
      ];
    }

    final memberContentCount = _members.length * 2 - 1;
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (index == memberContentCount) {
                if (_loadingMore) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                  );
                }
                if (_hasMore) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Center(
                      child: FilledButton.tonal(
                        onPressed: _loadMore,
                        child: Text(copy.loadMore),
                      ),
                    ),
                  );
                }
                return const SizedBox(height: 12);
              }

              if (index.isOdd) {
                return const Divider(height: 1, indent: 64);
              }

              final member = _members[index ~/ 2];
              return ListTile(
                leading: SmartAvatar(
                  imageUrl: member.avatarUrl,
                  radius: 20,
                  fallbackText: member.username,
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.name?.trim().isNotEmpty == true
                            ? member.name!.trim()
                            : member.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (member.owner) ...[
                      const SizedBox(width: 8),
                      _SmallBadge(label: copy.owner),
                    ],
                  ],
                ),
                subtitle: Text('@${member.username}'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => _openUser(member),
              );
            },
            childCount: memberContentCount + 1,
          ),
        ),
      ),
    ];
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.membershipChanging,
    required this.membershipRequesting,
    required this.membershipRequested,
    required this.onJoin,
    required this.onLeave,
    required this.onRequestMembership,
  });

  final DiscourseGroup group;
  final bool membershipChanging;
  final bool membershipRequesting;
  final bool membershipRequested;
  final VoidCallback onJoin;
  final VoidCallback onLeave;
  final VoidCallback onRequestMembership;

  @override
  Widget build(BuildContext context) {
    final copy = _copy(context);
    final scheme = Theme.of(context).colorScheme;
    final canRequestMembership =
        group.allowMembershipRequests && !group.isGroupUser && !group.canJoin;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: scheme.secondaryContainer,
                child: Icon(
                  Symbols.groups_rounded,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${group.name}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (group.bioRaw?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 10),
                      Text(group.bioRaw!.trim()),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (group.userCount != null)
                          _SmallBadge(
                            label: copy.memberCount(group.userCount!),
                          ),
                        if (group.automatic)
                          _SmallBadge(label: copy.automatic),
                        if (group.isGroupOwner)
                          _SmallBadge(label: copy.youAreOwner),
                      ],
                    ),
                    if (group.canJoin || group.canLeave) ...[
                      const SizedBox(height: 12),
                      if (group.canJoin)
                        FilledButton.tonal(
                          onPressed: membershipChanging ? null : onJoin,
                          child: membershipChanging
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator.adaptive(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(copy.join),
                        )
                      else
                        OutlinedButton(
                          onPressed: membershipChanging ? null : onLeave,
                          child: membershipChanging
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator.adaptive(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(copy.leave),
                        ),
                    ] else if (canRequestMembership) ...[
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: membershipRequesting || membershipRequested
                            ? null
                            : onRequestMembership,
                        icon: membershipRequesting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator.adaptive(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                membershipRequested
                                    ? Symbols.check_rounded
                                    : Symbols.person_add_rounded,
                              ),
                        label: Text(
                          membershipRequested
                              ? copy.requestSent
                              : copy.requestMembership,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _AddMembersRequest {
  const _AddMembersRequest({required this.usernames, required this.notifyUsers});
  final List<String> usernames;
  final bool notifyUsers;
}

class _AddMembersDialog extends StatefulWidget {
  const _AddMembersDialog({required this.groupLabel});
  final String groupLabel;

  @override
  State<_AddMembersDialog> createState() => _AddMembersDialogState();
}

class _AddMembersDialogState extends State<_AddMembersDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _notifyUsers = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> get _usernames => LinkedHashSet<String>.from(
        _controller.text
            .split(RegExp(r'[\s,;，；]+'))
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      ).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final copy = _copy(context);
    return AlertDialog(
      title: Text(copy.addMembersTo(widget.groupLabel)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: copy.usernames,
                hintText: copy.usernamesHint,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _notifyUsers,
              contentPadding: EdgeInsets.zero,
              title: Text(copy.notifyUsers),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (value) => setState(() => _notifyUsers = value ?? true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(copy.cancel),
        ),
        FilledButton.icon(
          onPressed: _usernames.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    _AddMembersRequest(
                      usernames: _usernames,
                      notifyUsers: _notifyUsers,
                    ),
                  ),
          icon: const Icon(Symbols.person_add_rounded),
          label: Text(copy.add),
        ),
      ],
    );
  }
}

class _GroupCopy {
  const _GroupCopy({required this.zh});
  final bool zh;

  String get refresh => zh ? '刷新' : 'Refresh';
  String get retry => zh ? '重试' : 'Retry';
  String get clear => zh ? '清除' : 'Clear';
  String get loadFailed => zh ? '群组加载失败' : 'Failed to load group';
  String get addMembers => zh ? '添加成员' : 'Add members';
  String get searchMembers => zh ? '搜索成员' : 'Search members';
  String get membersHidden => zh ? '该群组的成员列表不可见' : 'Members are hidden';
  String get noMembers => zh ? '没有成员' : 'No members';
  String get loadMore => zh ? '加载更多' : 'Load more';
  String get owner => zh ? '所有者' : 'Owner';
  String get automatic => zh ? '自动群组' : 'Automatic group';
  String get youAreOwner => zh ? '你是所有者' : 'You are an owner';
  String get join => zh ? '进入' : 'Join';
  String get leave => zh ? '退出' : 'Leave';
  String get joined => zh ? '已进入群组' : 'Joined group';
  String get left => zh ? '已退出群组' : 'Left group';
  String get requestMembership => zh ? '申请加入' : 'Request membership';
  String get requestMembershipTitle => zh ? '申请加入群组' : 'Request membership';
  String get requestReason => zh ? '申请理由（可选）' : 'Reason (optional)';
  String get requestReasonHint => zh
      ? '可以说明你希望加入这个群组的原因'
      : 'Tell the group owners why you would like to join';
  String get sendRequest => zh ? '发送申请' : 'Send request';
  String get requestSent => zh ? '加入申请已发送' : 'Membership request sent';
  String get confirmJoinTitle => zh ? '确认进入群组' : 'Join group?';
  String get confirmLeaveTitle => zh ? '确认退出群组' : 'Leave group?';
  String confirmJoin(String group) =>
      zh ? '确定要进入“$group”吗？' : 'Are you sure you want to join “$group”?';
  String confirmLeave(String group) =>
      zh ? '确定要退出“$group”吗？' : 'Are you sure you want to leave “$group”?';
  String memberCount(int value) => zh ? '$value 位成员' : '$value members';
  String addMembersTo(String group) =>
      zh ? '添加成员到 $group' : 'Add members to $group';
  String get usernames => zh ? '用户名' : 'Usernames';
  String get usernamesHint => zh
      ? '可一次填写多个用户名，用逗号、空格或换行分隔'
      : 'Separate usernames with commas, spaces, or new lines';
  String get notifyUsers => zh ? '通知被添加的用户' : 'Notify added users';
  String get cancel => zh ? '取消' : 'Cancel';
  String get add => zh ? '添加' : 'Add';
  String added(int count) => zh ? '已添加 $count 位成员' : 'Added $count members';
}

_GroupCopy _copy(BuildContext context) => _GroupCopy(
      zh: Localizations.localeOf(context).languageCode.toLowerCase() == 'zh',
    );
