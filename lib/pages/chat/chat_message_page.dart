import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat/chat_models.dart';
import '../../providers/chat_providers.dart';
import '../../providers/core_providers.dart';
import '../../utils/time_utils.dart';
import '../../utils/url_helper.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/loading_spinner.dart';
import '../../widgets/common/smart_avatar.dart';

/// Chat 消息页面
///
/// 展示指定频道的聊天消息，支持发送消息、加载历史、标记已读和自动滚动。
class ChatMessagePage extends ConsumerStatefulWidget {
  final int channelId;
  final String channelTitle;

  const ChatMessagePage({
    super.key,
    required this.channelId,
    required this.channelTitle,
  });

  @override
  ConsumerState<ChatMessagePage> createState() => _ChatMessagePageState();
}

class _ChatMessagePageState extends ConsumerState<ChatMessagePage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  bool _isSending = false;
  bool _isAtBottom = true;
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _textController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    // 检测是否在底部附近
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final atBottom = (maxScroll - currentScroll) < 100;
    if (atBottom != _isAtBottom) {
      setState(() => _isAtBottom = atBottom);
    }

    // 滚动到顶部时加载更多历史消息
    if (_scrollController.position.pixels <= 50) {
      _loadMoreMessages();
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadMoreMessages() async {
    final notifier = ref.read(chatMessagesProvider(widget.channelId).notifier);
    if (!notifier.canLoadMorePast || notifier.isLoadingMore) return;
    await notifier.loadMore();
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    try {
      final notifier = ref.read(chatMessagesProvider(widget.channelId).notifier);
      await notifier.sendMessage(text);
      _textController.clear();
      // 发送成功后滚动到底部
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.l10n.chat_send_failed}: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// 标记最近一条消息为已读
  void _markAsRead(List<ChatMessage> messages) {
    if (messages.isEmpty) return;
    // 取最后一条可见消息的 id 标记已读
    final lastMessage = messages.last;
    final notifier = ref.read(chatMessagesProvider(widget.channelId).notifier);
    notifier.markAsRead(lastMessage.id);
  }

  /// 构建头像 URL
  String? _buildAvatarUrl(ChatUser? user) {
    if (user == null || user.avatarTemplate == null) return null;
    final template = user.avatarTemplate!.replaceAll('{size}', '40');
    return UrlHelper.resolveUrlWithCdn(template);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messagesAsync = ref.watch(chatMessagesProvider(widget.channelId));
    final currentUser = ref.watch(currentUserProvider).value;

    // 监听消息列表变化，数据加载完成后自动滚动到底部
    ref.listen(chatMessagesProvider(widget.channelId), (_, next) {
      next.whenData((messages) {
        if (!_initialLoadDone) {
          _initialLoadDone = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom();
            _markAsRead(messages);
          });
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.channelTitle),
        actions: [
          if (!_isAtBottom && messagesAsync.valueOrNull != null)
            IconButton(
              icon: const Icon(Icons.arrow_downward_rounded),
              tooltip: context.l10n.chat_scroll_to_bottom,
              onPressed: _scrollToBottom,
            ),
        ],
      ),
      body: Column(
        children: [
          // 消息列表
          Expanded(
            child: messagesAsync.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return _buildEmptyState(theme);
                }

                // 首次加载后标记已读
                if (_initialLoadDone) {
                  _markAsRead(messages);
                }

                return NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollEndNotification &&
                        notification.metrics.pixels <= 50) {
                      _loadMoreMessages();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      12,
                      12,
                      12,
                      12 + MediaQuery.paddingOf(context).bottom,
                    ),
                    itemCount: messages.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        // 顶部加载更多指示器
                        return _buildLoadMoreIndicator();
                      }

                      final message = messages[index - 1];
                      final isOwnMessage =
                          currentUser != null &&
                          message.user != null &&
                          message.user!.id == currentUser.id;

                      return _ChatMessageBubble(
                        message: message,
                        isOwnMessage: isOwnMessage,
                        avatarUrl: _buildAvatarUrl(message.user),
                        theme: theme,
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(
                child: LoadingSpinner(size: 36),
              ),
              error: (error, stack) => ErrorView(
                error: error,
                stackTrace: stack,
                onRetry: () {
                  ref.invalidate(chatMessagesProvider(widget.channelId));
                },
              ),
            ),
          ),

          // 输入区域
          _buildInputBar(theme),
        ],
      ),
    );
  }

  Widget _buildLoadMoreIndicator() {
    final notifier = ref.read(chatMessagesProvider(widget.channelId).notifier);
    if (!notifier.canLoadMorePast && !notifier.isLoadingMore) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: notifier.isLoadingMore
            ? const SizedBox(
                width: 24,
                height: 24,
                child: LoadingSpinner(size: 24),
              )
            : SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  icon: Icon(
                    Icons.expand_less_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  tooltip: context.l10n.chat_load_more,
                  onPressed: _loadMoreMessages,
                ),
              ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_rounded,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.chat_no_messages,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.chat_send_first_message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  focusNode: _inputFocusNode,
                  textInputAction: TextInputAction.send,
                  maxLines: 5,
                  minLines: 1,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: InputDecoration(
                    hintText: context.l10n.chat_input_hint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: _isSending ? null : _sendMessage,
                icon: _isSending
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : Icon(Icons.send_rounded),
                color: theme.colorScheme.primary,
                tooltip: context.l10n.chat_send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单条 Chat 消息气泡组件
class _ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isOwnMessage;
  final String? avatarUrl;
  final ThemeData theme;

  const _ChatMessageBubble({
    required this.message,
    required this.isOwnMessage,
    this.avatarUrl,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    // 删除的消息不显示内容
    if (message.deleted) {
      return _buildDeletedMessage();
    }

    final alignment =
        isOwnMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    // 发送者信息：其他人的消息显示头像和名字
    final showSender = !isOwnMessage && message.user != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 别人消息的头像
              if (showSender)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 4),
                  child: SmartAvatar(
                    imageUrl: avatarUrl,
                    radius: 16,
                    fallbackText: message.user!.username,
                  ),
                ),

              // 消息气泡
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72,
                  ),
                  child: Column(
                    crossAxisAlignment: alignment,
                    children: [
                      // 用户名（仅显示在他人消息中）
                      if (showSender)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 4,
                            bottom: 2,
                          ),
                          child: Text(
                            message.user!.name ?? message.user!.username,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                      // 气泡主体
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isOwnMessage
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16).copyWith(
                            bottomLeft: isOwnMessage
                                ? const Radius.circular(16)
                                : const Radius.circular(4),
                            bottomRight: isOwnMessage
                                ? const Radius.circular(4)
                                : const Radius.circular(16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 消息文本
                            Text(
                              message.message,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isOwnMessage
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            // 时间戳 + 编辑标记
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  TimeUtils.formatCompactTime(message.createdAt),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: (isOwnMessage
                                            ? theme.colorScheme
                                                .onPrimaryContainer
                                            : theme.colorScheme
                                                .onSurfaceVariant)
                                        .withValues(alpha: 0.6),
                                    fontSize: 10,
                                  ),
                                ),
                                if (message.edited) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    context.l10n.chat_edited,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: (isOwnMessage
                                              ? theme.colorScheme
                                                  .onPrimaryContainer
                                              : theme.colorScheme
                                                  .onSurfaceVariant)
                                          .withValues(alpha: 0.5),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeletedMessage() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      child: Row(
        mainAxisAlignment:
            isOwnMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              context.l10n.chat_message_deleted,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}