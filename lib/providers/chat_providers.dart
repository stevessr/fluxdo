import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat/chat_models.dart';
import '../utils/paged_async_notifier.dart';
import 'core_providers.dart';

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
    final service = ref.read(discourseServiceProvider);
    final raw = await service.getChannelMessages(
      channelId,
      pageSize: 50,
      fetchFromLastRead: true,
    );
    final messages = _parseMessages(raw);
    final hasMore = raw['can_load_more_past'] as bool? ?? false;
    canLoadMoreFuture = raw['can_load_more_future'] as bool? ?? false;
    targetMessageId = raw['target_message_id'] as int?;
    return completePagedRefresh(
      PagedPage(items: messages, hasMore: hasMore),
    );
  }

  /// 重新加载消息列表
  Future<void> loadMessages() async {
    await runPagedRefresh(() async {
      final service = ref.read(discourseServiceProvider);
      final raw = await service.getChannelMessages(
        channelId,
        pageSize: 50,
        fetchFromLastRead: true,
      );
      final messages = _parseMessages(raw);
      final hasMore = raw['can_load_more_past'] as bool? ?? false;
      canLoadMoreFuture = raw['can_load_more_future'] as bool? ?? false;
      targetMessageId = raw['target_message_id'] as int?;
      return PagedPage(items: messages, hasMore: hasMore);
    });
  }

  /// 加载更多历史消息（向上翻页）
  Future<void> loadMore() async {
    await runPagedLoadMore((currentItems, nextPage) async {
      // 取当前最早消息的 id 作为 targetMessageId 来获取更早的消息
      final service = ref.read(discourseServiceProvider);
      final raw = await service.getChannelMessages(
        channelId,
        pageSize: 50,
        direction: 'backward',
        targetMessageId: currentItems.isNotEmpty ? currentItems.first.id : null,
      );
      final messages = _parseMessages(raw);
      final hasMorePast = raw['can_load_more_past'] as bool? ?? false;
      canLoadMoreFuture = raw['can_load_more_future'] as bool? ?? false;
      return PagedPage(
        items: [...messages, ...currentItems],
        hasMore: hasMorePast,
        advancePage: messages.isNotEmpty,
      );
    });
  }

  /// 发送消息
  Future<int> sendMessage(String text) async {
    final service = ref.read(discourseServiceProvider);
    final messageId = await service.sendChatMessage(channelId, text);
    // 发送成功后刷新消息列表
    unawaited(loadMessages());
    return messageId;
  }

  /// 标记已读
  Future<void> markAsRead(int messageId) async {
    final service = ref.read(discourseServiceProvider);
    await service.markChannelRead(channelId, messageId);
  }

  /// 加载更多失败时重试
  Future<void> retryLoadMore() {
    return retryPagedLoadMore(loadMore);
  }

  /// 解析消息列表
  List<ChatMessage> _parseMessages(Map<String, dynamic> raw) {
    final messages = raw['chat_messages'] as List<dynamic>? ?? [];
    return messages
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}

final chatMessagesProvider = AsyncNotifierProvider.family<
    ChatMessagesNotifier, List<ChatMessage>, int>(
  (ref, channelId) => ChatMessagesNotifier(channelId),
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