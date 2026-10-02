import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../models/chat/chat_models.dart';
import '../../providers/chat_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/theme_provider.dart';
import '../../utils/time_utils.dart';
import '../../utils/url_helper.dart';
import '../../widgets/chat/chat_conversation_tabs.dart';
import '../../widgets/common/emoji_text.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/smart_avatar.dart';
import '../../widgets/desktop_refresh_indicator.dart';
import 'chat_message_page.dart';
import 'chat_browse_channels_page.dart';
import 'chat_channel_settings_sheet.dart';
import 'chat_create_channel_sheet.dart';
import 'chat_search_page.dart';
import 'chat_thread_sheet.dart';

typedef ChatConversationGroups = ({
  List<ChatChannel> privateChats,
  List<ChatChannel> groupChats,
});

enum _ChatChannelFilter { all, active, unread, mentions }

enum _ChatChannelSort { alphabetical, recentActivity, priority }

enum _NewChatCreatorMode { message, group }

/// 按对话参与者拆分聊天频道。
///
/// 「私聊」仅指 1:1 Direct Message；群组 Direct Message 与公开频道都属于
/// 多人会话，放入「群聊」。这样收藏页加入子 Tab 后不会丢失已收藏的
/// 公开频道。
ChatConversationGroups partitionChatChannels(List<ChatChannel> channels) {
  final privateChats = <ChatChannel>[];
  final groupChats = <ChatChannel>[];
  for (final channel in channels) {
    if (channel.isDirectMessage && !channel.isGroupDm) {
      privateChats.add(channel);
    } else {
      groupChats.add(channel);
    }
  }
  return (privateChats: privateChats, groupChats: groupChats);
}

