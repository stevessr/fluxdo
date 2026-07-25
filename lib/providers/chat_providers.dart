import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat/chat_models.dart';
import '../services/message_bus_service.dart';
import '../utils/paged_async_notifier.dart';
import 'core_providers.dart';
import 'message_bus/message_bus_service_provider.dart';
import 'message_bus/topic_tracking_providers.dart';
import 'theme_provider.dart';

/// ============================================================================
/// 1. Chat 频道列表
/// ============================================================================

/// Chat 频道列表 Notifier
class ChatChannelsNotifier extends AsyncNotifier<ChatChannelsState> {
  @override
  Future<ChatChannelsState> build() async {
    final service = ref.read(discourseServiceProvider);
    final raw = await service.getChatChannels();
    return ChatChannelsState.fromJson(raw);
  }

  /// 刷新频道列表
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(discourseServiceProvider);
      final raw = await service.getChatChannels();
      return ChatChannelsState.fromJson(raw);
    });
  }
}

final chatChannelsProvider =
    AsyncNotifierProvider.autoDispose<ChatChannelsNotifier, ChatChannelsState>(
  ChatChannelsNotifier.new,
);

/// ============================================================================
/// 2. Chat 消息列表（按频道分页）
/// ============================================================================

/// Chat 消息列表 Notifier（按 channelId 分页）
class ChatMessagesNotifier extends AsyncNotifier<List<ChatMessage>>
    with PagedAsyncNotifierMixin<ChatMessage> {
  final int channelId;

  ChatMessagesNotifier(this.channelId);

  /// 是否可向前加载更多（旧消息）
  bool get canLoadMorePast => hasMore;

  /// 是否可向后加载更多（新消息，通常为 false）
  bool canLoadMoreFuture = false;

  /// 定位到指定消息 ID 时传入
  int? targetMessageId;

  @override
  Future<List<ChatMessage>> build() async {
    resetPagingState();
    _subscribeMessageBus();
    final service = ref.read(discourseServiceProvider);

    Map<String, dynamic> raw;
    try {
      raw = await service.getChannelMessages(
        channelId,
        pageSize: 50,
        fetchFromLastRead: true,
      );
    } catch (_) {
      raw = await service.getChannelMessages(
        channelId,
        pageSize: 50,
      );
    }

    var messages = _parseMessages(raw);

    // 容错处理：如果带 fetchFromLastRead 返回空消息，降级重新请求最新 50 条消息
    if (messages.isEmpty) {
      try {
        final fallbackRaw = await service.getChannelMessages(
          channelId,
          pageSize: 50,
        );
        final fallbackMessages = _parseMessages(fallbackRaw);
        if (fallbackMessages.isNotEmpty) {
          raw = fallbackRaw;
          messages = fallbackMessages;
        }
      } catch (_) {}
    }

    final hasMore = (raw['can_load_more_past'] as bool?) ??
        (raw['meta'] is Map ? raw['meta']['can_load_more_past'] as bool? : null) ??
        (messages.length >= 10);
    canLoadMoreFuture = raw['can_load_more_future'] as bool? ?? false;
    targetMessageId = (raw['target_message_id'] as num?)?.toInt();
    return completePagedRefresh(
      PagedPage(items: messages, hasMore: hasMore),
    );
  }

  void _subscribeMessageBus() {
    try {
      ref.watch(messageBusInitProvider);
      final messageBus = ref.watch(messageBusServiceProvider);
      final channel = '/chat/c/$channelId';

      void onMessage(MessageBusMessage msg) {
        final data = msg.data;
        if (data is! Map<String, dynamic>) return;
        final type = data['type'] as String? ?? data['chat_message_type'] as String?;
        if (type == 'sent' || type == 'created' || data.containsKey('chat_message')) {
          unawaited(loadMessages());
        } else if (type == 'edited' || type == 'deleted') {
          unawaited(loadMessages());
        }
      }

      messageBus.subscribe(channel, onMessage);
      ref.onDispose(() {
        messageBus.unsubscribe(channel, onMessage);
      });
    } catch (_) {
      // MessageBus 可选监听，失败不影响主流程
    }
  }

  /// 重新加载消息列表
  Future<void> loadMessages() async {
    await runPagedRefresh(() async {
      final service = ref.read(discourseServiceProvider);
      Map<String, dynamic> raw;
      try {
        raw = await service.getChannelMessages(
          channelId,
          pageSize: 50,
          fetchFromLastRead: true,
        );
      } catch (_) {
        raw = await service.getChannelMessages(
          channelId,
          pageSize: 50,
        );
      }

      var messages = _parseMessages(raw);

      if (messages.isEmpty) {
        try {
          final fallbackRaw = await service.getChannelMessages(
            channelId,
            pageSize: 50,
          );
          final fallbackMessages = _parseMessages(fallbackRaw);
          if (fallbackMessages.isNotEmpty) {
            raw = fallbackRaw;
            messages = fallbackMessages;
          }
        } catch (_) {}
      }

      final hasMore = (raw['can_load_more_past'] as bool?) ??
          (raw['meta'] is Map ? raw['meta']['can_load_more_past'] as bool? : null) ??
          (messages.length >= 10);
      canLoadMoreFuture = raw['can_load_more_future'] as bool? ?? false;
      targetMessageId = (raw['target_message_id'] as num?)?.toInt();
      return PagedPage(items: messages, hasMore: hasMore);
    });
  }

  /// 加载更多历史消息（向上翻页）
  Future<void> loadMore() async {
    await runPagedLoadMore((currentItems, nextPage) async {
      // 取当前最早消息的 id (即最小值) 作为 targetMessageId 来获取更早的历史消息
      final minTargetId = currentItems.isNotEmpty
          ? currentItems.map((m) => m.id).reduce((a, b) => a < b ? a : b)
          : null;
      final service = ref.read(discourseServiceProvider);
      final raw = await service.getChannelMessages(
        channelId,
        pageSize: 50,
        direction: 'past',
        targetMessageId: minTargetId,
      );
      final messages = _parseMessages(raw);

      final existingIds = currentItems.map((m) => m.id).toSet();
      final newMessages = messages.where((m) => !existingIds.contains(m.id)).toList();
      newMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      final combined = [...newMessages, ...currentItems];
      combined.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      final hasMorePast = (raw['can_load_more_past'] as bool?) ??
          (raw['meta'] is Map ? raw['meta']['can_load_more_past'] as bool? : null) ??
          (messages.isNotEmpty && messages.length >= 10);
      canLoadMoreFuture = raw['can_load_more_future'] as bool? ?? false;
      return PagedPage(
        items: combined,
        hasMore: hasMorePast,
        advancePage: newMessages.isNotEmpty,
      );
    });
  }

  /// 发送消息（支持回复和附件）
  Future<int> sendMessage(
    String text, {
    int? threadId,
    int? inReplyToId,
    List<int>? uploadIds,
  }) async {
    final service = ref.read(discourseServiceProvider);
    final messageId = await service.sendChatMessage(
      channelId,
      text,
      threadId: threadId,
      inReplyToId: inReplyToId,
      uploadIds: uploadIds,
    );
    // 发送成功后刷新消息列表
    unawaited(loadMessages());
    return messageId;
  }

  /// 编辑消息
  Future<void> editMessage(int messageId, String newText) async {
    final service = ref.read(discourseServiceProvider);
    await service.updateChatMessage(channelId, messageId, newText);
    unawaited(loadMessages());
  }

  /// 删除消息
  Future<void> deleteMessage(int messageId) async {
    final service = ref.read(discourseServiceProvider);
    await service.deleteChatMessage(channelId, messageId);
    unawaited(loadMessages());
  }

  /// 标记已读
  Future<void> markAsRead(int messageId) async {
    final service = ref.read(discourseServiceProvider);
    await service.markChannelRead(channelId, messageId);
  }

  /// 切换消息 Emoji 回应 (Reaction)
  Future<void> toggleReaction(int messageId, String emoji) async {
    final currentList = state.value ?? [];
    final msgIndex = currentList.indexWhere((m) => m.id == messageId);
    if (msgIndex == -1) return;

    final msg = currentList[msgIndex];
    final reactions = List<ChatMessageReaction>.from(msg.reactions ?? []);
    final rIndex = reactions.indexWhere((r) => r.emoji == emoji);

    final isAlreadyReacted = rIndex != -1 && reactions[rIndex].reacted;
    final action = isAlreadyReacted ? 'remove' : 'add';

    // 乐观更新 UI
    final newReactions = List<ChatMessageReaction>.from(reactions);
    if (isAlreadyReacted) {
      final old = newReactions[rIndex];
      if (old.count <= 1) {
        newReactions.removeAt(rIndex);
      } else {
        newReactions[rIndex] = ChatMessageReaction(
          emoji: old.emoji,
          count: old.count - 1,
          reacted: false,
        );
      }
    } else {
      if (rIndex != -1) {
        final old = newReactions[rIndex];
        newReactions[rIndex] = ChatMessageReaction(
          emoji: old.emoji,
          count: old.count + 1,
          reacted: true,
        );
      } else {
        newReactions.add(ChatMessageReaction(
          emoji: emoji,
          count: 1,
          reacted: true,
        ));
      }
    }

    final updatedMsg = msg.copyWith(reactions: newReactions);
    final updatedList = List<ChatMessage>.from(currentList);
    updatedList[msgIndex] = updatedMsg;
    state = AsyncValue.data(updatedList);

    try {
      final service = ref.read(discourseServiceProvider);
      await service.reactToChatMessage(channelId, messageId, emoji, action: action);
    } catch (_) {
      // 失败回滚
      state = AsyncValue.data(currentList);
    }
  }

  /// 切换消息书签状态 (Bookmark)
  Future<void> toggleBookmark(int messageId) async {
    final currentList = state.value ?? [];
    final msgIndex = currentList.indexWhere((m) => m.id == messageId);
    if (msgIndex == -1) return;

    final msg = currentList[msgIndex];
    final nextBookmarked = !msg.bookmarked;

    // 乐观更新 UI
    final updatedList = List<ChatMessage>.from(currentList);
    updatedList[msgIndex] = msg.copyWith(bookmarked: nextBookmarked);
    state = AsyncValue.data(updatedList);

    try {
      final service = ref.read(discourseServiceProvider);
      await service.toggleChatMessageBookmark(channelId, messageId, bookmarked: nextBookmarked);
    } catch (_) {
      // 失败回滚
      state = AsyncValue.data(currentList);
    }
  }

  /// 加载更多失败时重试
  Future<void> retryLoadMore() {
    return retryPagedLoadMore(loadMore);
  }

  /// 解析消息列表（支持时间升序排序）
  List<ChatMessage> _parseMessages(Map<String, dynamic> raw) {
    final list = raw['chat_messages'] ?? raw['messages'];
    if (list is! List) return [];

    // 解析顶层 users 映射，供消息缺失 user 字段时按 user_id 匹配补全
    final usersMap = <int, ChatUser>{};
    if (raw['users'] is List) {
      for (final u in raw['users'] as List) {
        if (u is Map) {
          final user = ChatUser.fromJson(Map<String, dynamic>.from(u));
          usersMap[user.id] = user;
        }
      }
    }

    final parsed = list.map((e) {
      if (e is! Map) return null;
      final json = Map<String, dynamic>.from(e);
      if (json['user'] == null && json['user_id'] != null) {
        final userId = (json['user_id'] as num?)?.toInt();
        if (userId != null && usersMap.containsKey(userId)) {
          json['user'] = usersMap[userId]!.toJson();
        }
      }
      return ChatMessage.fromJson(json);
    }).whereType<ChatMessage>().toList();

    parsed.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return parsed;
  }
}

