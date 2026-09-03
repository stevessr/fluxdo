import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group.dart';
import '../providers/discourse_providers.dart';
import '../widgets/common/error_view.dart';
import '../widgets/common/relative_time_text.dart';
import '../widgets/common/smart_avatar.dart';
import 'user_profile_page.dart';

/// Group owner/admin view for pending Discourse membership requests.
///
/// Upstream exposes requesters through `/groups/:name/members.json?requesters=true`
/// and mutates each request through `PUT /groups/:id/handle_membership_request.json`.
class GroupRequestsPage extends ConsumerStatefulWidget {
  const GroupRequestsPage({
    super.key,
    required this.groupId,
    required this.groupName,
    this.groupLabel,
  });

  final int groupId;
  final String groupName;
  final String? groupLabel;

  @override
  ConsumerState<GroupRequestsPage> createState() => _GroupRequestsPageState();
}

class _GroupRequestsPageState extends ConsumerState<GroupRequestsPage> {
  final TextEditingController _filterController = TextEditingController();

  List<GroupRequester>? _requesters;
  String _filter = '';
  int _total = 0;
  int _nextOffset = 0;
  bool _hasMore = false;
  bool _loading = false;
  bool _loadingMore = false;
  Object? _error;
  StackTrace? _errorStack;
  final Set<int> _actingUserIds = <int>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (_loading) return;
    final requestedFilter = _filter;
    setState(() {
      _loading = true;
      _error = null;
      _errorStack = null;
    });
    try {
      final result = await ref.read(discourseServiceProvider).fetchGroupRequesters(
            widget.groupName,
            filter: requestedFilter.isEmpty ? null : requestedFilter,
          );
      if (!mounted || requestedFilter != _filter) return;
      setState(() {
        _requesters = result.requesters;
        _total = result.total;
        _nextOffset = result.nextOffset;
        _hasMore = result.hasMore;
      });
    } catch (error, stack) {
      if (mounted && requestedFilter == _filter) {
        setState(() {
          _error = error;
          _errorStack = stack;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final requestedFilter = _filter;
    setState(() => _loadingMore = true);
    try {
      final result = await ref.read(discourseServiceProvider).fetchGroupRequesters(
            widget.groupName,
            offset: _nextOffset,
            filter: requestedFilter.isEmpty ? null : requestedFilter,
          );
      if (!mounted || requestedFilter != _filter) return;
      final byId = LinkedHashMap<int, GroupRequester>();
      for (final requester in [...?_requesters, ...result.requesters]) {
        byId[requester.id] = requester;
      }
      setState(() {
        _requesters = byId.values.toList(growable: false);
        _total = result.total;
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

  void _applyFilter() {
    final next = _filterController.text.trim();
    if (next == _filter) {
      _reload();
      return;
    }
    setState(() {
      _filter = next;
      _requesters = null;
      _hasMore = false;
      _nextOffset = 0;
    });
    _reload();
  }

  Future<bool> _confirmReject(GroupRequester requester) async {
    final copy = _copy(context);
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(copy.rejectTitle),
            content: Text(copy.rejectConfirm(requester.username)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(copy.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(copy.reject),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _handleRequest(
    GroupRequester requester, {
    required bool accept,
  }) async {
    if (_actingUserIds.contains(requester.id)) return;
    if (!accept) {
      final confirmed = await _confirmReject(requester);
      if (!confirmed || !mounted) return;
    }

    setState(() => _actingUserIds.add(requester.id));
    try {
      await ref.read(discourseServiceProvider).handleGroupMembershipRequest(
            groupId: widget.groupId,
            userId: requester.id,
            accept: accept,
          );
      if (!mounted) return;
      setState(() {
        _requesters = (_requesters ?? const <GroupRequester>[])
            .where((item) => item.id != requester.id)
            .toList(growable: false);
        if (_total > 0) _total -= 1;
        _actingUserIds.remove(requester.id);
      });
      final copy = _copy(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accept ? copy.accepted : copy.rejected)),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _actingUserIds.remove(requester.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  void _openUser(GroupRequester requester) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfilePage(username: requester.username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy(context);
    final requesters = _requesters;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _total > 0
              ? '${widget.groupLabel ?? widget.groupName} · ${copy.requests} ($_total)'
              : '${widget.groupLabel ?? widget.groupName} · ${copy.requests}',
        ),
        actions: [
          IconButton(
            tooltip: copy.refresh,
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SearchBar(
              controller: _filterController,
              leading: const Icon(Icons.search_rounded),
              hintText: copy.search,
              trailing: [
                if (_filterController.text.isNotEmpty || _filter.isNotEmpty)
                  IconButton(
                    tooltip: copy.clear,
                    onPressed: () {
                      _filterController.clear();
                      if (_filter.isNotEmpty) _applyFilter();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _applyFilter(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: requesters == null && _loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : requesters == null && _error != null
                ? ErrorView(
                    error: _error!,
                    stackTrace: _errorStack,
                    onRetry: _reload,
                  )
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: _buildList(copy, requesters ?? const []),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(_GroupRequestsCopy copy, List<GroupRequester> requesters) {
    if (requesters.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.55,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.how_to_reg_rounded, size: 52),
                  const SizedBox(height: 12),
                  Text(copy.empty),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: requesters.length + 1,
      itemBuilder: (context, index) {
        if (index == requesters.length) {
          if (_loadingMore) {
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
                  onPressed: _loadMore,
                  child: Text(copy.loadMore),
                ),
              ),
            );
          }
          return const SizedBox(height: 12);
        }

        final requester = requesters[index];
        final acting = _actingUserIds.contains(requester.id);
        final reason = requester.reason?.trim();
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: SmartAvatar(
                    imageUrl: requester.avatarUrl,
                    radius: 22,
                    fallbackText: requester.username,
                  ),
                  title: Text(requester.displayName),
                  subtitle: Row(
                    children: [
                      Flexible(
                        child: Text(
                          '@${requester.username}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (requester.requestedAt != null) ...[
                        const SizedBox(width: 8),
                        const Text('·'),
                        const SizedBox(width: 8),
                        RelativeTimeText(
                          dateTime: requester.requestedAt,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openUser(requester),
                ),
                if (reason != null && reason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                      reason,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: acting
                            ? null
                            : () => _handleRequest(requester, accept: false),
                        icon: const Icon(Icons.close_rounded),
                        label: Text(copy.reject),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: acting
                            ? null
                            : () => _handleRequest(requester, accept: true),
                        icon: acting
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator.adaptive(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(copy.accept),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GroupRequestsCopy {
  const _GroupRequestsCopy(this.zh);
  final bool zh;

  String get requests => zh ? '加入申请' : 'Membership requests';
  String get refresh => zh ? '刷新' : 'Refresh';
  String get search => zh ? '搜索申请人' : 'Search requesters';
  String get clear => zh ? '清除' : 'Clear';
  String get empty => zh ? '暂无待处理的加入申请' : 'No pending membership requests';
  String get loadMore => zh ? '加载更多' : 'Load more';
  String get accept => zh ? '批准' : 'Accept';
  String get reject => zh ? '拒绝' : 'Reject';
  String get accepted => zh ? '已批准加入申请' : 'Membership request accepted';
  String get rejected => zh ? '已拒绝加入申请' : 'Membership request rejected';
  String get rejectTitle => zh ? '拒绝加入申请？' : 'Reject membership request?';
  String rejectConfirm(String username) => zh
      ? '确定拒绝 @$username 的加入申请吗？此操作会移除该申请。'
      : 'Reject @$username? This removes the pending request.';
  String get cancel => zh ? '取消' : 'Cancel';
}

_GroupRequestsCopy _copy(BuildContext context) => _GroupRequestsCopy(
      Localizations.localeOf(context).languageCode.toLowerCase() == 'zh',
    );
