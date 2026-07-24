import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../models/chat/chat_models.dart';
import '../../providers/chat_providers.dart';
import '../../utils/time_utils.dart';
import '../../utils/url_helper.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/smart_avatar.dart';
import '../../widgets/desktop_refresh_indicator.dart';
import 'chat_message_page.dart';

/// Chat 频道列表页面
///
/// 显示公开频道和私信频道，支持 Tab 切换、下拉刷新、新建私信。
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await ref.read(chatChannelsProvider.notifier).refresh();
  }

  void _openNewDmDialog() {
    showDialog(
      context: context,
      builder: (context) => const _NewDmDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(chatChannelsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.chat_title),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: context.l10n.chat_public_channels),
            Tab(text: context.l10n.chat_direct_messages),
          ],
        ),
      ),
      body: channelsAsync.when(
        data: (state) => TabBarView(
          controller: _tabController,
          children: [
            _ChatChannelListView(
              channels: state.publicChannels,
              onRefresh: _onRefresh,
            ),
            _ChatChannelListView(
              channels: state.directMessageChannels,
              onRefresh: _onRefresh,
            ),
          ],
        ),
        loading: () => const _ChatPageSkeleton(),
        error: (error, stack) => ErrorView(
          error: error,
          stackTrace: stack,
          onRetry: _onRefresh,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'newDm',
        onPressed: _openNewDmDialog,
        tooltip: context.l10n.chat_new_dm,
        child: const Icon(AppIcons.add),
      ),
    );
  }
}

/// 单个 Tab 的频道列表视图
class _ChatChannelListView extends ConsumerWidget {
  final List<ChatChannel> channels;
  final Future<void> Function() onRefresh;

  const _ChatChannelListView({
    required this.channels,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (channels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              AppIcons.forum,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.chat_empty,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return DesktopRefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: channels.length,
        itemBuilder: (context, index) {
          final channel = channels[index];
          return ChatChannelTile(
            channel: channel,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatMessagePage(
                    channelId: channel.id,
                    channelTitle: _resolveTitle(context),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// 频道列表项组件
class ChatChannelTile extends StatelessWidget {
  final ChatChannel channel;
  final VoidCallback onTap;

  const ChatChannelTile({
    super.key,
    required this.channel,
    required this.onTap,
  });

  /// 获取私信频道中对方的头像 URL
  String? _resolveAvatarUrl(ChatUser? user) {
    if (user == null) return null;
    if (user.avatarTemplate == null || user.avatarTemplate!.isEmpty) {
      return null;
    }
    return UrlHelper.resolveUrlWithCdn(
      user.avatarTemplate!.replaceAll('{size}', '48'),
    );
  }

  /// 获取频道显示标题
  String _resolveTitle(BuildContext context) {
    final isDm = channel.chatableType == 'DirectMessage';
    if (isDm) {
      // 私信频道：优先显示对方用户名
      final lastMessage = channel.lastMessage;
      final otherUser = lastMessage?.user;
      if (otherUser != null) {
        return otherUser.name ?? otherUser.username;
      }
      // 没有消息时用频道标题
      if (channel.title != null && channel.title!.isNotEmpty) {
        return channel.title!;
      }
      return context.l10n.chat_dm_placeholder;
    }
    // 公开频道：显示频道标题
    return channel.title ?? context.l10n.chat_unnamed_channel;
  }

  /// 获取最后一条消息预览文本
  String _resolveLastMessagePreview() {
    final lastMessage = channel.lastMessage;
    if (lastMessage == null) return '';

    // 使用原始消息文本（不含 HTML），截取前 80 字
    final text = lastMessage.message;
    if (text.length > 80) {
      return '${text.substring(0, 80)}…';
    }
    return text;
  }

  /// 获取频道头像
  Widget _buildLeading(BuildContext context) {
    final isDm = channel.chatableType == 'DirectMessage';

    if (isDm) {
      // 私信频道：显示对方头像
      final otherUser = channel.lastMessage?.user;
      if (otherUser != null) {
        final avatarUrl = _resolveAvatarUrl(otherUser);
        return SmartAvatar(
          imageUrl: avatarUrl,
          radius: 22,
          fallbackText: otherUser.username,
        );
      }
      // 没有对方信息时显示默认头像
      return const CircleAvatar(
        radius: 22,
        child: Icon(AppIcons.person, size: 24),
      );
    }

    // 公开频道：显示频道图标
    return CircleAvatar(
      radius: 22,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Icon(
        AppIcons.forum,
        size: 24,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDm = channel.chatableType == 'DirectMessage';
    final lastMessage = channel.lastMessage;
    final hasUnread = channel.unreadCount > 0;

    return ListTile(
      leading: _buildLeading(context),
      title: Text(
        _resolveTitle(context),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: lastMessage != null
          ? Text(
              _resolveLastMessagePreview(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 最后消息时间
          if (channel.lastMessageSentAt != null)
            Text(
              TimeUtils.formatRelativeTime(channel.lastMessageSentAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          if (hasUnread) ...[
            const SizedBox(height: 4),
            // 未读计数徽章
            Container(
              constraints: const BoxConstraints(minWidth: 20),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                channel.unreadCount > 99
                    ? '99+'
                    : channel.unreadCount.toString(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}

/// 加载骨架屏
class _ChatPageSkeleton extends StatelessWidget {
  const _ChatPageSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shimmerColor = theme.colorScheme.surfaceContainerHighest;

    return Column(
      children: [
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: 8,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemBuilder: (context, index) {
              return ListTile(
                leading: CircleAvatar(
                  radius: 22,
                  backgroundColor: shimmerColor,
                ),
                title: Container(
                  height: 14,
                  width: 120 + (index % 3) * 60.0,
                  decoration: BoxDecoration(
                    color: shimmerColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    height: 12,
                    width: 180 + (index % 2) * 40.0,
                    decoration: BoxDecoration(
                      color: shimmerColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 新建私信对话框
///
/// 搜索用户并创建私信频道。
class _NewDmDialog extends ConsumerStatefulWidget {
  const _NewDmDialog();

  @override
  ConsumerState<_NewDmDialog> createState() => _NewDmDialogState();
}

class _NewDmDialogState extends ConsumerState<_NewDmDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Chatable> _results = [];
  bool _isSearching = false;
  bool _isCreating = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final results = await ref.read(chatSearchProvider(query.trim()).future);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSearching = false);
    }
  }

  Future<void> _onSelectUser(Chatable user) async {
    if (_isCreating) return;

    setState(() => _isCreating = true);

    try {
      final channelId = await ref.read(
        createDirectMessageProvider([user.username]).future,
      );

      if (!mounted) return;

      Navigator.of(context).pop();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatMessagePage(channelId: channelId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCreating = false);
    }
  }

  /// 解析用户头像 URL
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
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.chat_new_dm,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(AppIcons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // 搜索输入框
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: context.l10n.chat_search_users,
                  prefixIcon: const Icon(AppIcons.search, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: _onSearch,
              ),
            ),
            const SizedBox(height: 8),
            // 搜索结果列表
            Flexible(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            _searchController.text.isEmpty
                                ? context.l10n.chat_search_hint
                                : context.l10n.chat_no_results,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _results.length,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemBuilder: (context, index) {
                            final user = _results[index];
                            final avatarUrl = _resolveUserAvatarUrl(user);

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
                              trailing: _isCreating
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : null,
                              onTap: _isCreating ? null : () => _onSelectUser(user),
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