final chatMessagesProvider = AsyncNotifierProvider.family<
    ChatMessagesNotifier, List<ChatMessage>, int>(
  ChatMessagesNotifier.new,
);

/// ============================================================================
/// 3. 未读统计 Provider
/// ============================================================================

/// 所有 Chat 频道的未读消息总数
///
/// 从 [chatChannelsProvider] 的 tracking 数据中提取并汇总。
final chatUnreadProvider = Provider<int>((ref) {
  final channelsState = ref.watch(chatChannelsProvider);
  final tracking = channelsState.value?.tracking;
  if (tracking == null || tracking.isEmpty) return 0;
  var total = 0;
  for (final entry in tracking.entries) {
    total += (entry.value['unread_count'] as num?)?.toInt() ?? 0;
  }
  return total;
});

/// ============================================================================
/// 4. 创建私信频道
/// ============================================================================

final createDirectMessageProvider =
    FutureProvider.family<int, List<String>>((ref, targetUsernames) async {
  final service = ref.read(discourseServiceProvider);
  final channelId = await service.createDirectMessageChannel(targetUsernames);
  // 创建后刷新频道列表
  ref.invalidate(chatChannelsProvider);
  return channelId;
});

/// ============================================================================
/// 5. 搜索 Chat 可提及用户
/// ============================================================================

