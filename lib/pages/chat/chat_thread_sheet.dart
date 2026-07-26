import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat/chat_models.dart';
import '../../providers/chat_providers.dart';
import '../../utils/time_utils.dart';
import '../../utils/url_helper.dart';
import '../../widgets/common/app_bottom_sheet.dart';
import '../../widgets/common/emoji_text.dart';
import '../../widgets/common/smart_avatar.dart';
import '../../widgets/markdown_editor/emoji_sticker_panel.dart';

/// 消息串底部面板：展示串内消息并支持回复。
class ChatThreadSheet extends ConsumerStatefulWidget {
  final int channelId;
  final ChatThread thread;
  final ChatMessage? originalMessage;

  const ChatThreadSheet({
    super.key,
    required this.channelId,
    required this.thread,
    this.originalMessage,
  });

  static Future<void> show(
    BuildContext context, {
    required int channelId,
    required ChatThread thread,
    ChatMessage? originalMessage,
  }) {
    return AppBottomSheet.showDraggable(
      context: context,
      showCloseButton: true,
      title: thread.title?.isNotEmpty == true ? thread.title : '消息串',
      maxSize: 0.92,
      initialSize: 0.78,
      minSize: 0.45,
      contentPadding: EdgeInsets.zero,
      bodyBuilder: (ctx, scrollController) => ChatThreadSheet(
        channelId: channelId,
        thread: thread,
        originalMessage: originalMessage,
      ),
    );
  }

  @override
  ConsumerState<ChatThreadSheet> createState() => _ChatThreadSheetState();
}

class _ChatThreadSheetState extends ConsumerState<ChatThreadSheet> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  bool _isSending = false;
  bool _showEmojiPicker = false;

  @override
  void dispose() {
    _textController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  String? _avatarUrl(ChatUser? user) {
    if (user?.avatarTemplate == null) return null;
    return UrlHelper.resolveUrlWithCdn(
      user!.avatarTemplate!.replaceAll('{size}', '48'),
    );
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    try {
      await ref
          .read(chatMessagesProvider(widget.channelId).notifier)
          .sendThreadMessage(widget.thread.id, text);
      _textController.clear();
      ref.invalidate(
        chatThreadMessagesProvider((
          channelId: widget.channelId,
          threadId: widget.thread.id,
        )),
      );
      // 频道主列表也刷新，更新消息串预览
      unawaitedRefreshChannel();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void unawaitedRefreshChannel() {
    // fire-and-forget：刷新主列表以更新 thread preview
    ref
        .read(chatMessagesProvider(widget.channelId).notifier)
        .loadMessages(preferLatest: true)
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final params = (
      channelId: widget.channelId,
      threadId: widget.thread.id,
    );
    final messagesAsync = ref.watch(chatThreadMessagesProvider(params));
    final replyCount =
        widget.thread.preview?.replyCount ?? widget.thread.replyCount;

    return Column(
      children: [
        // 标题副信息
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.forum_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                replyCount > 0 ? '$replyCount 条回复' : '消息串',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: messagesAsync.when(
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
                      onPressed: () => ref.invalidate(
                        chatThreadMessagesProvider(params),
                      ),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
            data: (messages) {
              // 原消息置顶；串内消息升序
              final items = <ChatMessage>[];
              final om = widget.originalMessage;
              if (om != null) {
                items.add(om);
              }
              for (final m in messages) {
                if (om != null && m.id == om.id) continue;
                items.add(m);
              }

              if (items.isEmpty) {
                return Center(
                  child: Text(
                    '还没有回复，来发第一条吧',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final message = items[index];
                  final isOriginal =
                      om != null && message.id == om.id && index == 0;
                  return _ThreadMessageTile(
                    message: message,
                    avatarUrl: _avatarUrl(message.user),
                    theme: theme,
                    isOriginal: isOriginal,
                  );
                },
              );
            },
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '表情',
                      onPressed: () {
                        setState(() => _showEmojiPicker = !_showEmojiPicker);
                        if (_showEmojiPicker) {
                          _inputFocusNode.unfocus();
                        } else {
                          _inputFocusNode.requestFocus();
                        }
                      },
                      icon: Icon(
                        _showEmojiPicker
                            ? Icons.keyboard_alt_outlined
                            : Icons.emoji_emotions_outlined,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: _inputFocusNode,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        onTap: () {
                          if (_showEmojiPicker) {
                            setState(() => _showEmojiPicker = false);
                          }
                        },
                        decoration: const InputDecoration(
                          hintText: '回复消息串…',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton.filled(
                      onPressed: _isSending ? null : _send,
                      icon: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
              if (_showEmojiPicker)
                SizedBox(
                  height: 240,
                  child: EmojiStickerPanel(
                    onEmojiSelected: (emoji) {
                      final text = _textController.text;
                      final selection = _textController.selection;
                      final code = ':${emoji.name}: ';
                      if (selection.isValid) {
                        final start = selection.start;
                        final newText =
                            text.replaceRange(start, selection.end, code);
                        _textController.value = TextEditingValue(
                          text: newText,
                          selection: TextSelection.collapsed(
                            offset: start + code.length,
                          ),
                        );
                      } else {
                        _textController.text = '$text$code';
                      }
                    },
                    onStickerSelected: (_) {},
                    onBackspace: () {
                      final text = _textController.text;
                      if (text.isNotEmpty) {
                        _textController.text =
                            text.substring(0, text.length - 1);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThreadMessageTile extends StatelessWidget {
  final ChatMessage message;
  final String? avatarUrl;
  final ThemeData theme;
  final bool isOriginal;

  const _ThreadMessageTile({
    required this.message,
    required this.avatarUrl,
    required this.theme,
    required this.isOriginal,
  });

  @override
  Widget build(BuildContext context) {
    final username =
        message.user?.name ?? message.user?.username ?? '用户';
    final time = TimeUtils.formatCompactTime(message.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isOriginal
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: isOriginal
            ? Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.35),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SmartAvatar(
            imageUrl: avatarUrl,
            radius: 16,
            fallbackText: message.user?.username,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        username,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isOriginal) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '原消息',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      time,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SelectableEmojiText(
                  message.message,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