/// Chat 频道列表页面
///
/// 支持收藏/常用频道、公开频道与直接消息 Tab 切换，包含实时频道与消息检索。
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _ChatChannelFilter _channelFilter = _ChatChannelFilter.all;
  _ChatChannelSort _channelSort = _ChatChannelSort.priority;

  static const _channelFilterPreferenceKey = 'chat_channel_list_filter';
  static const _channelSortPreferenceKey = 'chat_channel_list_sort';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    final prefs = ref.read(sharedPreferencesProvider);
    final storedFilter = prefs.getString(_channelFilterPreferenceKey);
    final storedSort = prefs.getString(_channelSortPreferenceKey);
    _channelFilter = _ChatChannelFilter.values.firstWhere(
      (value) => value.name == storedFilter,
      orElse: () => _ChatChannelFilter.all,
    );
    _channelSort = _ChatChannelSort.values.firstWhere(
      (value) => value.name == storedSort,
      orElse: () => _ChatChannelSort.priority,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await ref.read(chatChannelsProvider.notifier).refresh();
  }

  void _openNewDmDialog() {
    showDialog(
      context: context,
      builder: (context) =>
          const _NewDmDialog(initialMode: _NewChatCreatorMode.message),
    );
  }

  void _openNewGroupDialog() {
    showDialog(
      context: context,
      builder: (context) =>
          const _NewDmDialog(initialMode: _NewChatCreatorMode.group),
    );
  }

  void _openGlobalSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChatSearchPage()),
    );
  }

  void _openCreateChannel() {
    ChatCreateChannelSheet.show(context);
  }

  List<ChatChannel> _filterChannels(List<ChatChannel> list, String query) {
    if (query.isEmpty) return List<ChatChannel>.from(list);
    final q = query.toLowerCase();
    return list.where((c) {
      final titleMatch = c.title?.toLowerCase().contains(q) ?? false;
      final slugMatch = c.slug?.toLowerCase().contains(q) ?? false;
      final descMatch = c.description?.toLowerCase().contains(q) ?? false;
      final msgMatch =
          c.lastMessage?.message.toLowerCase().contains(q) ?? false;
      final userMatch =
          (c.lastMessage?.user?.username.toLowerCase().contains(q) ?? false) ||
          (c.lastMessage?.user?.name?.toLowerCase().contains(q) ?? false) ||
          (c.dmUsers?.any(
                (u) =>
                    u.username.toLowerCase().contains(q) ||
                    (u.name?.toLowerCase().contains(q) ?? false),
              ) ??
              false);
      return titleMatch || slugMatch || descMatch || msgMatch || userMatch;
    }).toList();
  }

  List<ChatChannel> _prepareChannels(
    List<ChatChannel> list,
    String query,
  ) {
    var channels = _filterChannels(list, query);

    final activeSince = DateTime.now().subtract(const Duration(days: 30));
    channels = switch (_channelFilter) {
      _ChatChannelFilter.all => channels,
      _ChatChannelFilter.active => channels
          .where(
            (channel) =>
                channel.lastMessage != null &&
                (channel.lastMessageSentAt?.isAfter(activeSince) ?? false),
          )
          .toList(),
      _ChatChannelFilter.unread => channels
          .where((channel) => !channel.muted && _channelHasUnread(channel))
          .toList(),
      _ChatChannelFilter.mentions => channels
          .where(
            (channel) => !channel.muted && channel.unreadMentions > 0,
          )
          .toList(),
    };

    channels.sort((a, b) {
      switch (_channelSort) {
        case _ChatChannelSort.alphabetical:
          return _compareAlphabetically(a, b);
        case _ChatChannelSort.recentActivity:
          return _compareRecentActivity(a, b) ?? _compareAlphabetically(a, b);
        case _ChatChannelSort.priority:
          final priority = _channelPriority(a).compareTo(_channelPriority(b));
          if (priority != 0) return priority;
          return _compareRecentActivity(a, b) ?? _compareAlphabetically(a, b);
      }
    });

    return channels;
  }

  bool _channelHasUnread(ChatChannel channel) =>
      channel.unreadCount > 0 || channel.unreadMentions > 0;

  int _channelPriority(ChatChannel channel) {
    if (channel.muted) return 2;
    if (channel.unreadMentions > 0) return 0;
    return _channelHasUnread(channel) ? 1 : 2;
  }

  int? _compareRecentActivity(ChatChannel a, ChatChannel b) {
    final aTime = a.lastMessageSentAt?.millisecondsSinceEpoch;
    final bTime = b.lastMessageSentAt?.millisecondsSinceEpoch;

    if ((aTime != null) != (bTime != null)) {
      return aTime != null ? -1 : 1;
    }
    if (aTime == null || bTime == null) return null;

    final comparison = bTime.compareTo(aTime);
    return comparison == 0 ? null : comparison;
  }

  int _compareAlphabetically(ChatChannel a, ChatChannel b) {
    final comparison = _channelSortName(a).compareTo(_channelSortName(b));
    return comparison != 0 ? comparison : a.id.compareTo(b.id);
  }

  String _channelSortName(ChatChannel channel) {
    if (!channel.isDirectMessage) {
      final slug = channel.slug?.trim();
      if (slug != null && slug.isNotEmpty) return slug.toLowerCase();
      return (channel.title ?? '').trim().toLowerCase();
    }

    final title = channel.title?.trim();
    if (title != null && title.isNotEmpty) return title.toLowerCase();

    final users = channel.dmUsers;
    if (users != null && users.isNotEmpty) {
      return users
          .where((user) => !user.isSystemUser)
          .map((user) => (user.name ?? user.username).toLowerCase())
          .join(',');
    }

    return (channel.slug ?? '').toLowerCase();
  }

  String _currentFilterLabel(BuildContext context) => switch (_channelFilter) {
    _ChatChannelFilter.all => context.l10n.chat_filter_all,
    _ChatChannelFilter.active => context.l10n.chat_filter_active,
    _ChatChannelFilter.unread => context.l10n.chat_filter_unread,
    _ChatChannelFilter.mentions => context.l10n.chat_filter_mentions,
  };

  String _currentSortLabel(BuildContext context) => switch (_channelSort) {
    _ChatChannelSort.alphabetical => context.l10n.chat_sort_alphabetical,
    _ChatChannelSort.recentActivity => context.l10n.chat_sort_recent_activity,
    _ChatChannelSort.priority => context.l10n.chat_sort_priority,
  };

  void _openBrowseChannels() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChatBrowseChannelsPage()),
    );
  }

  Future<void> _showChannelFilterPicker() async {
    final selected = await showModalBottomSheet<_ChatChannelFilter>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        Widget option(
          _ChatChannelFilter value,
          String title, {
          String? subtitle,
        }) {
          final selected = _channelFilter == value;
          return ListTile(
            leading: SizedBox(
              width: 28,
              child: selected
                  ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
                  : null,
            ),
            title: Text(title),
            subtitle: subtitle == null ? null : Text(subtitle),
            onTap: () => Navigator.pop(context, value),
          );
        }

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Text(
                  context.l10n.chat_filter_title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              option(_ChatChannelFilter.all, context.l10n.chat_filter_all),
              option(
                _ChatChannelFilter.active,
                context.l10n.chat_filter_active,
                subtitle: context.l10n.chat_filter_active_description,
              ),
              option(
                _ChatChannelFilter.unread,
                context.l10n.chat_filter_unread,
              ),
              option(
                _ChatChannelFilter.mentions,
                context.l10n.chat_filter_mentions,
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() => _channelFilter = selected);
    await ref
        .read(sharedPreferencesProvider)
        .setString(_channelFilterPreferenceKey, selected.name);
  }

  Future<void> _showChannelSortPicker() async {
    final selected = await showModalBottomSheet<_ChatChannelSort>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        Widget option(
          _ChatChannelSort value,
          String title, {
          String? subtitle,
        }) {
          final selected = _channelSort == value;
          return ListTile(
            leading: SizedBox(
              width: 28,
              child: selected
                  ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
                  : null,
            ),
            title: Text(title),
            subtitle: subtitle == null ? null : Text(subtitle),
            onTap: () => Navigator.pop(context, value),
          );
        }

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Text(
                  context.l10n.chat_sort_title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              option(
                _ChatChannelSort.alphabetical,
                context.l10n.chat_sort_alphabetical,
              ),
              option(
                _ChatChannelSort.recentActivity,
                context.l10n.chat_sort_recent_activity,
              ),
              option(
                _ChatChannelSort.priority,
                context.l10n.chat_sort_priority,
                subtitle: context.l10n.chat_sort_priority_description,
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() => _channelSort = selected);
    await ref
        .read(sharedPreferencesProvider)
        .setString(_channelSortPreferenceKey, selected.name);
  }

  Future<void> _markAllChannelsRead() async {
    try {
      await ref.read(markAllChatChannelsReadProvider.future);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.chat_mark_all_read_success)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(chatChannelsProvider);
    final favoriteIds = ref.watch(chatFavoritesProvider);
    final theme = Theme.of(context);

    final currentUser = ref.watch(currentUserProvider).value;
    final canCreateChannel = currentUser?.isStaff ?? false;
    // 论坛 Chat 总开关：仅读启动预加载的 siteSettings 快照
    final forumChatEnabled = ref.watch(forumChatEnabledProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(
        // 浏览频道入口：左上角
        leading: IconButton(
          icon: const Icon(Symbols.explore_rounded),
          tooltip: context.l10n.chat_browse_channels,
          onPressed: _openBrowseChannels,
        ),
        title: Text(context.l10n.chat_title),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: context.l10n.chat_search_messages,
            onPressed: _openGlobalSearch,
          ),
          PopupMenuButton<String>(
            tooltip: context.l10n.chat_channel_options,
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              switch (value) {
                case 'new_dm':
                  _openNewDmDialog();
                case 'new_group':
                  _openNewGroupDialog();
                case 'create_channel':
                  _openCreateChannel();
                case 'filter':
                  _showChannelFilterPicker();
                case 'sort':
                  _showChannelSortPicker();
                case 'mark_read':
                  _markAllChannelsRead();
              }
            },
            itemBuilder: (context) => [
              if (forumChatEnabled &&
                  (currentUser?.canDirectMessage ?? true)) ...[
                PopupMenuItem<String>(
                  value: 'new_dm',
                  child: Row(
                    children: [
                      Expanded(child: Text(context.l10n.chat_new_dm)),
                      const Icon(Icons.add_rounded),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'new_group',
                  child: Row(
                    children: [
                      Expanded(child: Text(context.l10n.chat_new_group)),
                      const Icon(Icons.add_rounded),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
              ],
              if (canCreateChannel)
                PopupMenuItem<String>(
                  value: 'create_channel',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.add_box_outlined),
                    title: Text(context.l10n.chat_create_public_channel),
                  ),
                ),
              PopupMenuItem<String>(
                enabled: false,
                height: 32,
                child: Text(context.l10n.chat_channel_filter),
              ),
              PopupMenuItem<String>(
                value: 'filter',
                child: Row(
                  children: [
                    Expanded(child: Text(_currentFilterLabel(context))),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                enabled: false,
                height: 32,
                child: Text(context.l10n.chat_channel_sort),
              ),
              PopupMenuItem<String>(
                value: 'sort',
                child: Row(
                  children: [
                    Expanded(child: Text(_currentSortLabel(context))),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'mark_read',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.done_all_rounded),
                  title: Text(context.l10n.chat_mark_all_read),
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          dividerHeight: 0,
          indicatorSize: TabBarIndicatorSize.tab,
          labelPadding: const EdgeInsets.symmetric(horizontal: 8),
          tabs: [
            Tab(text: context.l10n.chat_favorites),
            Tab(text: context.l10n.chat_public_channels),
            Tab(text: context.l10n.chat_direct_messages),
            const Tab(text: '消息串'),
          ],
        ),
      ),
      body: Column(
        children: [
          // 频道搜索。创建私信/群聊入口统一收进右上角频道列表选项。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: context.l10n.chat_search_channels,
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
            child: channelsAsync.when(
              data: (state) {
                // 提取所有频道并过滤收藏的频道
                final allChannels = [
                  ...state.publicChannels,
                  ...state.directMessageChannels,
                ];
                final favoriteChannels = allChannels
                    .where((c) => favoriteIds.contains(c.id))
                    .toList();

                return TabBarView(
                  controller: _tabController,
                  children: [
                    // 收藏 Tab：1:1 私聊 / 多人会话二级分类
                    _ChatConversationSubtabs(
                      id: 'favorites',
                      channels: _prepareChannels(favoriteChannels, _searchQuery),
                      isFavorites: true,
                      searchQuery: _searchQuery,
                      onRefresh: _onRefresh,
                    ),
                    // 公开频道 Tab
                    _ChatChannelListView(
                      channels: _prepareChannels(
                        state.publicChannels,
                        _searchQuery,
                      ),
                      searchQuery: _searchQuery,
                      onRefresh: _onRefresh,
                    ),
                    // 直接消息 Tab：1:1 私聊 / 群组 DM 二级分类
                    _ChatConversationSubtabs(
                      id: 'direct-messages',
                      channels: _prepareChannels(
                        state.directMessageChannels,
                        _searchQuery,
                      ),
                      searchQuery: _searchQuery,
                      onRefresh: _onRefresh,
                    ),
                    // 消息串 Tab：全部频道的消息串
                    const _ChatThreadTabView(),
                  ],
                );
              },
              loading: () => const _ChatPageSkeleton(),
              error: (error, stack) => ErrorView(
                error: error,
                stackTrace: stack,
                onRetry: _onRefresh,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「收藏」和「直接消息」共用的私聊 / 群聊二级分类。
class _ChatConversationSubtabs extends StatelessWidget {
  const _ChatConversationSubtabs({
    required this.id,
    required this.channels,
    this.isFavorites = false,
    required this.searchQuery,
    required this.onRefresh,
  });

  final String id;
  final List<ChatChannel> channels;
  final bool isFavorites;
  final String searchQuery;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final groups = partitionChatChannels(channels);
    return ChatConversationTabs(
      key: PageStorageKey('chat-$id-conversation-tabs'),
      id: id,
      privateCount: groups.privateChats.length,
      groupCount: groups.groupChats.length,
      privateChild: _ChatChannelListView(
        key: PageStorageKey('chat-$id-private-list'),
        channels: groups.privateChats,
        emptyKind: isFavorites
            ? _ChatChannelEmptyKind.favoritePrivateChats
            : _ChatChannelEmptyKind.privateChats,
        searchQuery: searchQuery,
        onRefresh: onRefresh,
      ),
      groupChild: _ChatChannelListView(
        key: PageStorageKey('chat-$id-group-list'),
        channels: groups.groupChats,
        emptyKind: isFavorites
            ? _ChatChannelEmptyKind.favoriteGroupChats
            : _ChatChannelEmptyKind.groupChats,
        searchQuery: searchQuery,
        onRefresh: onRefresh,
      ),
    );
  }
}

enum _ChatChannelEmptyKind {
  channels,
  privateChats,
  groupChats,
  favoritePrivateChats,
  favoriteGroupChats,
}

/// 单个 Tab 的频道列表视图
class _ChatChannelListView extends ConsumerWidget {
  final List<ChatChannel> channels;
  final _ChatChannelEmptyKind emptyKind;
  final String searchQuery;
  final Future<void> Function() onRefresh;

  const _ChatChannelListView({
    super.key,
    required this.channels,
    this.emptyKind = _ChatChannelEmptyKind.channels,
    this.searchQuery = '',
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (channels.isEmpty) {
      if (searchQuery.isNotEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Symbols.search_off_rounded,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.chat_no_results,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      }

      if (emptyKind != _ChatChannelEmptyKind.channels) {
        final isFavorite =
            emptyKind == _ChatChannelEmptyKind.favoritePrivateChats ||
            emptyKind == _ChatChannelEmptyKind.favoriteGroupChats;
        final isPrivate =
            emptyKind == _ChatChannelEmptyKind.privateChats ||
            emptyKind == _ChatChannelEmptyKind.favoritePrivateChats;
        final title = switch (emptyKind) {
          _ChatChannelEmptyKind.privateChats => context.l10n.chat_private_empty,
          _ChatChannelEmptyKind.groupChats => context.l10n.chat_group_empty,
          _ChatChannelEmptyKind.favoritePrivateChats =>
            context.l10n.chat_favorite_private_empty,
          _ChatChannelEmptyKind.favoriteGroupChats =>
            context.l10n.chat_favorite_group_empty,
          _ChatChannelEmptyKind.channels => context.l10n.chat_empty,
        };
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isFavorite
                    ? Symbols.star_outline_rounded
                    : isPrivate
                    ? Icons.person_outline_rounded
                    : Icons.groups_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (isFavorite) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    context.l10n.chat_favorite_hint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(AppIcons.forum, size: 64, color: Colors.grey),
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
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        itemCount: channels.length,
        itemBuilder: (context, index) {
          final channel = channels[index];
          return ChatChannelTile(
            key: ValueKey('chat-channel-${channel.id}'),
            channel: channel,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) {
                    final title = channel.chatableType == 'DirectMessage'
                        ? (channel.title?.isNotEmpty == true
                              ? channel.title!
                              : channel.lastMessage?.user?.name ??
                                    channel.lastMessage?.user?.username ??
                                    context.l10n.chat_dm_placeholder)
                        : (channel.title ?? context.l10n.chat_unnamed_channel);
                    return ChatMessagePage(
                      channelId: channel.id,
                      channelTitle: title,
                    );
                  },
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
class ChatChannelTile extends ConsumerWidget {
  final ChatChannel channel;
  final VoidCallback onTap;

  const ChatChannelTile({
    super.key,
    required this.channel,
    required this.onTap,
  });

  /// 获取直接消息频道中对方的头像 URL
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
  String _resolveTitle(BuildContext context, int? currentUserId) {
    final isDm =
        channel.chatableType == 'DirectMessage' ||
        channel.chatableType == 'DirectMessageChannel';
    if (isDm) {
      // 群聊 DM（3+ 人直接消息）：Discourse 服务端已用成员名拼接出 title，
      // 优先用它，避免取到系统用户 (system) 而把群聊标题显示成 "system"。
      // 判据用 isGroupDm（含 group=true 标记或成员>2），覆盖 3 人直接消息。
      if (channel.isGroupDm &&
          channel.title != null &&
          channel.title!.isNotEmpty) {
        return channel.title!;
      }
      final targetUser = channel.getDmTargetUser(currentUserId);
      if (targetUser != null) {
        return targetUser.name ?? targetUser.username;
      }
      if (channel.title != null && channel.title!.isNotEmpty) {
        return channel.title!;
      }
      return context.l10n.chat_dm_placeholder;
    }
    return channel.title ?? context.l10n.chat_unnamed_channel;
  }

  /// 获取最后一条消息预览文本
  String _resolveLastMessagePreview() {
    final lastMessage = channel.lastMessage;
    if (lastMessage == null) return '';

    final text = lastMessage.message;
    if (text.length > 80) {
      return '${text.substring(0, 80)}…';
    }
    return text;
  }

  /// 获取频道头像/图标
  ///
  /// 对齐 Discourse channel-icon：
  /// - 只要设置了频道 emoji（含群组直接消息），优先显示表情
  /// - 1:1 直接消息无 emoji 时显示对方头像
  /// - 群组直接消息无 emoji 时显示人数/默认图标
  /// - 公开频道无 emoji 时显示论坛图标
  Widget _buildLeading(BuildContext context, int? currentUserId) {
    final theme = Theme.of(context);
    final isDm =
        channel.chatableType == 'DirectMessage' ||
        channel.chatableType == 'DirectMessageChannel';

    // 1. 频道自定义表情优先（公开频道 + 群组 DM 均适用）
    final emojiCode = channel.emojiShortcode;
    if (emojiCode != null && emojiCode.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: EmojiText(emojiCode, style: const TextStyle(fontSize: 20)),
      );
    }

    // 2. 直接消息回退
    if (isDm) {
      // 群组直接消息：无 emoji 时优先显示人数徽标（对齐官方 --users-count）
      if (channel.isGroupDm) {
        final count = channel.membersCount;
        if (count != null && count > 0) {
          return CircleAvatar(
            radius: 22,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              count > 99 ? '99+' : '$count',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
      }

      final targetUser = channel.getDmTargetUser(currentUserId);
      if (targetUser != null) {
        final avatarUrl = _resolveAvatarUrl(targetUser);
        return SmartAvatar(
          imageUrl: avatarUrl,
          radius: 22,
          fallbackText: targetUser.username,
        );
      }
      return CircleAvatar(
        radius: 22,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          AppIcons.person,
          size: 24,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      );
    }

    // 3. 公开频道默认图标
    return CircleAvatar(
      radius: 22,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: Icon(
        AppIcons.forum,
        size: 24,
        color: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }

  String _leaveLabel(BuildContext context) {
    final l10n = context.l10n;
    if (channel.isDirectMessage) {
      // 官方侧栏对所有 DM 文案是 close_channel；群组设置页才强调 leave group
      return channel.isGroupDm ? l10n.chat_leave_group : l10n.chat_leave_dm;
    }
    return l10n.chat_leave_channel;
  }

  Future<void> _leaveFromList(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmMsg = channel.isDirectMessage
        ? (channel.isGroupDm
              ? l10n.chat_leave_confirm_group
              : l10n.chat_leave_confirm_dm)
        : l10n.chat_leave_confirm_channel;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_leaveLabel(context)),
        content: Text(confirmMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.chat_cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.chat_leave),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      // 对齐侧栏菜单：
      // - 直接消息（含群组）：unfollow（列表关闭；群组破坏性仅设置页 leaveDestructive）
      // - 公开频道：leaveChannel API（对 category 等价 unfollow，但走 leave 服务）
      if (channel.isDirectMessage) {
        await ref.read(unfollowChannelProvider(channel.id).future);
      } else {
        await ref.read(leaveChannelProvider(channel.id).future);
      }
      if (!context.mounted) return;
      final title = channel.title ?? l10n.chat_unnamed_channel;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.chat_leave_success(title))));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.chat_leave_failed('$e'))));
    }
  }

  void _showChannelMenu(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isFavorite = ref.read(chatFavoritesProvider).contains(channel.id);
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  isFavorite
                      ? Symbols.star_rounded
                      : Symbols.star_outline_rounded,
                  color: isFavorite ? Colors.amber.shade700 : null,
                ),
                title: Text(
                  isFavorite
                      ? l10n.chat_remove_favorite
                      : l10n.chat_add_favorite,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  ref
                      .read(chatFavoritesProvider.notifier)
                      .toggleFavorite(channel.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('频道设置'),
                onTap: () {
                  Navigator.pop(ctx);
                  final title = channel.title ?? l10n.chat_unnamed_channel;
                  ChatChannelSettingsSheet.show(context, channel.id, title);
                },
              ),
              if (channel.isJoined)
                ListTile(
                  leading: Icon(
                    Icons.logout_rounded,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    _leaveLabel(context),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _leaveFromList(context, ref);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentUser = ref.watch(currentUserProvider).value;
    final lastMessage = channel.lastMessage;
    final hasUnread = channel.unreadCount > 0;
    final favorites = ref.watch(chatFavoritesProvider);
    final isFavorite = favorites.contains(channel.id);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      horizontalTitleGap: 12,
      minVerticalPadding: 6,
      leading: _buildLeading(context, currentUser?.id),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _resolveTitle(context, currentUser?.id),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (isFavorite) ...[
            const SizedBox(width: 6),
            Icon(Symbols.star_rounded, size: 16, color: Colors.amber.shade700),
          ],
        ],
      ),
      subtitle: lastMessage != null
          ? EmojiText(
              _resolveLastMessagePreview(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: hasUnread
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: hasUnread ? FontWeight.w500 : FontWeight.w400,
              ),
            )
          : null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (channel.lastMessageSentAt != null)
            Text(
              TimeUtils.formatRelativeTime(channel.lastMessageSentAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: hasUnread
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          if (hasUnread) ...[
            const SizedBox(height: 4),
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
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
      tileColor: hasUnread
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.12)
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
      onLongPress: () => _showChannelMenu(context, ref),
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

/// 新建直接消息对话框
///
/// 搜索用户并创建直接消息频道。
class _NewDmDialog extends ConsumerStatefulWidget {
  const _NewDmDialog({required this.initialMode});

  final _NewChatCreatorMode initialMode;

  @override
  ConsumerState<_NewDmDialog> createState() => _NewDmDialogState();
}

class _NewDmDialogState extends ConsumerState<_NewDmDialog> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _groupNameController = TextEditingController();
  final List<Chatable> _selected = [];
  List<Chatable> _results = [];
  bool _isSearching = false;
  bool _isCreating = false;
  late _NewChatCreatorMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _groupNameController.dispose();
    super.dispose();
  }

  bool get _canCreateDm {
    final user = ref.read(currentUserProvider).value;
    // canDirectMessage 来自 currentUser JSON；缺失时不阻断（站点若禁 DM，
    // 创建接口会返回错误，由 SnackBar 展示）。
    if (user?.canDirectMessage == false) return false;
    return true;
  }

  bool get _isGroup => _mode == _NewChatCreatorMode.group;

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
      final me = ref.read(currentUserProvider).value?.username.toLowerCase();
      // 过滤自己、已选用户，以及 system（服务端通常也不返回）
      final filtered = results.where((u) {
        final name = u.username.toLowerCase();
        if (name.isEmpty || name == 'system') return false;
        if (me != null && name == me) return false;
        if (_selected.any((s) => s.id == u.id || s.username == u.username)) {
          return false;
        }
        return true;
      }).toList();
      setState(() {
        _results = filtered;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSearching = false);
    }
  }

  void _toggleUser(Chatable user) {
    final exists = _selected.any((s) => s.id == user.id);
    setState(() {
      if (exists) {
        _selected.removeWhere((s) => s.id == user.id);
      } else {
        _selected.add(user);
      }
    });
    // 选中后清搜索框，方便继续加下一位
    if (!exists) {
      _searchController.clear();
      _results = [];
    }
  }

  Future<void> _selectUser(Chatable user) async {
    if (_mode == _NewChatCreatorMode.group) {
      _toggleUser(user);
      return;
    }

    setState(() {
      _selected
        ..clear()
        ..add(user);
    });
    await _create();
  }

  void _switchToGroupMode() {
    if (_isCreating) return;
    setState(() {
      _mode = _NewChatCreatorMode.group;
      _selected.clear();
      _results.clear();
      _searchController.clear();
    });
  }

  void _cancelGroupMode() {
    if (_isCreating) return;
    if (widget.initialMode == _NewChatCreatorMode.group) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _mode = _NewChatCreatorMode.message;
      _selected.clear();
      _results.clear();
      _groupNameController.clear();
      _searchController.clear();
    });
  }

  List<ChatChannel> _messageChannels(String query) {
    final state = ref.read(chatChannelsProvider).value;
    if (state == null) return const [];

    final channels = <ChatChannel>[
      ...state.publicChannels,
      ...state.directMessageChannels,
    ];
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return channels;

    final currentUserId = ref.read(currentUserProvider).value?.id;
    return channels.where((channel) {
      final title = _messageChannelTitle(channel, currentUserId).toLowerCase();
      final slug = channel.slug?.toLowerCase() ?? '';
      final target = channel.getDmTargetUser(currentUserId);
      final username = target?.username.toLowerCase() ?? '';
      final name = target?.name?.toLowerCase() ?? '';
      return title.contains(trimmed) ||
          slug.contains(trimmed) ||
          username.contains(trimmed) ||
          name.contains(trimmed);
    }).toList();
  }

  String _messageChannelTitle(ChatChannel channel, int? currentUserId) {
    if (channel.isDirectMessage) {
      if (channel.isGroupDm &&
          channel.title != null &&
          channel.title!.trim().isNotEmpty) {
        return channel.title!.trim();
      }
      final user = channel.getDmTargetUser(currentUserId);
      if (user != null) return user.name ?? user.username;
      final title = channel.title?.trim();
      if (title != null && title.isNotEmpty) return title;
      return context.l10n.chat_dm_placeholder;
    }

    final title = channel.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    final slug = channel.slug?.trim();
    if (slug != null && slug.isNotEmpty) return slug;
    return context.l10n.chat_unnamed_channel;
  }

  String? _resolveChatUserAvatarUrl(ChatUser? user) {
    final template = user?.avatarTemplate;
    if (template == null || template.isEmpty) return null;
    return UrlHelper.resolveUrlWithCdn(template.replaceAll('{size}', '48'));
  }

  void _openExistingChannel(ChatChannel channel) {
    final currentUserId = ref.read(currentUserProvider).value?.id;
    final title = _messageChannelTitle(channel, currentUserId);
    Navigator.of(context).pop();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChatMessagePage(channelId: channel.id, channelTitle: title),
      ),
    );
  }

  void _removeSelected(Chatable user) {
    setState(() => _selected.removeWhere((s) => s.id == user.id));
  }

  Future<void> _create() async {
    if (_isCreating || _selected.isEmpty) return;
    if (!_canCreateDm) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.chat_dm_disabled)));
      return;
    }
    setState(() => _isCreating = true);
    try {
      final usernames = _selected.map((u) => u.username).toList();
      final groupName = _groupNameController.text.trim();
      final channelId = await ref.read(
        createDirectMessageProvider((
          usernames: usernames,
          name: _isGroup && groupName.isNotEmpty ? groupName : null,
        )).future,
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      final title = _isGroup
          ? (groupName.isNotEmpty
                ? groupName
                : _selected
                      .map(
                        (u) => u.name?.trim().isNotEmpty == true
                            ? u.name!
                            : u.username,
                      )
                      .join(', '))
          : (_selected.first.name ?? _selected.first.username);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ChatMessagePage(channelId: channelId, channelTitle: title),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCreating = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${context.l10n.chat_error}: $e')));
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

  Widget _buildSearchResults(ThemeData theme, AppLocalizations l10n) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    final query = _searchController.text.trim();

    if (_isGroup) {
      if (_results.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            query.isEmpty ? l10n.chat_select_users_hint : l10n.chat_no_results,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      }

      return ListView.builder(
        shrinkWrap: true,
        itemCount: _results.length,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemBuilder: (context, index) {
          final user = _results[index];
          final avatarUrl = _resolveUserAvatarUrl(user);
          final selected = _selected.any((s) => s.id == user.id);
          return ListTile(
            leading: SmartAvatar(
              imageUrl: avatarUrl,
              radius: 20,
              fallbackText: user.username,
            ),
            title: _buildUserTitle(
              theme,
              user.name ?? user.username,
              user.name == null ? null : user.username,
            ),
            trailing: Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.add_circle_outline_rounded,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            onTap: _isCreating ? null : () => _selectUser(user),
          );
        },
      );
    }

    final currentUserId = ref.read(currentUserProvider).value?.id;
    final channels = _messageChannels(query);
    final channelUsernames = <String>{
      for (final channel in channels)
        if (channel.getDmTargetUser(currentUserId) case final user?)
          user.username.toLowerCase(),
    };
    final remoteUsers = _results
        .where(
          (user) => !channelUsernames.contains(user.username.toLowerCase()),
        )
        .toList();

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount:
          (query.isEmpty ? 1 : 0) + channels.length + remoteUsers.length,
      itemBuilder: (context, index) {
        if (query.isEmpty && index == 0) {
          return ListTile(
            minTileHeight: 62,
            selected: true,
            selectedTileColor: theme.colorScheme.primaryContainer.withValues(
              alpha: 0.55,
            ),
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.group_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            title: Text(
              l10n.chat_new_group,
              style: theme.textTheme.titleMedium,
            ),
            onTap: _switchToGroupMode,
          );
        }

        final dataIndex = index - (query.isEmpty ? 1 : 0);
        if (dataIndex < channels.length) {
          final channel = channels[dataIndex];
          final targetUser = channel.getDmTargetUser(currentUserId);
          final title = _messageChannelTitle(channel, currentUserId);

          Widget leading;
          String? username;
          if (channel.isDirectMessage && !channel.isGroupDm && targetUser != null) {
            leading = SmartAvatar(
              imageUrl: _resolveChatUserAvatarUrl(targetUser),
              radius: 20,
              fallbackText: targetUser.username,
            );
            username = targetUser.username;
          } else if (channel.emojiShortcode case final emoji?
              when emoji.isNotEmpty) {
            leading = CircleAvatar(
              radius: 20,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: EmojiText(emoji, style: const TextStyle(fontSize: 19)),
            );
          } else {
            leading = CircleAvatar(
              radius: 20,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                channel.isDirectMessage
                    ? Icons.groups_rounded
                    : Icons.chat_bubble_rounded,
                size: 22,
                color: channel.isDirectMessage
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.primary,
              ),
            );
          }

          return ListTile(
            minTileHeight: 62,
            leading: leading,
            title: _buildUserTitle(
              theme,
              title,
              username != null && username != title ? username : null,
            ),
            onTap: () => _openExistingChannel(channel),
          );
        }

        final user = remoteUsers[dataIndex - channels.length];
        return ListTile(
          minTileHeight: 62,
          leading: SmartAvatar(
            imageUrl: _resolveUserAvatarUrl(user),
            radius: 20,
            fallbackText: user.username,
          ),
          title: _buildUserTitle(
            theme,
            user.name ?? user.username,
            user.name == null ? null : user.username,
          ),
          onTap: _isCreating ? null : () => _selectUser(user),
        );
      },
    );
  }

  Widget _buildUserTitle(
    ThemeData theme,
    String primary,
    String? secondary,
  ) {
    if (secondary == null || secondary.isEmpty || secondary == primary) {
      return Text(
        primary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium,
      );
    }

    return Row(
      children: [
        Flexible(
          child: Text(
            primary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            secondary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final title = _isGroup ? l10n.chat_new_group : l10n.chat_send_message_title;
    final createLabel = l10n.chat_create_group_chat;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isGroup)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        enabled: !_isCreating,
                        decoration: InputDecoration(
                          hintText: l10n.chat_channel_filter,
                          prefixIcon: const Icon(AppIcons.search, size: 24),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: _onSearch,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                      icon: const Icon(AppIcons.close, size: 26),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_selected.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          l10n.chat_members_selected(_selected.length),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
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
            if (_isGroup) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: TextField(
                  controller: _groupNameController,
                  enabled: !_isCreating,
                  decoration: InputDecoration(
                    hintText: l10n.chat_group_name_hint,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              if (_selected.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    itemCount: _selected.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final user = _selected[index];
                      final label = user.name?.trim().isNotEmpty == true
                          ? user.name!
                          : user.username;
                      return InputChip(
                        avatar: SmartAvatar(
                          imageUrl: _resolveUserAvatarUrl(user),
                          radius: 12,
                          fallbackText: user.username,
                        ),
                        label: Text(label),
                        onDeleted: _isCreating
                            ? null
                            : () => _removeSelected(user),
                        deleteIconColor: theme.colorScheme.onSurfaceVariant,
                      );
                    },
                  ),
                ),
            ],
            if (_isGroup)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  enabled: !_isCreating,
                  decoration: InputDecoration(
                    hintText: l10n.chat_add_more_members_hint,
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
            Flexible(child: _buildSearchResults(theme, l10n)),
            if (_isGroup)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _isCreating ? null : _cancelGroupMode,
                      child: Text(l10n.chat_cancel),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _isCreating || _selected.isEmpty
                          ? null
                          : _create,
                      child: _isCreating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(createLabel),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 全局消息串 Tab 视图
///
/// 按最后回复时间展示所有已启用消息串频道的线程列表，
/// 提供快速进入消息串讨论的入口。
class _ChatThreadTabView extends ConsumerWidget {
  const _ChatThreadTabView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final threadsAsync = ref.watch(chatAllThreadsProvider);

    return threadsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('加载失败: $e'),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => ref.invalidate(chatAllThreadsProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
      data: (threads) {
        if (threads.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.forum_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '还没有消息串\n回复消息即可开启讨论',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(chatAllThreadsProvider);
            await ref.read(chatAllThreadsProvider.future);
          },
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: threads.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final (thread, channel) = threads[index];
              final om = thread.originalMessage;
              String? avatarUrl;
              if (om?.user?.avatarTemplate != null) {
                avatarUrl = UrlHelper.resolveUrlWithCdn(
                  om!.user!.avatarTemplate!.replaceAll('{size}', '48'),
                );
              }
              final replyCount =
                  thread.preview?.replyCount ?? thread.replyCount;
              final lastAt = thread.preview?.lastReplyCreatedAt;
              final time = lastAt != null
                  ? TimeUtils.formatRelativeTime(lastAt)
                  : (om?.createdAt != null
                        ? TimeUtils.formatRelativeTime(om!.createdAt!)
                        : null);

              return ListTile(
                leading: SmartAvatar(
                  imageUrl: avatarUrl,
                  radius: 20,
                  fallbackText: om?.user?.username,
                ),
                title: Text(
                  thread.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer
                              .withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          channel.title ?? '#${channel.id}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.forum_outlined,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        replyCount > 0 ? '$replyCount 条回复' : '消息串',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      if (om?.user?.username != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '@${om!.user!.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                      if (time != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  ChatMessage? original;
                  if (om != null) {
                    try {
                      original = ChatMessage.fromJson(om.toMessageJson());
                    } catch (_) {}
                  }
                  if (!context.mounted) return;
                  await ChatThreadSheet.show(
                    context,
                    channelId: channel.id,
                    thread: thread,
                    originalMessage: original,
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
