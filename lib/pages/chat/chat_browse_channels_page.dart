import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat/chat_models.dart';
import '../../providers/chat_providers.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common/emoji_text.dart';
import '../../widgets/common/error_view.dart';
import 'chat_message_page.dart';

/// 频道浏览页面
///
/// 展示论坛中所有可用的聊天频道，支持按状态（全部/开放/已关闭）筛选，
/// 可搜索频道名称，并支持加入频道。
class ChatBrowseChannelsPage extends ConsumerStatefulWidget {
  const ChatBrowseChannelsPage({super.key});

  @override
  ConsumerState<ChatBrowseChannelsPage> createState() =>
      _ChatBrowseChannelsPageState();
}

class _ChatBrowseChannelsPageState
    extends ConsumerState<ChatBrowseChannelsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// Tab 对应的 status 值：null=全部, 'open'=开放, 'closed'=已关闭
  static const List<String?> _statusFilters = [null, 'open', 'closed'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('浏览频道'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '全部'),
            Tab(text: '开放'),
            Tab(text: '已关闭'),
          ],
        ),
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索频道...',
                prefixIcon: const Icon(Symbols.search_rounded, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Symbols.close_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val.trim());
              },
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _statusFilters.map((status) {
                return _BrowseChannelListView(
                  status: status,
                  searchQuery: _searchQuery,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 频道列表视图
class _BrowseChannelListView extends ConsumerWidget {
  final String? status;
  final String searchQuery;

  const _BrowseChannelListView({
    this.status,
    this.searchQuery = '',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final params = BrowseChannelsParams(
      status: status,
      filter: searchQuery.isNotEmpty ? searchQuery : null,
    );
    final channelsAsync = ref.watch(browseChannelsProvider(params));

    // 获取当前已加入的频道 ID 列表
    final joinedChannelIds = <int>{};
    final currentChannels = ref.watch(chatChannelsProvider).value;
    if (currentChannels != null) {
      for (final c in currentChannels.publicChannels) {
        joinedChannelIds.add(c.id);
      }
      for (final c in currentChannels.directMessageChannels) {
        joinedChannelIds.add(c.id);
      }
    }

    return channelsAsync.when(
      data: (channels) {
        if (channels.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  searchQuery.isNotEmpty
                      ? Symbols.search_off_rounded
                      : Symbols.forum_rounded,
                  size: 64,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  searchQuery.isNotEmpty ? '没有找到匹配的频道' : '暂无频道',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(browseChannelsProvider(params));
          },
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: channels.length,
            itemBuilder: (context, index) {
              final channel = channels[index];
              final isJoined = joinedChannelIds.contains(channel.id);
              return _BrowseChannelTile(
                channel: channel,
                isJoined: isJoined,
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => ErrorView(
        error: error,
        stackTrace: stack,
        onRetry: () {
          ref.invalidate(browseChannelsProvider(params));
        },
      ),
    );
  }
}

/// 频道列表项组件
class _BrowseChannelTile extends ConsumerStatefulWidget {
  final ChatChannel channel;
  final bool isJoined;

  const _BrowseChannelTile({
    required this.channel,
    required this.isJoined,
  });

  @override
  ConsumerState<_BrowseChannelTile> createState() => _BrowseChannelTileState();
}

class _BrowseChannelTileState extends ConsumerState<_BrowseChannelTile> {
  bool _isJoining = false;

  Future<void> _joinChannel() async {
    if (_isJoining) return;
    setState(() => _isJoining = true);
    try {
      final service = ref.read(discourseServiceProvider);
      await service.joinChannel(widget.channel.id);
      // 刷新已加入的频道列表
      ref.invalidate(chatChannelsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已加入频道「${widget.channel.title ?? ''}」')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加入失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  Widget _buildLeading(BuildContext context) {
    // 如果设置了自定义频道表情/图标
    if (widget.channel.emoji != null && widget.channel.emoji!.isNotEmpty) {
      final emojiCode = widget.channel.emoji!.startsWith(':')
          ? widget.channel.emoji!
          : ':${widget.channel.emoji}:';
      return CircleAvatar(
        radius: 22,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: EmojiText(
          emojiCode,
          style: const TextStyle(fontSize: 20),
        ),
      );
    }

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
    final channel = widget.channel;

    return ListTile(
      leading: _buildLeading(context),
      title: Text(
        channel.title ?? '未命名频道',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (channel.description != null && channel.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                channel.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(
                  Icons.people_outline_rounded,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '${channel.membersCount ?? 0} 成员',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (channel.threadingEnabled) ...[
                  const SizedBox(width: 12),
                  Icon(
                    Icons.forum_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '消息串',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      trailing: widget.isJoined
          ? FilledButton.tonal(
              onPressed: () {
                // 已加入 → 进入频道
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatMessagePage(
                      channelId: channel.id,
                      channelTitle: channel.title ?? '未命名频道',
                    ),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('已加入'),
            )
          : _isJoining
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton(
                  onPressed: _joinChannel,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('加入'),
                ),
      onTap: widget.isJoined
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatMessagePage(
                    channelId: channel.id,
                    channelTitle: channel.title ?? '未命名频道',
                  ),
                ),
              );
            }
          : null,
      isThreeLine: channel.description != null && channel.description!.isNotEmpty,
    );
  }
}