final chatSearchProvider =
    FutureProvider.family<List<Chatable>, String>((ref, filter) async {
  final service = ref.read(discourseServiceProvider);
  final raw = await service.searchChatables(filter);
  final users = raw['users'] as List<dynamic>? ?? [];
  return users
      .map((e) => Chatable.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
});

/// ============================================================================
/// 6. 频道成员列表与添加成员 Provider
/// ============================================================================

final chatChannelMembersProvider =
    FutureProvider.family<List<ChatUser>, int>((ref, channelId) async {
  final service = ref.read(discourseServiceProvider);
  final list = <ChatUser>[];
  final seenUsernames = <String>{};

  // 1. 尝试从 API 获取频道成员列表
  try {
    final membersRaw = await service.getChannelMembers(channelId);
    for (final e in membersRaw) {
      Map<String, dynamic>? userMap;
      if (e['user'] is Map) {
        userMap = Map<String, dynamic>.from(e['user'] as Map);
      } else if (e['user_chat_channel_membership'] is Map &&
          e['user_chat_channel_membership']['user'] is Map) {
        userMap = Map<String, dynamic>.from(
            e['user_chat_channel_membership']['user'] as Map);
      } else {
        userMap = Map<String, dynamic>.from(e);
      }
      final u = ChatUser.fromJson(userMap);
      if (u.username.isNotEmpty && seenUsernames.add(u.username)) {
        list.add(u);
      }
    }
  } catch (_) {}

  // 2. 补充 dmUsers (私信频道固定成员)
  final channelsState = ref.read(chatChannelsProvider).value;
  if (channelsState != null) {
    final allChannels = [
      ...channelsState.publicChannels,
      ...channelsState.directMessageChannels,
    ];
    ChatChannel? channelObj;
    for (final c in allChannels) {
      if (c.id == channelId) {
        channelObj = c;
        break;
      }
    }
    if (channelObj?.dmUsers != null) {
      for (final u in channelObj!.dmUsers!) {
        if (u.username.isNotEmpty && seenUsernames.add(u.username)) {
          list.add(u);
        }
      }
    }
  }

  // 3. 从聊天消息记录中补充发言过或被提及的用户
  final messagesState = ref.read(chatMessagesProvider(channelId));
  final currentMessages = messagesState.value ?? [];
  for (final msg in currentMessages) {
    if (msg.user != null &&
        msg.user!.username.isNotEmpty &&
        seenUsernames.add(msg.user!.username)) {
      list.add(ChatUser(
        id: msg.user!.id,
        username: msg.user!.username,
        name: msg.user!.name,
        avatarTemplate: msg.user!.avatarTemplate,
      ));
    }
  }

  return list;
});

final addChannelMemberProvider =
    FutureProvider.family<void, ({int channelId, String username})>(
        (ref, params) async {
  final service = ref.read(discourseServiceProvider);
  await service.addChannelMember(params.channelId, params.username);
  ref.invalidate(chatChannelMembersProvider(params.channelId));
});

/// ============================================================================
/// 7. Chat 收藏频道 Provider
/// ============================================================================

class ChatFavoritesNotifier extends Notifier<Set<int>> {
  static const _key = 'favorite_chat_channel_ids';

  @override
  Set<int> build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final localList = prefs.getStringList(_key) ?? [];
    final set = localList.map((e) => int.tryParse(e)).whereType<int>().toSet();

    // 优先以后端 Discourse 权威数据 (starred/following) 为准，保持与云端一致
    final channelsAsync = ref.watch(chatChannelsProvider);
    final channelsState = channelsAsync.value;
    if (channelsState != null) {
      final allChannels = [
        ...channelsState.publicChannels,
        ...channelsState.directMessageChannels,
      ];
      for (final channel in allChannels) {
        final isServerFav = channel.starred ||
            channel.following ||
            (channel.userChatChannelMembership?['starred'] == true) ||
            (channel.userChatChannelMembership?['following'] == true);

        if (isServerFav) {
          set.add(channel.id);
        }
      }
    }

    return set;
  }

  Future<void> toggleFavorite(int channelId) async {
    final next = Set<int>.from(state);
    final isFav = next.contains(channelId);
    if (isFav) {
      next.remove(channelId);
    } else {
      next.add(channelId);
    }
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setStringList(_key, next.map((e) => e.toString()).toList());

    // 同步关注/取消关注到 Discourse 服务端
    try {
      final service = ref.read(discourseServiceProvider);
      await service.followChannel(channelId, follow: !isFav);
      // 刷新频道列表保持云端与本地状态强一致
      ref.invalidate(chatChannelsProvider);
    } catch (_) {}
  }

  bool isFavorite(int channelId) => state.contains(channelId);
}

