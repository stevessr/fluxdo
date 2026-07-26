import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/s.dart';
import '../../models/chat/chat_models.dart';
import '../../models/emoji.dart';
import '../../models/topic.dart' show FlagType;
import '../../models/user.dart';
import '../../providers/chat_providers.dart';
import '../../providers/core_providers.dart';
import '../../services/discourse/discourse_service.dart';
import '../../services/preloaded_data_service.dart';
import '../../utils/fluxdo_render_callbacks.dart';
import '../../utils/time_utils.dart';
import '../../utils/url_helper.dart';
import '../../widgets/common/cached_image.dart';
import '../../widgets/common/emoji_text.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/smart_avatar.dart';
import '../../widgets/chat/online_status_avatar.dart';
import '../../widgets/markdown_editor/emoji_sticker_panel.dart';
import '../image_viewer_page.dart';
import '../user_profile_page.dart';
import 'chat_channel_members_sheet.dart';
import 'chat_channel_settings_sheet.dart';

/// Chat 消息页面
///
/// 展示指定频道的聊天消息，支持发送、回复、编辑、删除、图片上传及提到用户。
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

  // 上下文状态：回复/编辑/附件/mention
  ChatMessage? _replyToMessage;
  ChatMessage? _editingMessage;
  List<int> _uploadIds = [];
  String? _uploadPreviewPath;
  bool _isUploadingImage = false;

  List<Chatable> _mentionSuggestions = [];
  bool _showMentionSuggestions = false;
  bool _showEmojiPicker = false;

  // 多选消息模式状态
  bool _isMultiSelectMode = false;
  final Set<int> _selectedMessageIds = {};

  // 频道内搜索
  bool _isSearchMode = false;
  final TextEditingController _searchController = TextEditingController();
  List<ChatMessage> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;

  void _enterMultiSelectMode([int? initialMessageId]) {
    setState(() {
      _isMultiSelectMode = true;
      _selectedMessageIds.clear();
      if (initialMessageId != null) {
        _selectedMessageIds.add(initialMessageId);
      }
    });
  }

  void _exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedMessageIds.clear();
    });
  }

  void _toggleSelectMessage(int messageId) {
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  void _onCopyShareLink(ChatMessage message) {
    final baseUrl = DiscourseService.baseUrl;
    final shareUrl = '$baseUrl/chat/channel/${widget.channelId}?message_id=${message.id}';
    Clipboard.setData(ClipboardData(text: shareUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制分享链接到剪贴板')),
    );
  }

  void _copySelectedMessages(List<ChatMessage> allMessages) {
    if (_selectedMessageIds.isEmpty) return;
    final selectedMsgs = allMessages.where((m) => _selectedMessageIds.contains(m.id)).toList();
    selectedMsgs.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final buffer = StringBuffer();
    for (final m in selectedMsgs) {
      final username = m.user?.name ?? m.user?.username ?? '用户';
      final timeStr = TimeUtils.formatCompactTime(m.createdAt);
      buffer.writeln('[$timeStr] $username: ${m.message}');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 ${_selectedMessageIds.length} 条消息到剪贴板')),
    );
  }

  /// 将选中消息生成 Discourse 引用 Markdown（对齐官方 quote）
  Future<void> _quoteSelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;
    final ids = _selectedMessageIds.toList()..sort();
    try {
      final markdown = await ref
          .read(chatMessagesProvider(widget.channelId).notifier)
          .quoteMessages(ids);
      if (!mounted) return;
      if (markdown.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('生成引用失败：返回为空')),
        );
        return;
      }
      await Clipboard.setData(ClipboardData(text: markdown));
      if (!mounted) return;
      _exitMultiSelectMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制 ${ids.length} 条消息的引用 Markdown')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成引用失败: $e')),
      );
    }
  }

  bool get _pinEnabled {
    final settings = PreloadedDataService().siteSettingsSync;
    return settings?['chat_pinned_messages'] == true;
  }

  Future<void> _togglePinMessage(ChatMessage message) async {
    try {
      await ref
          .read(chatMessagesProvider(widget.channelId).notifier)
          .togglePin(message.id, pin: !message.pinned);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message.pinned ? '已取消置顶' : '已置顶消息')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('置顶操作失败: $e')),
      );
    }
  }

  Future<void> _restoreMessage(ChatMessage message) async {
    try {
      await ref
          .read(chatMessagesProvider(widget.channelId).notifier)
          .restoreMessage(message.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已恢复消息')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('恢复失败: $e')),
      );
    }
  }

  Future<void> _showFlagSheet(ChatMessage message) async {
    final username = message.user?.username ?? '用户';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ChatMessageFlagSheet(
        channelId: widget.channelId,
        messageId: message.id,
        username: username,
        availableFlagKeys: message.availableFlags,
      ),
    );
    _exitMultiSelectMode();
  }

  void _onEmojiSelected(Emoji emoji) {
    final text = _textController.text;
    final selection = _textController.selection;
    final emojiCode = ':${emoji.name}: ';
    if (selection.isValid && selection.isCollapsed) {
      final start = selection.start;
      final newText = text.replaceRange(start, selection.end, emojiCode);
      _textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start + emojiCode.length),
      );
    } else {
      _textController.text = '$text$emojiCode';
    }
  }

  void _onStickerSelected(String stickerMarkdown) {
    _textController.text = '${_textController.text} $stickerMarkdown'.trim();
  }

  void _onEmojiBackspace() {
    final text = _textController.text;
    if (text.isNotEmpty) {
      _textController.text = text.substring(0, text.length - 1);
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _textController.addListener(_onTextChanged);
    // 上报用户进入聊天（用于在线状态追踪）
    _reportPresence();
  }

  void _reportPresence() {
    final discourse = ref.read(discourseServiceProvider);
    discourse.chat.reportChatPresence(widget.channelId).catchError((_) {
      // 静默失败，不影响主流程
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _searchController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _enterSearchMode() {
    setState(() {
      _isSearchMode = true;
      _isMultiSelectMode = false;
      _searchResults = [];
      _searchError = null;
    });
  }

  void _exitSearchMode() {
    setState(() {
      _isSearchMode = false;
      _searchController.clear();
      _searchResults = [];
      _isSearching = false;
      _searchError = null;
    });
  }

  Future<void> _runChannelSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _searchError = null;
        _isSearching = false;
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _searchError = null;
    });
    try {
      final result = await ref.read(
        chatChannelSearchProvider((
          channelId: widget.channelId,
          query: q,
        )).future,
      );
      if (!mounted) return;
      setState(() {
        _searchResults = result.messages;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = e.toString();
        _searchResults = [];
      });
    }
  }

  Future<void> _jumpToSearchResult(ChatMessage message) async {
    _exitSearchMode();
    try {
      await ref
          .read(chatMessagesProvider(widget.channelId).notifier)
          .jumpToMessage(message.id);
      if (!mounted) return;
      // reverse 列表：index 0 = 最新；按「距最新的距离」粗略定位
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final messages =
            ref.read(chatMessagesProvider(widget.channelId)).value ?? [];
        final idx = messages.indexWhere((m) => m.id == message.id);
        if (idx < 0) {
          _scrollToBottom();
          return;
        }
        final max = _scrollController.position.maxScrollExtent;
        // ASC 列表中 idx 越大越新；reverse 下距底部比例 ≈ 1 - (idx+1)/n
        final ratio = messages.length <= 1
            ? 0.0
            : 1.0 - ((idx + 1) / messages.length);
        _scrollController.animateTo(
          (max * ratio).clamp(0.0, max),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('定位消息失败: $e')),
      );
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    // reverse ListView：pixels≈0 为视觉底部（最新消息）
    final atBottom = currentScroll <= 100;
    if (atBottom != _isAtBottom) {
      setState(() => _isAtBottom = atBottom);
    }

    // reverse 列表顶部（历史方向）靠近 maxScrollExtent
    if (maxScroll > 0 && currentScroll >= maxScroll - 240) {
      _loadMoreMessages();
    }
  }

  void _scrollToBottom({bool animate = true}) {
    void jump() {
      if (!_scrollController.hasClients) return;
      // reverse ListView 底部即 minScrollExtent（通常为 0）
      const target = 0.0;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    }

    // 首屏布局未完成时多帧重试，确保落在最新消息
    WidgetsBinding.instance.addPostFrameCallback((_) {
      jump();
      WidgetsBinding.instance.addPostFrameCallback((_) => jump());
    });
  }

  /// 对齐 Discourse scrollToLatestMessage：
  /// 若仍有 future / 中窗会话，先重拉最新再贴底，避免只在已加载窗口内假「到底」。
  Future<void> _scrollToLatest() async {
    final notifier = ref.read(chatMessagesProvider(widget.channelId).notifier);
    if (notifier.canLoadMoreFuture || notifier.targetMessageId != null) {
      await notifier.scrollToLatest();
      if (!mounted) return;
    }
    _scrollToBottom(animate: true);
    final messages =
        ref.read(chatMessagesProvider(widget.channelId)).asData?.value;
    if (messages != null) _markAsRead(messages);
  }

  Future<void> _loadMoreMessages() async {
    final notifier = ref.read(chatMessagesProvider(widget.channelId).notifier);
    if (!notifier.canLoadMorePast || notifier.isLoadingMore) return;

    // reverse ListView 在 trailing 端插入更旧消息时，会增大 maxScrollExtent，
    // 同时保持相对底部的 pixels，无需额外锚点补偿。
    await notifier.loadMore();
  }

  /// 监听输入框变化，触发 @ 用户联想
  void _onTextChanged() {
    final text = _textController.text;
    final selection = _textController.selection;
    if (!selection.isValid || selection.isCollapsed == false) {
      if (_showMentionSuggestions) {
        setState(() => _showMentionSuggestions = false);
      }
      return;
    }

    final cursorPosition = selection.baseOffset;
    if (cursorPosition <= 0) {
      if (_showMentionSuggestions) {
        setState(() => _showMentionSuggestions = false);
      }
      return;
    }

    final textBeforeCursor = text.substring(0, cursorPosition);
    final lastAtIndex = textBeforeCursor.lastIndexOf('@');

    if (lastAtIndex >= 0 && (lastAtIndex == 0 || textBeforeCursor[lastAtIndex - 1] == ' ')) {
      final filter = textBeforeCursor.substring(lastAtIndex + 1);
      if (!filter.contains(' ')) {
        _fetchMentionSuggestions(filter);
        return;
      }
    }

    if (_showMentionSuggestions) {
      setState(() => _showMentionSuggestions = false);
    }
  }

  Future<void> _fetchMentionSuggestions(String filter) async {
    try {
      final suggestions = await ref.read(chatSearchProvider(filter).future);
      if (!mounted) return;
      setState(() {
        _mentionSuggestions = suggestions;
        _showMentionSuggestions = suggestions.isNotEmpty;
      });
    } catch (_) {
      if (mounted && _showMentionSuggestions) {
        setState(() => _showMentionSuggestions = false);
      }
    }
  }

  void _insertMention(Chatable user) {
    final text = _textController.text;
    final selection = _textController.selection;
    final cursorPosition = selection.baseOffset;
    final textBeforeCursor = text.substring(0, cursorPosition);
    final lastAtIndex = textBeforeCursor.lastIndexOf('@');

    if (lastAtIndex >= 0) {
      final newText = text.substring(0, lastAtIndex) + '@${user.username} ' + text.substring(cursorPosition);
      _textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: lastAtIndex + user.username.length + 2),
      );
    }
    setState(() => _showMentionSuggestions = false);
  }

  /// 选择并上传图片附件
  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() {
      _isUploadingImage = true;
      _uploadPreviewPath = pickedFile.path;
    });

    try {
      final service = ref.read(discourseServiceProvider);
      final uploadResult = await service.uploadFile(pickedFile.path);
      if (!mounted) return;
      setState(() {
        _uploadIds.add(uploadResult.id);
        _isUploadingImage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploadingImage = false;
        _uploadPreviewPath = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.chat_upload_failed(e.toString()))),
      );
    }
  }

  /// 清除附件
  void _clearUpload() {
    setState(() {
      _uploadIds.clear();
      _uploadPreviewPath = null;
    });
  }

  /// 发送或更新消息
  Future<void> _sendMessageOrUpdate() async {
    final text = _textController.text.trim();
    if ((text.isEmpty && _uploadIds.isEmpty) || _isSending || _isUploadingImage) return;

    setState(() => _isSending = true);
    try {
      final notifier = ref.read(chatMessagesProvider(widget.channelId).notifier);
      if (_editingMessage != null) {
        await notifier.editMessage(_editingMessage!.id, text);
      } else {
        await notifier.sendMessage(
          text,
          inReplyToId: _replyToMessage?.id,
          uploadIds: _uploadIds.isNotEmpty ? _uploadIds : null,
        );
      }

      _textController.clear();
      _onCancelReplyOrEdit();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e) {
      if (!mounted) return;
      final msg = _editingMessage != null
          ? context.l10n.chat_update_failed(e.toString())
          : context.l10n.chat_send_failed(e.toString());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _onStartReply(ChatMessage message) {
    setState(() {
      _replyToMessage = message;
      _editingMessage = null;
    });
    _inputFocusNode.requestFocus();
  }

  void _onStartEdit(ChatMessage message) {
    setState(() {
      _editingMessage = message;
      _replyToMessage = null;
      _textController.text = message.message;
    });
    _inputFocusNode.requestFocus();
  }

  void _onCancelReplyOrEdit() {
    setState(() {
      _replyToMessage = null;
      _editingMessage = null;
      _uploadIds.clear();
      _uploadPreviewPath = null;
      _showMentionSuggestions = false;
    });
  }

  Future<void> _onDeleteMessage(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.chat_delete),
        content: Text(ctx.l10n.chat_delete_confirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.chat_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(ctx.l10n.chat_delete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final notifier = ref.read(chatMessagesProvider(widget.channelId).notifier);
      await notifier.deleteMessage(message.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.chat_delete_failed(e.toString()))),
      );
    }
  }

  void _onCopyMessage(ChatMessage message) {
    Clipboard.setData(ClipboardData(text: message.message));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.chat_copied),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 最近使用的反应表情 SharedPreferences key
  static const String _recentReactionEmojisKey = 'recent_reaction_emojis';

  /// 记录最近使用的反应表情
  Future<void> _saveRecentReactionEmoji(String emojiName) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_recentReactionEmojisKey) ?? [];
    list.remove(emojiName);
    list.insert(0, emojiName);
    // 最多保留 30 个
    final trimmed = list.length > 30 ? list.sublist(0, 30) : list;
    await prefs.setStringList(_recentReactionEmojisKey, trimmed);
  }

  /// 加载最近使用的反应表情
  Future<List<String>> _loadRecentReactionEmojis() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentReactionEmojisKey) ?? [];
  }

  /// 打开完整表情选择器用于反应
  void _showFullEmojiPickerForReaction(ChatMessage message) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.45,
        child: EmojiStickerPanel(
          onEmojiSelected: (emoji) {
            Navigator.pop(ctx);
            _saveRecentReactionEmoji(emoji.name);
            ref
                .read(chatMessagesProvider(widget.channelId).notifier)
                .toggleReaction(message.id, emoji.name);
          },
          onStickerSelected: (_) {},
          onBackspace: null,
        ),
      ),
    );
  }

  /// 长按弹出消息操作 BottomSheet
  void _showMessageActionSheet(ChatMessage message, bool isOwnMessage) {
    // 已删除消息：仅提供恢复（若服务端仍返回该消息，通常需有审核权限）
    if (message.deleted) {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.restore_rounded),
                title: const Text('恢复消息'),
                onTap: () {
                  Navigator.pop(ctx);
                  _restoreMessage(message);
                },
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: Text(ctx.l10n.chat_cancel),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      );
      return;
    }

    final currentUser = ref.read(currentUserProvider).value;
    final canFlag = !isOwnMessage &&
        (message.availableFlags == null || message.availableFlags!.isNotEmpty);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 快捷 Emoji 回应工具栏
              FutureBuilder<List<String>>(
                future: _loadRecentReactionEmojis(),
                builder: (ctx, snapshot) {
                  final recentEmojis = snapshot.data ?? [];
                  final availableWidth = MediaQuery.of(ctx).size.width - 32 - 46;
                  final maxCount =
                      (availableWidth / 46).floor().clamp(0, recentEmojis.length);
                  final displayEmojis = recentEmojis.take(maxCount).toList();

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: displayEmojis.map((emoji) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _saveRecentReactionEmoji(emoji);
                                      ref
                                          .read(chatMessagesProvider(
                                                  widget.channelId)
                                              .notifier)
                                          .toggleReaction(message.id, emoji);
                                    },
                                    borderRadius: BorderRadius.circular(24),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Theme.of(ctx)
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.7),
                                        shape: BoxShape.circle,
                                      ),
                                      child: EmojiText(
                                        ':$emoji:',
                                        style: const TextStyle(fontSize: 22),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              _showFullEmojiPickerForReaction(message);
                            },
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(ctx)
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: 0.7),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.add_rounded,
                                size: 22,
                                color: Theme.of(ctx)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(ctx.l10n.chat_reply),
                onTap: () {
                  Navigator.pop(ctx);
                  _onStartReply(message);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(ctx.l10n.chat_copy),
                onTap: () {
                  Navigator.pop(ctx);
                  _onCopyMessage(message);
                },
              ),
              ListTile(
                leading: const Icon(Icons.link_rounded),
                title: const Text('复制分享链接'),
                onTap: () {
                  Navigator.pop(ctx);
                  _onCopyShareLink(message);
                },
              ),
              ListTile(
                leading: Icon(
                  message.bookmarked
                      ? Icons.bookmark_remove_rounded
                      : Icons.bookmark_add_outlined,
                  color: message.bookmarked
                      ? Theme.of(ctx).colorScheme.primary
                      : null,
                ),
                title: Text(message.bookmarked ? '取消书签' : '设为书签'),
                onTap: () {
                  Navigator.pop(ctx);
                  ref
                      .read(chatMessagesProvider(widget.channelId).notifier)
                      .toggleBookmark(message.id);
                },
              ),
              if (_pinEnabled)
                ListTile(
                  leading: Icon(
                    message.pinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    color: message.pinned
                        ? Theme.of(ctx).colorScheme.primary
                        : null,
                  ),
                  title: Text(message.pinned ? '取消置顶' : '置顶消息'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _togglePinMessage(message);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.checklist_rounded),
                title: const Text('多选消息'),
                onTap: () {
                  Navigator.pop(ctx);
                  _enterMultiSelectMode(message.id);
                },
              ),
              if (canFlag)
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('举报'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showFlagSheet(message);
                  },
                ),
              if (isOwnMessage || (currentUser?.isStaff ?? false)) ...[
                if (isOwnMessage)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: Text(ctx.l10n.chat_edit),
                    onTap: () {
                      Navigator.pop(ctx);
                      _onStartEdit(message);
                    },
                  ),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: Theme.of(ctx).colorScheme.error,
                  ),
                  title: Text(
                    ctx.l10n.chat_delete,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _onDeleteMessage(message);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 标记已读
  void _markAsRead(List<ChatMessage> messages) {
    if (messages.isEmpty) return;
    final lastMessage = messages.last;
    final notifier = ref.read(chatMessagesProvider(widget.channelId).notifier);
    notifier.markAsRead(lastMessage.id);
  }

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

    ref.listen(chatMessagesProvider(widget.channelId), (prev, next) {
      next.whenData((messages) {
        if (!_initialLoadDone && messages.isNotEmpty) {
          _initialLoadDone = true;
          // reverse 列表默认已在底部；仍 jump 一次以对齐布局
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom(animate: false);
            _markAsRead(messages);
          });
          return;
        }
        // 自己发送/底部时跟随新消息（reverse 下贴 minScrollExtent）
        final prevLen = prev?.value?.length ?? 0;
        if (_isAtBottom && messages.length > prevLen) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom(animate: true);
            _markAsRead(messages);
          });
        }
      });
    });

    // provider 非 autoDispose：缓存已有数据时 ref.listen 不会再触发首屏回调，
    // 这里补一次，避免重进频道停在错误位置或看起来像空白。
    final cachedMessages = messagesAsync.asData?.value;
    if (!_initialLoadDone &&
        cachedMessages != null &&
        cachedMessages.isNotEmpty) {
      _initialLoadDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom(animate: false);
        _markAsRead(cachedMessages);
      });
    }

    final channelsAsync = ref.watch(chatChannelsProvider);
    ChatChannel? currentChannel;
    if (channelsAsync.value != null) {
      final all = [
        ...channelsAsync.value!.publicChannels,
        ...channelsAsync.value!.directMessageChannels,
      ];
      try {
        currentChannel = all.firstWhere((c) => c.id == widget.channelId);
      } catch (_) {}
    }

    return Scaffold(
      appBar: _isSearchMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _exitSearchMode,
              ),
              title: TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: '搜索此对话中的消息',
                  border: InputBorder.none,
                ),
                onSubmitted: _runChannelSearch,
              ),
              actions: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchResults = [];
                        _searchError = null;
                      });
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.search_rounded),
                  tooltip: '搜索',
                  onPressed: () => _runChannelSearch(_searchController.text),
                ),
              ],
            )
          : _isMultiSelectMode
              ? AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _exitMultiSelectMode,
                  ),
                  title: Text('已选择 ${_selectedMessageIds.length} 条'),
                  actions: [
                    TextButton(
                      onPressed: () {
                        final msgs = messagesAsync.value ?? [];
                        setState(() {
                          _selectedMessageIds.addAll(msgs.map((m) => m.id));
                        });
                      },
                      child: const Text('全选'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.format_quote_rounded),
                      tooltip: '引用选中消息',
                      onPressed: _selectedMessageIds.isEmpty
                          ? null
                          : _quoteSelectedMessages,
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded),
                      tooltip: '复制选中消息',
                      onPressed: () =>
                          _copySelectedMessages(messagesAsync.value ?? []),
                    ),
                  ],
                )
              : AppBar(
                  title: Text(widget.channelTitle),
                  actions: [
                    // 收藏（与频道列表/设置页共用 chatFavoritesProvider）
                    Builder(
                      builder: (context) {
                        final isFavorite = ref
                            .watch(chatFavoritesProvider)
                            .contains(widget.channelId);
                        return IconButton(
                          icon: Icon(
                            isFavorite
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: isFavorite ? Colors.amber : null,
                          ),
                          tooltip: isFavorite ? '取消收藏' : '收藏频道',
                          onPressed: () {
                            ref
                                .read(chatFavoritesProvider.notifier)
                                .toggleFavorite(widget.channelId);
                          },
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.search_rounded),
                      tooltip: '搜索对话',
                      onPressed: _enterSearchMode,
                    ),
                    if (!_isAtBottom && messagesAsync.value != null)
                      IconButton(
                        icon: const Icon(Icons.arrow_downward_rounded),
                        tooltip: context.l10n.chat_scroll_to_bottom,
                        onPressed: _scrollToLatest,
                      ),
                    IconButton(
                      icon: const Icon(Icons.people_outline_rounded),
                      tooltip: context.l10n.chat_channel_members,
                      onPressed: () {
                        final settings =
                            PreloadedDataService().siteSettingsSync;
                        final rawLimit =
                            settings?['chat_max_direct_message_users'];
                        final dmLimit = currentChannel?.isDirectMessage == true
                            ? (rawLimit is num
                                ? rawLimit.toInt()
                                : int.tryParse('$rawLimit'))
                            : null;
                        ChatChannelMembersSheet.show(
                          context,
                          widget.channelId,
                          widget.channelTitle,
                          canAddMembers:
                              currentChannel?.canAddMembers ?? false,
                          membersCountHint: currentChannel?.membersCount,
                          membersLimit: dmLimit,
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.tune_rounded),
                      tooltip: '频道设置',
                      onPressed: () {
                        ChatChannelSettingsSheet.show(
                          context,
                          widget.channelId,
                          widget.channelTitle,
                        );
                      },
                    ),
                  ],
                ),
      body: Column(
        children: [
          if (_isSearchMode)
            Expanded(child: _buildSearchPanel(theme))
          else ...[
            // 消息列表
            Expanded(
              child: messagesAsync.when(
                // 刷新时保留旧列表，避免发送/重载把消息区刷成空白转圈
                skipLoadingOnReload: true,
                data: (messages) {
                  if (messages.isEmpty) {
                    return _buildEmptyState(theme);
                  }

                  return NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.axis != Axis.vertical) {
                        return false;
                      }
                      final metrics = notification.metrics;
                      // reverse：靠近 maxScrollExtent = 更旧历史
                      if (metrics.maxScrollExtent > 0 &&
                          metrics.pixels >= metrics.maxScrollExtent - 300) {
                        _loadMoreMessages();
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scrollController,
                      // reverse：index 0 贴在视觉底部 = 最新消息，
                      // 首屏无需再等 jump，从根上消除「数据在但屏幕空白」。
                      reverse: true,
                      scrollCacheExtent:
                          const ScrollCacheExtent.pixels(800),
                      // reverse 会翻转 padding：top 落在视觉底部（靠近输入框）
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      // +1：最旧一侧的「加载更多」指示器
                      itemCount: messages.length + 1,
                      itemBuilder: (context, index) {
                        // reverse 下最大 index 在视觉顶部
                        if (index == messages.length) {
                          return _buildLoadMoreIndicator();
                        }

                        // messages 仍为时间升序；reverse 映射最新到 index 0
                        final messageIndex = messages.length - 1 - index;
                        final message = messages[messageIndex];
                        final isOwnMessage = currentUser != null &&
                            message.user != null &&
                            message.user!.id == currentUser.id;

                        // 日期分割：相对时间序上一条（更旧）
                        bool showDateHeader = false;
                        if (messageIndex == 0) {
                          showDateHeader = true;
                        } else {
                          final prevMessage = messages[messageIndex - 1];
                          showDateHeader = !_isSameDay(
                            message.createdAt,
                            prevMessage.createdAt,
                          );
                        }

                        // 查找关联回复消息
                        ChatMessage? replyToMsg;
                        if (message.inReplyToId != null) {
                          replyToMsg = messages.firstWhere(
                            (m) => m.id == message.inReplyToId,
                            orElse: () => message,
                          );
                          if (replyToMsg.id == message.id) {
                            replyToMsg = null;
                          }
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (showDateHeader)
                              _buildDateHeader(theme, message.createdAt),
                            _ChatMessageBubble(
                              message: message,
                              replyToMessage: replyToMsg,
                              isOwnMessage: isOwnMessage,
                              avatarUrl: _buildAvatarUrl(message.user),
                              theme: theme,
                              isMultiSelectMode: _isMultiSelectMode,
                              isSelected:
                                  _selectedMessageIds.contains(message.id),
                              onToggleSelect: (id) =>
                                  _toggleSelectMessage(id),
                              onLongPress: () => _showMessageActionSheet(
                                message,
                                isOwnMessage,
                              ),
                              onRestore: message.deleted
                                  ? () => _restoreMessage(message)
                                  : null,
                              onToggleReaction: (emoji) {
                                ref
                                    .read(chatMessagesProvider(
                                            widget.channelId)
                                        .notifier)
                                    .toggleReaction(message.id, emoji);
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, stack) => ErrorView(
                  error: error,
                  stackTrace: stack,
                  onRetry: () {
                    ref.invalidate(chatMessagesProvider(widget.channelId));
                  },
                ),
              ),
            ),
            // 输入区域（含回复/编辑/图片预览/联想菜单）
            _buildInputArea(theme, currentChannel, currentUser),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchPanel(ThemeData theme) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(height: 8),
              Text('搜索失败: $_searchError', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _runChannelSearch(_searchController.text),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_searchController.text.trim().isEmpty) {
      return Center(
        child: Text(
          '输入关键词搜索此对话中的消息',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          '未找到匹配消息',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _searchResults.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final message = _searchResults[index];
        final username = message.user?.name ??
            message.user?.username ??
            '用户';
        final preview = message.message.isNotEmpty
            ? message.message
            : (message.cooked?.replaceAll(RegExp(r'<[^>]*>'), '') ?? '');
        return ListTile(
          leading: OnlineStatusAvatar(
            userId: message.user?.id,
            imageUrl: _buildAvatarUrl(message.user),
            radius: 18,
            fallbackText: username,
          ),
          title: Text(
            username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            TimeUtils.formatCompactTime(message.createdAt),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          onTap: () => _jumpToSearchResult(message),
        );
      },
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildDateHeader(ThemeData theme, DateTime date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            TimeUtils.formatShortDate(date),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadMoreIndicator() {
    final notifier = ref.read(chatMessagesProvider(widget.channelId).notifier);
    if (notifier.isLoadMoreFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: TextButton.icon(
            onPressed: () => notifier.retryLoadMore(),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('加载历史消息失败，点击重试'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
      );
    }

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
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton.icon(
                onPressed: _loadMoreMessages,
                icon: const Icon(Icons.expand_less_rounded, size: 18),
                label: Text(context.l10n.chat_load_more),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
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

  Widget _buildInputArea(
    ThemeData theme,
    ChatChannel? channel,
    User? currentUser,
  ) {
    final isStaff = currentUser?.isStaff ?? false;
    final userSilenced = currentUser?.isSilenced ?? false;
    final canSend = channel?.canSendMessages(
          isStaff: isStaff,
          userSilenced: userSilenced,
        ) ??
        true;
    final disabledReason = channel?.sendDisabledReason(
          isStaff: isStaff,
          userSilenced: userSilenced,
        ) ??
        '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // @ 联想弹窗
        if (_showMentionSuggestions && canSend) _buildMentionSuggestions(theme),

        Container(
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!canSend)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            disabledReason,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 回复 / 编辑提示条
                if (canSend &&
                    (_replyToMessage != null || _editingMessage != null))
                  _buildContextBanner(theme),

                // 图片附件预览
                if (canSend && _uploadPreviewPath != null)
                  _buildUploadPreview(theme),

                // 输入框与操作按钮
                if (canSend)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // 图片附件上传按钮
                      IconButton(
                        onPressed: _isUploadingImage ? null : _pickAndUploadImage,
                        icon: const Icon(Icons.add_photo_alternate_rounded),
                        color: theme.colorScheme.onSurfaceVariant,
                        tooltip: context.l10n.chat_upload_image,
                      ),
                      // 表情与贴纸切换按钮
                      IconButton(
                        onPressed: () {
                          if (_showEmojiPicker) {
                            setState(() => _showEmojiPicker = false);
                            _inputFocusNode.requestFocus();
                          } else {
                            _inputFocusNode.unfocus();
                            setState(() => _showEmojiPicker = true);
                          }
                        },
                        icon: Icon(
                          _showEmojiPicker
                              ? Icons.keyboard_rounded
                              : Icons.sentiment_satisfied_alt_rounded,
                        ),
                        color: _showEmojiPicker
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        tooltip: '表情与贴纸',
                      ),
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          focusNode: _inputFocusNode,
                          textInputAction: TextInputAction.send,
                          maxLines: 5,
                          minLines: 1,
                          onTap: () {
                            if (_showEmojiPicker) {
                              setState(() => _showEmojiPicker = false);
                            }
                          },
                          onSubmitted: (_) => _sendMessageOrUpdate(),
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
                        onPressed: (_isSending || _isUploadingImage)
                            ? null
                            : _sendMessageOrUpdate,
                        icon: _isSending
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.primary,
                                ),
                              )
                            : Icon(
                                _editingMessage != null
                                    ? Icons.check_rounded
                                    : Icons.send_rounded,
                              ),
                        color: theme.colorScheme.primary,
                        tooltip: context.l10n.chat_send,
                      ),
                    ],
                  ),
                ),

                // 表情 / 表情包面板
                if (canSend && _showEmojiPicker)
                  SizedBox(
                    height: 280,
                    child: EmojiStickerPanel(
                      onEmojiSelected: _onEmojiSelected,
                      onStickerSelected: _onStickerSelected,
                      onBackspace: _onEmojiBackspace,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContextBanner(ThemeData theme) {
    final isEditing = _editingMessage != null;
    final title = isEditing
        ? context.l10n.chat_editing_message
        : context.l10n.chat_replying_to(
            _replyToMessage?.user?.name ??
                _replyToMessage?.user?.username ??
                '',
          );
    final subtitle = isEditing
        ? _editingMessage!.message
        : _replyToMessage?.message ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(
        children: [
          Icon(
            isEditing ? Icons.edit_outlined : Icons.reply_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: _onCancelReplyOrEdit,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadPreview(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(8),
      alignment: Alignment.centerLeft,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(_uploadPreviewPath!),
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
          if (_isUploadingImage)
            Positioned.fill(
              child: Container(
                color: Colors.black38,
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: _clearUpload,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMentionSuggestions(ThemeData theme) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _mentionSuggestions.length,
        itemBuilder: (context, index) {
          final user = _mentionSuggestions[index];
          final avatarUrl = _buildAvatarUrl(
            ChatUser(
              id: user.id,
              username: user.username,
              avatarTemplate: user.avatarTemplate,
            ),
          );

          return ListTile(
            dense: true,
            leading: OnlineStatusAvatar(
              userId: user.id,
              imageUrl: avatarUrl,
              radius: 12,
              fallbackText: user.username,
            ),
            title: Text('@${user.username}'),
            subtitle: user.name != null ? Text(user.name!) : null,
            onTap: () => _insertMention(user),
          );
        },
      ),
    );
  }
}

/// 单条 Chat 消息气泡组件
class _ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final ChatMessage? replyToMessage;
  final bool isOwnMessage;
  final String? avatarUrl;
  final ThemeData theme;
  final VoidCallback onLongPress;
  final ValueChanged<String> onToggleReaction;
  final bool isMultiSelectMode;
  final bool isSelected;
  final ValueChanged<int>? onToggleSelect;
  final VoidCallback? onRestore;

  const _ChatMessageBubble({
    required this.message,
    this.replyToMessage,
    required this.isOwnMessage,
    this.avatarUrl,
    required this.theme,
    required this.onLongPress,
    required this.onToggleReaction,
    this.isMultiSelectMode = false,
    this.isSelected = false,
    this.onToggleSelect,
    this.onRestore,
  });

  List<String> _extractImageUrls() {
    final urls = <String>[];
    final seen = <String>{};

    // 判断是否为非正文图片（emoji / 引用块头像 / 缩略图 / 站点图标等）
    // 这些 img 标签由 Discourse 渲染引擎插入，属于 UI 元素而非用户上传的正文图片，
    // 不应作为独立大图重复渲染（否则引用块头像会被 quote 卡片小头像 + 大图各显示一次）。
    bool isNonContentImage(String rawStr) {
      final lower = rawStr.toLowerCase();
      // emoji 表情
      if (lower.contains('class="emoji"') ||
          lower.contains("class='emoji'") ||
          lower.contains('class=emoji') ||
          lower.contains('/images/emoji/') ||
          lower.contains('/emoji/')) {
        return true;
      }
      // 引用块头像 / 缩略图 / 站点图标 / 视频 poster 等装饰性图片
      if (lower.contains('class="avatar"') ||
          lower.contains("class='avatar'") ||
          lower.contains('class=avatar') ||
          lower.contains('"avatar ') ||
          lower.contains("'avatar ") ||
          lower.contains(' avatar"') ||
          lower.contains(" avatar'") ||
          lower.contains('class="thumbnail"') ||
          lower.contains("class='thumbnail'") ||
          lower.contains('class="site-icon"') ||
          lower.contains("class='site-icon'") ||
          lower.contains('class="favicon"') ||
          lower.contains("class='favicon'") ||
          lower.contains('class="ytp-thumbnail-image"') ||
          lower.contains("class='ytp-thumbnail-image'") ||
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

    // 1. 从 uploads 字典列表中提取 HTTP 图像 URL (优先使用 url / full_url / short_path)
    if (message.uploads != null) {
      for (final u in message.uploads!) {
        final path = u['url'] as String? ??
            u['full_url'] as String? ??
            u['short_path'] as String? ??
            (u['short_url'] is String && !(u['short_url'] as String).startsWith('upload://')
                ? u['short_url'] as String
                : null);
        addUrl(path);
      }
    }

    // 2. 从 message 文本中匹配 markdown 图片格式 ![alt](url)
    final mdRegex = RegExp(r'!\[.*?\]\((.*?)\)');
    for (final match in mdRegex.allMatches(message.message)) {
      final urlCandidate = match.group(1);
      if (urlCandidate != null) {
        addUrl(urlCandidate.split(' ').first);
      }
    }

    // 3. 从 cooked HTML 中匹配非表情 <img ...> 标签
    if (message.cooked != null && message.cooked!.isNotEmpty) {
      final imgRegex = RegExp(r'<img[^>]+>', caseSensitive: false);
      for (final match in imgRegex.allMatches(message.cooked!)) {
        final imgTag = match.group(0) ?? '';
        if (isNonContentImage(imgTag)) continue;

        final srcMatch =
            RegExp('src=["\']([^"\']+)["\']', caseSensitive: false)
                .firstMatch(imgTag);
        if (srcMatch != null) {
          addUrl(srcMatch.group(1));
        }
      }
    }

    return urls;
  }

  @override
  Widget build(BuildContext context) {
    if (message.deleted) {
      return _buildDeletedMessage(context);
    }

    final alignment =
        isOwnMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final showSender = !isOwnMessage && message.user != null;
    final imageUrls = _extractImageUrls();

    // 过滤除去纯图片 markdown 链接后的文本展示
    String displayText = message.message;
    for (final url in imageUrls) {
      displayText = displayText.replaceAll(RegExp('!\\[.*?\\]\\(${RegExp.escape(url)}\\)'), '');
    }
    displayText = displayText.replaceAll(RegExp(r'!\[.*?\]\(upload://[^\)]+\)'), '').trim();

    final bubbleWidget = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isMultiSelectMode)
                Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 4),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => onToggleSelect?.call(message.id),
                    visualDensity: VisualDensity.compact,
                  ),
                ),

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

              // 气泡「按内容自适应宽度」靠的是整条链路都不横向拉伸：
              // Column(crossAxisAlignment != stretch) → 宽度 = 最宽子项自然宽，
              // Container 的 maxWidth 仍保证长文本在 0.75 屏宽处换行。
              //
              // 这里**不能**用 IntrinsicWidth：正文渲染子树里图片 / iframe /
              // 视频等 builder 内部有 LayoutBuilder，不支持 dry layout 与内在
              // 尺寸，被问到就抛异常，整条消息布局失败 → 消息肉眼不可见。
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

                    // 关联回复引用框（移到气泡上方）
                    if (replyToMessage != null)
                      GestureDetector(
                        onTap: () {
                          // TODO: 滚动到被引用的消息位置
                          // 需要通过回调将 replyToMessage.id 传给父级，
                          // 父级通过 ScrollController 滚动到对应位置
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border(
                              left: BorderSide(
                                color: theme.colorScheme.primary,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.reply,
                                size: 14,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${replyToMessage!.user?.username ?? '未知用户'}: ${replyToMessage!.message}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    GestureDetector(
                      onLongPress: isMultiSelectMode ? null : onLongPress,
                      onTap: isMultiSelectMode
                          ? () => onToggleSelect?.call(message.id)
                          : null,
                      child: Container(
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

                            // 图片附件与 HTML 媒体展示 (点击放大全屏查看)
                            if (imageUrls.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: imageUrls.asMap().entries.map((entry) {
                                    final idx = entry.key;
                                    final url = entry.value;
                                    return GestureDetector(
                                      onTap: () {
                                        ImageViewerPage.open(
                                          context,
                                          url,
                                          galleryImages: imageUrls,
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

                            // 消息内容渲染：优先使用 cooked HTML（支持引用、onebox 等），
                            // 回退到纯文本 + emoji 渲染
                            if (message.cooked != null && message.cooked!.isNotEmpty)
                              _CookedHtmlContent(
                                cooked: message.cooked!,
                                messageId: message.id,
                                isOwnMessage: isOwnMessage,
                                theme: theme,
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

                            // 时间戳 + 编辑标记 + 书签标记
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
                                if (message.bookmarked) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.bookmark_rounded,
                                    size: 11,
                                    color: (isOwnMessage
                                            ? theme.colorScheme.onPrimaryContainer
                                            : theme.colorScheme.primary)
                                        .withValues(alpha: 0.8),
                                  ),
                                ],
                                if (message.pinned) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.push_pin_rounded,
                                    size: 11,
                                    color: (isOwnMessage
                                            ? theme.colorScheme.onPrimaryContainer
                                            : theme.colorScheme.primary)
                                        .withValues(alpha: 0.8),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Emoji 回应 (Reactions) 移到气泡下方
                    if (message.reactions != null &&
                        message.reactions!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
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
                                      width: 1,
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
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
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

    return bubbleWidget;
  }

  Widget _buildDeletedMessage(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      child: Row(
        mainAxisAlignment:
            isOwnMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: onLongPress,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.chat_message_deleted,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.5),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  if (onRestore != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: onRestore,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('恢复'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 聊天消息举报面板
class _ChatMessageFlagSheet extends StatefulWidget {
  final int channelId;
  final int messageId;
  final String username;
  final List<String>? availableFlagKeys;

  const _ChatMessageFlagSheet({
    required this.channelId,
    required this.messageId,
    required this.username,
    this.availableFlagKeys,
  });

  @override
  State<_ChatMessageFlagSheet> createState() => _ChatMessageFlagSheetState();
}

class _ChatMessageFlagSheetState extends State<_ChatMessageFlagSheet> {
  List<FlagType> _flagTypes = [];
  FlagType? _selected;
  final _messageController = TextEditingController();
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    final preloaded = PreloadedDataService();
    final types = await preloaded.getPostActionTypes();
    if (!mounted) return;
    setState(() {
      final parsed = (types ?? const [])
          .map((t) => FlagType.fromJson(Map<String, dynamic>.from(t as Map)))
          .where((f) => f.isFlag && f.enabled && f.appliesToChatMessage)
          .toList()
        ..sort((a, b) => a.position.compareTo(b.position));
      // 若消息自带 available_flags，再按 nameKey 过滤
      if (widget.availableFlagKeys != null &&
          widget.availableFlagKeys!.isNotEmpty) {
        final keys = widget.availableFlagKeys!.toSet();
        _flagTypes =
            parsed.where((f) => keys.contains(f.nameKey)).toList();
        if (_flagTypes.isEmpty) {
          // 服务端给了符号但预加载类型匹配不上时，回退全部 chat 适用类型
          _flagTypes = parsed;
        }
      } else {
        _flagTypes = parsed.isNotEmpty ? parsed : FlagType.defaultTypes;
      }
      _loading = false;
    });
  }

  Future<void> _submit() async {
    if (_selected == null || _submitting) return;
    if (_selected!.requireMessage && _messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写举报说明')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await DiscourseService().flagChatMessage(
        widget.channelId,
        widget.messageId,
        _selected!.id,
        message: _messageController.text.trim().isEmpty
            ? null
            : _messageController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已提交举报')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('举报失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '举报 @${widget.username} 的消息',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else ...[
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _flagTypes.length,
                  itemBuilder: (context, index) {
                    final type = _flagTypes[index];
                    return RadioListTile<FlagType>(
                      value: type,
                      groupValue: _selected,
                      onChanged: _submitting
                          ? null
                          : (v) => setState(() => _selected = v),
                      title: Text(type.name),
                      subtitle: type.shortDescription != null ||
                              type.description.isNotEmpty
                          ? Text(
                              (type.shortDescription ?? type.description)
                                  .replaceAll('%{username}', widget.username)
                                  .replaceAll(
                                    '@%{username}',
                                    '@${widget.username}',
                                  ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                    );
                  },
                ),
              ),
              if (_selected?.requireMessage == true)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _messageController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: '请说明举报原因',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _selected == null || _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('提交举报'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 聊天消息 cooked HTML 渲染组件
///
/// 使用 [FluxdoRenderCallbacks.generic] 渲染 Discourse cooked HTML，
/// 支持引用（quote）、onebox（链接预览）、代码块、图片等富文本内容。
class _CookedHtmlContent extends StatelessWidget {
  final String cooked;
  final int messageId;
  final bool isOwnMessage;
  final ThemeData theme;

  const _CookedHtmlContent({
    required this.cooked,
    required this.messageId,
    required this.isOwnMessage,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final callbacks = FluxdoRenderCallbacks.generic(
      heroTagNamespace: 'chat_msg_$messageId',
    );
    return callbacks.render(
      cookedHtml: cooked,
      baseTextStyle: theme.textTheme.bodyMedium?.copyWith(
        color: isOwnMessage
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface,
      ),
      selectionEnabled: true,
      compact: true,
      trimTopMargin: true,
      trimBottomMargin: true,
      // 气泡宽度要贴合内容：块级子项不横向拉伸，否则每条消息都会撑满
      // 0.75 屏宽（外层不能用 IntrinsicWidth，见 _ChatMessageBubble 注释）。
      stretchBlocks: false,
    );
  }
}