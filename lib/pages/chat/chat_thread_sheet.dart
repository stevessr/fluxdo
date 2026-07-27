import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat/chat_models.dart';
import '../../providers/chat_providers.dart';
import '../../providers/core_providers.dart';
import '../../utils/fluxdo_render_callbacks.dart';
import '../../utils/time_utils.dart';
import '../../utils/url_helper.dart';
import '../../widgets/chat/online_status_avatar.dart';
import '../../widgets/common/app_bottom_sheet.dart';
import '../../widgets/common/cached_image.dart';
import '../../widgets/common/emoji_text.dart';
import '../../widgets/markdown_editor/emoji_sticker_panel.dart';
import '../image_viewer_page.dart';
import '../user_profile_page.dart';

/// 消息串底部面板：串内消息与主聊 UI 对齐（气泡 / cooked / 图片 / 反应）。
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
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  bool _showEmojiPicker = false;

  @override
  void dispose() {
    _textController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? _avatarUrl(ChatUser? user) {
    if (user?.avatarTemplate == null) return null;
    return UrlHelper.resolveUrlWithCdn(
      user!.avatarTemplate!.replaceAll('{size}', '40'),
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
      // 刷新主列表预览 + 消息串列表
      unawaitedRefresh();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void unawaitedRefresh() {
    ref
        .read(chatMessagesProvider(widget.channelId).notifier)
        .loadMessages(preferLatest: true)
        .catchError((_) {});
    ref.invalidate(chatChannelThreadsProvider(widget.channelId));
  }

  Future<void> _toggleReaction(ChatMessage message, String emoji) async {
    await ref
        .read(chatMessagesProvider(widget.channelId).notifier)
        .toggleReaction(message.id, emoji);
    ref.invalidate(
      chatThreadMessagesProvider((
        channelId: widget.channelId,
        threadId: widget.thread.id,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final params = (
      channelId: widget.channelId,
      threadId: widget.thread.id,
    );
    final messagesAsync = ref.watch(chatThreadMessagesProvider(params));
    final currentUser = ref.watch(currentUserProvider).value;
    final replyCount =
        widget.thread.preview?.replyCount ?? widget.thread.replyCount;

    return Column(
      children: [
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
              final items = <ChatMessage>[];
              final om = widget.originalMessage;
              if (om != null) items.add(om);
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
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final message = items[index];
                  final isOriginal =
                      om != null && message.id == om.id && index == 0;
                  final isOwn = currentUser != null &&
                      message.user != null &&
                      message.user!.id == currentUser.id;
                  return _ThreadChatBubble(
                    message: message,
                    avatarUrl: _avatarUrl(message.user),
                    theme: theme,
                    isOwnMessage: isOwn,
                    isOriginal: isOriginal,
                    onToggleReaction: (emoji) =>
                        _toggleReaction(message, emoji),
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

/// 与主聊天页对齐的消息串气泡
class _ThreadChatBubble extends StatelessWidget {
  final ChatMessage message;
  final String? avatarUrl;
  final ThemeData theme;
  final bool isOwnMessage;
  final bool isOriginal;
  final ValueChanged<String> onToggleReaction;

  const _ThreadChatBubble({
    required this.message,
    required this.avatarUrl,
    required this.theme,
    required this.isOwnMessage,
    required this.isOriginal,
    required this.onToggleReaction,
  });

  static final RegExp _uploadSha1 = RegExp(r'[0-9a-f]{40}');

  static bool _cookedRendersUrl(String cooked, String url) {
    if (cooked.isEmpty) return false;
    final sha = _uploadSha1.firstMatch(url)?.group(0);
    if (sha != null) return cooked.contains(sha);
    final path = Uri.tryParse(url)?.path ?? '';
    return path.isNotEmpty && cooked.contains(path);
  }

  List<String> _extractImageUrls() {
    final urls = <String>[];
    final seen = <String>{};

    bool isNonContentImage(String rawStr) {
      final lower = rawStr.toLowerCase();
      if (lower.contains('class="emoji"') ||
          lower.contains("class='emoji'") ||
          lower.contains('/images/emoji/') ||
          lower.contains('/emoji/')) {
        return true;
      }
      if (lower.contains('class="avatar"') ||
          lower.contains("class='avatar'") ||
          lower.contains('class="thumbnail"') ||
          lower.contains('class="site-icon"') ||
          lower.contains('class="favicon"') ||
          lower.contains('data-avatar')) {
        return true;
      }
      return false;
    }

    void addUrl(String? raw) {
      if (raw == null || raw.trim().isEmpty) return;
      final trimmed = raw.trim();
      if (trimmed.startsWith('upload://')) return;
      if (isNonContentImage(trimmed)) return;
      final resolved = UrlHelper.resolveUrlWithCdn(trimmed);
      if (resolved.isNotEmpty &&
          !isNonContentImage(resolved) &&
          seen.add(resolved)) {
        urls.add(resolved);
      }
    }

    if (message.uploads != null) {
      for (final u in message.uploads!) {
        final path = u['url'] as String? ??
            u['full_url'] as String? ??
            u['short_path'] as String?;
        addUrl(path);
      }
    }

    final mdRegex = RegExp(r'!\[.*?\]\((.*?)\)');
    for (final match in mdRegex.allMatches(message.message)) {
      final urlCandidate = match.group(1);
      if (urlCandidate != null) addUrl(urlCandidate.split(' ').first);
    }

    if (message.cooked != null && message.cooked!.isNotEmpty) {
      final imgRegex = RegExp(r'<img[^>]+>', caseSensitive: false);
      for (final match in imgRegex.allMatches(message.cooked!)) {
        final imgTag = match.group(0) ?? '';
        if (isNonContentImage(imgTag)) continue;
        final srcMatch =
            RegExp('src=["\']([^"\']+)["\']', caseSensitive: false)
                .firstMatch(imgTag);
        if (srcMatch != null) addUrl(srcMatch.group(1));
      }
    }

    return urls;
  }

  @override
  Widget build(BuildContext context) {
    final alignment =
        isOwnMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final showSender = !isOwnMessage && message.user != null;
    final imageUrls = _extractImageUrls();
    final cookedHtml = message.cooked ?? '';
    final thumbnailUrls = cookedHtml.isEmpty
        ? imageUrls
        : imageUrls.where((u) => !_cookedRendersUrl(cookedHtml, u)).toList();

    String displayText = message.message;
    for (final url in imageUrls) {
      displayText = displayText.replaceAll(
        RegExp('!\\[.*?\\]\\(${RegExp.escape(url)}\\)'),
        '',
      );
    }
    displayText = displayText
        .replaceAll(RegExp(r'!\[.*?\]\(upload://[^\)]+\)'), '')
        .trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          if (isOriginal)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.push_pin_outlined,
                    size: 12,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '原消息',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (showSender)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 4),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UserProfilePage(
                            username: message.user!.username,
                          ),
                        ),
                      );
                    },
                    child: OnlineStatusAvatar(
                      userId: message.user!.id,
                      imageUrl: avatarUrl,
                      radius: 16,
                      fallbackText: message.user!.username,
                    ),
                  ),
                ),
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: alignment,
                  children: [
                    if (showSender)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 2),
                        child: Text(
                          message.user!.name ?? message.user!.username,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
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
                        border: isOriginal
                            ? Border.all(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.35),
                              )
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (thumbnailUrls.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children:
                                    thumbnailUrls.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final url = entry.value;
                                  return GestureDetector(
                                    onTap: () {
                                      ImageViewerPage.open(
                                        context,
                                        url,
                                        galleryImages: thumbnailUrls,
                                        initialIndex: idx,
                                        enableShare: true,
                                      );
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: CachedImage(
                                        url: url,
                                        width: 180,
                                        height: 120,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          if (message.cooked != null &&
                              message.cooked!.isNotEmpty)
                            FluxdoRenderCallbacks.generic(
                              heroTagNamespace:
                                  'chat_thread_msg_${message.id}',
                            ).render(
                              cookedHtml: message.cooked!,
                              baseTextStyle:
                                  theme.textTheme.bodyMedium?.copyWith(
                                color: isOwnMessage
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onSurface,
                              ),
                              selectionEnabled: true,
                              compact: true,
                              trimTopMargin: true,
                              trimBottomMargin: true,
                              stretchBlocks: false,
                            )
                          else if (displayText.isNotEmpty)
                            SelectableEmojiText(
                              displayText,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isOwnMessage
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          const SizedBox(height: 2),
                          Text(
                            TimeUtils.formatCompactTime(message.createdAt),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: (isOwnMessage
                                      ? theme.colorScheme.onPrimaryContainer
                                      : theme.colorScheme.onSurfaceVariant)
                                  .withValues(alpha: 0.6),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (message.reactions != null &&
                        message.reactions!.isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.only(top: 4, left: 4, right: 4),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: message.reactions!.map((r) {
                            final isReacted = r.reacted;
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => onToggleReaction(r.emoji),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isReacted
                                        ? theme.colorScheme.primaryContainer
                                        : theme.colorScheme.surface,
                                    border: Border.all(
                                      color: isReacted
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.outlineVariant
                                              .withValues(alpha: 0.5),
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      EmojiText(
                                        ':${r.emoji}:',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${r.count}',
                                        style:
                                            theme.textTheme.labelSmall?.copyWith(
                                          fontSize: 10,
                                          fontWeight: isReacted
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: isReacted
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme
                                                  .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