final chatFavoritesProvider =
    NotifierProvider<ChatFavoritesNotifier, Set<int>>(
  ChatFavoritesNotifier.new,
);

/// ============================================================================
/// 8. 频道浏览 Provider（论坛所有公开频道）
/// ============================================================================

/// 浏览频道请求参数
class BrowseChannelsParams {
  final String? status;
  final String? filter;

  const BrowseChannelsParams({this.status, this.filter});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrowseChannelsParams &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          filter == other.filter;

  @override
  int get hashCode => Object.hash(status, filter);
}

/// 浏览频道列表 Provider
///
/// 获取论坛中所有公开频道（支持 status 过滤和搜索）
final browseChannelsProvider =
    FutureProvider.family<List<ChatChannel>, BrowseChannelsParams>(
        (ref, params) async {
  final service = ref.read(discourseServiceProvider);
  final raw = await service.browseChannels(
    status: params.status,
    filter: params.filter,
  );
  final channels = raw['channels'] as List? ?? [];
  return channels
      .map((e) => ChatChannel.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
});

/// 加入频道 Provider
final joinChannelProvider =
    FutureProvider.family<void, int>((ref, channelId) async {
  final service = ref.read(discourseServiceProvider);
  await service.joinChannel(channelId);
  // 刷新频道列表
  ref.invalidate(chatChannelsProvider);
});

/// 离开频道 Provider
final leaveChannelProvider =
    FutureProvider.family<void, int>((ref, channelId) async {
  final service = ref.read(discourseServiceProvider);
  await service.leaveChannel(channelId);
  // 刷新频道列表
  ref.invalidate(chatChannelsProvider);
});