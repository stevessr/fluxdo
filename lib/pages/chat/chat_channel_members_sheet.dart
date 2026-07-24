import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../models/chat/chat_models.dart';
import '../../providers/chat_providers.dart';
import '../../utils/url_helper.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/smart_avatar.dart';
import '../user_profile_page.dart';

/// 聊天频道成员与添加成员弹窗
class ChatChannelMembersSheet extends ConsumerStatefulWidget {
  final int channelId;
  final String channelTitle;

  const ChatChannelMembersSheet({
    super.key,
    required this.channelId,
    required this.channelTitle,
  });

  static void show(BuildContext context, int channelId, String channelTitle) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ChatChannelMembersSheet(
        channelId: channelId,
        channelTitle: channelTitle,
      ),
    );
  }

  @override
  ConsumerState<ChatChannelMembersSheet> createState() =>
      _ChatChannelMembersSheetState();
}

class _ChatChannelMembersSheetState
    extends ConsumerState<ChatChannelMembersSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _filterQuery = '';
  bool _isAdding = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String? _resolveAvatarUrl(ChatUser user) {
    if (user.avatarTemplate == null || user.avatarTemplate!.isEmpty) {
      return null;
    }
    return UrlHelper.resolveUrlWithCdn(
      user.avatarTemplate!.replaceAll('{size}', '48'),
    );
  }

  /// 展开添加成员对话框
  void _showAddMemberDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _AddChannelMemberDialog(
        channelId: widget.channelId,
        onMemberAdded: () {
          ref.invalidate(chatChannelMembersProvider(widget.channelId));
        },
      ),
    );
  }

  void _navigateToUserProfile(String username) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfilePage(username: username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(chatChannelMembersProvider(widget.channelId));

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // 顶部抓手与标题
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.chat_channel_members,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              widget.channelTitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 添加成员按钮
                      FilledButton.icon(
                        onPressed: _showAddMemberDialog,
                        icon: const Icon(Icons.person_add_rounded, size: 18),
                        label: Text(context.l10n.chat_add_member),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 搜索过滤框
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                controller: _searchController,
                onChanged: (val) {
                  setState(() => _filterQuery = val.trim().toLowerCase());
                },
                decoration: InputDecoration(
                  hintText: context.l10n.chat_search_members,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ),

            const Divider(height: 1),

            // 成员列表视图
            Expanded(
              child: membersAsync.when(
                data: (members) {
                  final filteredMembers = members.where((m) {
                    if (_filterQuery.isEmpty) return true;
                    final usernameMatch =
                        m.username.toLowerCase().contains(_filterQuery);
                    final nameMatch =
                        m.name?.toLowerCase().contains(_filterQuery) ?? false;
                    return usernameMatch || nameMatch;
                  }).toList();

                  if (filteredMembers.isEmpty) {
                    return Center(
                      child: Text(
                        context.l10n.chat_no_members,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    itemCount: filteredMembers.length,
                    itemBuilder: (context, index) {
                      final user = filteredMembers[index];
                      final avatarUrl = _resolveAvatarUrl(user);

                      return ListTile(
                        leading: SmartAvatar(
                          imageUrl: avatarUrl,
                          radius: 20,
                          fallbackText: user.username,
                        ),
                        title: Text(
                          user.name ?? user.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: user.name != null
                            ? Text(
                                '@${user.username}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            : null,
                        trailing: TextButton(
                          onPressed: () => _navigateToUserProfile(user.username),
                          child: Text(context.l10n.chat_view_profile),
                        ),
                        onTap: () => _navigateToUserProfile(user.username),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => ErrorView(
                  error: err,
                  stackTrace: stack,
                  onRetry: () => ref.invalidate(
                    chatChannelMembersProvider(widget.channelId),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 弹窗：搜索并添加新成员到频道
class _AddChannelMemberDialog extends ConsumerStatefulWidget {
  final int channelId;
  final VoidCallback onMemberAdded;

  const _AddChannelMemberDialog({
    required this.channelId,
    required this.onMemberAdded,
  });

  @override
  ConsumerState<_AddChannelMemberDialog> createState() =>
      __AddChannelMemberDialogState();
}

class __AddChannelMemberDialogState
    extends ConsumerState<_AddChannelMemberDialog> {
  final TextEditingController _controller = TextEditingController();
  List<Chatable> _searchResults = [];
  bool _isSearching = false;
  bool _isAdding = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    try {
      final results = await ref.read(chatSearchProvider(query.trim()).future);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _addMember(String username) async {
    if (_isAdding) return;
    setState(() => _isAdding = true);

    try {
      await ref.read(
        addChannelMemberProvider((
          channelId: widget.channelId,
          username: username,
        )).future,
      );
      if (!mounted) return;

      widget.onMemberAdded();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.chat_add_member_success)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAdding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.chat_add_member_failed(e.toString())),
        ),
      );
    }
  }

  String? _resolveUserAvatarUrl(Chatable user) {
    if (user.avatarTemplate == null || user.avatarTemplate!.isEmpty) {
      return null;
    }
    return UrlHelper.resolveUrlWithCdn(
      user.avatarTemplate!.replaceAll('{size}', '48'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.chat_add_member,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: context.l10n.chat_search_users,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: _searchUsers,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : _searchResults.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _controller.text.isEmpty
                                ? context.l10n.chat_search_hint
                                : context.l10n.chat_no_results,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final user = _searchResults[index];
                            final avatarUrl = _resolveUserAvatarUrl(user);

                            return ListTile(
                              leading: SmartAvatar(
                                imageUrl: avatarUrl,
                                radius: 18,
                                fallbackText: user.username,
                              ),
                              title: Text(user.name ?? user.username),
                              subtitle: user.name != null
                                  ? Text('@${user.username}')
                                  : null,
                              trailing: IconButton(
                                icon: const Icon(Icons.add_circle_outline_rounded),
                                color: theme.colorScheme.primary,
                                onPressed: _isAdding
                                    ? null
                                    : () => _addMember(user.username),
                              ),
                              onTap: _isAdding
                                  ? null
                                  : () => _addMember(user.username),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
