import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';

import '../../services/matrix_client_service.dart';
import '../../services/messaging/matrix_media_service.dart';
import 'matrix_message_media_view.dart';
import 'matrix_thread_page.dart' as thread_ui;

class MatrixRoomPage extends StatefulWidget {
  const MatrixRoomPage({super.key, required this.client, required this.room});

  final MatrixClientService client;
  final MatrixRoomSummary room;

  @override
  State<MatrixRoomPage> createState() => _MatrixRoomPageState();
}

enum _MessageAction { reply, thread, reaction, edit, redact }

class _MatrixRoomPageState extends State<MatrixRoomPage>
    with WidgetsBindingObserver {
  static const Duration _typingIdleDelay = Duration(seconds: 5);
  static const Duration _foregroundRefreshInterval = Duration(seconds: 20);
  static const List<String> _quickReactions = <String>[
    '👍',
    '❤️',
    '😂',
    '🎉',
    '👀',
    '🔥',
  ];

  final TextEditingController _composerController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Timer? _typingStopTimer;
  Timer? _refreshTimer;
  MatrixMediaService? _mediaService;
  bool _threadRouteActive = false;
  bool _typingSent = false;
  bool _loading = true;
  bool _loadingOlder = false;
  bool _refreshingLatest = false;
  bool _sending = false;
  bool _uploadingMedia = false;
  double? _uploadProgress;
  bool _paginationInitialized = false;
  bool _historyExhausted = false;
  String? _error;
  String? _nextOlderToken;
  List<MatrixMessage> _messages = const <MatrixMessage>[];

  MatrixMessage? _replyTarget;
  String? _composerThreadRootEventId;
  bool _composerThreadFallback = false;

  bool get _sendingDisabled =>
      widget.room.encrypted || _sending || _uploadingMedia;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startForegroundRefresh();
    unawaited(_loadLatest());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_threadRouteActive) {
        _startForegroundRefresh();
        unawaited(_refreshLatestSilently());
      }
    } else {
      _stopForegroundRefresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopForegroundRefresh();
    _typingStopTimer?.cancel();
    if (_typingSent) {
      unawaited(_setTyping(false));
    }
    widget.client.releaseTimeline(widget.room.roomId);
    _mediaService?.dispose();
    _mediaService = null;
    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startForegroundRefresh() {
    if (_threadRouteActive) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      _foregroundRefreshInterval,
      (_) => unawaited(_refreshLatestSilently()),
    );
  }

  void _stopForegroundRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _refreshLatestSilently() async {
    if (!mounted ||
        _threadRouteActive ||
        _loading ||
        _loadingOlder ||
        _sending ||
        _uploadingMedia ||
        _refreshingLatest) {
      return;
    }
    await _loadLatest(
      showSpinner: false,
      scrollToBottom: false,
      preservePaginationCursor: true,
      surfaceErrors: false,
    );
  }

  Future<void> _loadLatest({
    bool showSpinner = true,
    bool scrollToBottom = true,
    bool preservePaginationCursor = false,
    bool surfaceErrors = true,
  }) async {
    if (_refreshingLatest) return;
    _refreshingLatest = true;

    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final page = await widget.client.loadMessagePage(widget.room.roomId);
      if (!mounted) return;
      setState(() {
        _messages = page.messages;
        if (!preservePaginationCursor || !_paginationInitialized) {
          _nextOlderToken = page.endToken;
          _historyExhausted = page.endToken == null || page.endToken!.isEmpty;
          _paginationInitialized = true;
        }
        if (surfaceErrors) _error = null;
      });
      if (_messages.isNotEmpty) {
        unawaited(_markRead(_messages.last.eventId));
      }
      if (scrollToBottom) _scrollToBottom();
    } catch (error) {
      if (!mounted || !surfaceErrors) return;
      setState(() => _error = error.toString());
    } finally {
      _refreshingLatest = false;
      if (showSpinner && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadOlder() async {
    final token = _nextOlderToken;
    if (token == null ||
        token.isEmpty ||
        _historyExhausted ||
        _loadingOlder ||
        _refreshingLatest) {
      return;
    }

    final beforePixels = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    final beforeMax = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;

    setState(() {
      _loadingOlder = true;
      _error = null;
    });

    try {
      final page = await widget.client.loadMessagePage(
        widget.room.roomId,
        from: token,
      );
      if (!mounted) return;
      final next = page.endToken;
      setState(() {
        _messages = page.messages;
        if (next == null || next.isEmpty || next == token) {
          _nextOlderToken = null;
          _historyExhausted = true;
        } else {
          _nextOlderToken = next;
        }
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final addedExtent =
            _scrollController.position.maxScrollExtent - beforeMax;
        final target = (beforePixels + addedExtent).clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(target);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _markRead(String eventId) async {
    try {
      await widget.client.markRead(widget.room.roomId, eventId);
    } catch (_) {
      // Read receipts are best-effort and should not block viewing a room.
    }
  }

  void _onComposerChanged(String value) {
    if (widget.room.encrypted) return;
    _typingStopTimer?.cancel();
    if (value.trim().isEmpty) {
      unawaited(_setTyping(false));
      return;
    }

    if (!_typingSent) {
      unawaited(_setTyping(true));
    }
    _typingStopTimer = Timer(
      _typingIdleDelay,
      () => unawaited(_setTyping(false)),
    );
  }

  Future<void> _setTyping(bool typing) async {
    if (widget.room.encrypted || _typingSent == typing) return;
    _typingSent = typing;
    try {
      await widget.client.setTyping(widget.room.roomId, typing: typing);
    } catch (_) {
      // Typing is ephemeral. Network failures should not disturb composing.
    }
  }

  Future<void> _send() async {
    final text = _composerController.text.trim();
    if (text.isEmpty || _sendingDisabled) return;

    _typingStopTimer?.cancel();
    unawaited(_setTyping(false));
    setState(() => _sending = true);
    try {
      await widget.client.sendText(
        widget.room.roomId,
        text,
        replyToEventId: _replyTarget?.eventId,
        threadRootEventId: _composerThreadRootEventId,
        threadFallback: _composerThreadFallback,
      );
      _composerController.clear();
      if (mounted) {
        setState(_clearComposerRelation);
      }
      await _loadLatest(showSpinner: false, preservePaginationCursor: true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  MatrixMediaService _mediaFor(MatrixSession session) {
    final current = _mediaService;
    if (current != null &&
        current.session.homeserver == session.homeserver &&
        current.session.accessToken == session.accessToken) {
      return current;
    }
    current?.dispose();
    return _mediaService = MatrixMediaService(session: session);
  }

  Future<void> _pickAndSendMedia() async {
    if (_sendingDisabled) return;
    final session = widget.client.session;
    if (session == null) {
      setState(() => _error = 'Matrix 会话已失效，请重新登录。');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.single;

    setState(() {
      _uploadingMedia = true;
      _uploadProgress = 0;
      _error = null;
    });
    try {
      final media = _mediaFor(session);
      int? serverMaxBytes;
      try {
        serverMaxBytes = await media.maxUploadBytes();
      } on MatrixMediaException {
        // Legacy homeservers may omit media/config. Streaming avoids heap OOM,
        // but keep a generous network-safety ceiling for the LAB provider.
      }

      const fallbackUploadLimit = 512 * 1024 * 1024;
      final effectiveMax = serverMaxBytes ?? fallbackUploadLimit;
      if (file.size > effectiveMax) {
        throw MatrixMediaException(
          '附件 ${file.name} 为 ${_formatBytes(file.size)}；当前允许上限为 '
          '${_formatBytes(effectiveMax)}。',
        );
      }

      final contentType =
          lookupMimeType(file.name) ?? 'application/octet-stream';
      var lastRenderedProgress = -1.0;
      final uploaded = await media.uploadStream(
        stream: file.xFile.openRead(),
        length: file.size,
        filename: file.name,
        contentType: contentType,
        onSendProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          final progress = (sent / total).clamp(0.0, 1.0);
          if (progress < 1 && progress - lastRenderedProgress < 0.01) return;
          lastRenderedProgress = progress;
          setState(() => _uploadProgress = progress);
        },
      );
      await media.sendUpload(
        widget.room.roomId,
        uploaded,
        replyToEventId: _replyTarget?.eventId,
        threadRootEventId: _composerThreadRootEventId,
        threadFallback: _composerThreadFallback,
      );
      if (!mounted) return;
      setState(_clearComposerRelation);
      await _loadLatest(showSpinner: false, preservePaginationCursor: true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _uploadingMedia = false;
          _uploadProgress = null;
        });
      }
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kib = bytes / 1024;
    if (kib < 1024) return '${kib.toStringAsFixed(1)} KiB';
    final mib = kib / 1024;
    return '${mib.toStringAsFixed(1)} MiB';
  }

  void _clearComposerRelation() {
    _replyTarget = null;
    _composerThreadRootEventId = null;
    _composerThreadFallback = false;
  }

  void _prepareReply(MatrixMessage message) {
    if (widget.room.encrypted || message.encrypted || message.redacted) return;
    setState(() {
      _replyTarget = message;
      // Replying to an event already inside a thread should remain inside the
      // same thread. This is a genuine threaded reply, not a fallback relation.
      _composerThreadRootEventId = message.threadRootEventId;
      _composerThreadFallback = false;
    });
  }

  void _prepareThreadReply(MatrixMessage message) {
    if (widget.room.encrypted || message.encrypted || message.redacted) return;
    setState(() {
      _replyTarget = message;
      _composerThreadRootEventId = message.threadRootEventId ?? message.eventId;
      // The reply target gives non-thread-aware clients continuity while the
      // m.thread relation always points at the actual root.
      _composerThreadFallback = true;
    });
  }

  bool _canEditMessage(MatrixMessage message) {
    final currentUserId = widget.client.session?.userId;
    return !widget.room.encrypted &&
        !message.encrypted &&
        !message.redacted &&
        currentUserId != null &&
        message.sender == currentUserId &&
        message.msgType == 'm.text' &&
        !message.hasMedia;
  }

  bool _canRedactMessage(MatrixMessage message) {
    final currentUserId = widget.client.session?.userId;
    return !widget.room.encrypted &&
        !message.encrypted &&
        !message.redacted &&
        currentUserId != null &&
        message.sender == currentUserId;
  }

  Future<void> _editMessage(MatrixMessage message) async {
    if (!_canEditMessage(message)) return;
    var draft = message.body;
    try {
      final replacement = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('编辑消息'),
          content: TextFormField(
            initialValue: message.body,
            autofocus: true,
            minLines: 1,
            maxLines: 8,
            onChanged: (value) => draft = value,
            decoration: const InputDecoration(
              hintText: '新的消息内容',
              border: OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(draft.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (!mounted || replacement == null || replacement.isEmpty) return;
      if (replacement == message.body.trim()) return;
      await widget.client.editText(
        widget.room.roomId,
        message.eventId,
        replacement,
      );
      await _loadLatest(
        showSpinner: false,
        scrollToBottom: false,
        preservePaginationCursor: true,
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _redactMessage(MatrixMessage message) async {
    if (!_canRedactMessage(message)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤回消息？'),
        content: Text(
          '这会通过 Matrix redaction 撤回该事件，且无法恢复。\n\n${message.body}',
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认撤回'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      await widget.client.redactEvent(widget.room.roomId, message.eventId);
      await _loadLatest(
        showSpinner: false,
        scrollToBottom: false,
        preservePaginationCursor: true,
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _showMessageActions(MatrixMessage message) async {
    if (widget.room.encrypted || message.encrypted || message.redacted) return;
    final canEdit = _canEditMessage(message);
    final canRedact = _canRedactMessage(message);
    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('回复'),
              subtitle: message.threadRootEventId == null
                  ? const Text('发送普通 Matrix rich reply')
                  : const Text('在当前 thread 内回复此消息'),
              onTap: () => Navigator.of(context).pop(_MessageAction.reply),
            ),
            ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: Text(message.threadRootEventId == null ? '开启线程' : '继续线程'),
              subtitle: const Text('使用 m.thread，并附带兼容 reply fallback'),
              onTap: () => Navigator.of(context).pop(_MessageAction.thread),
            ),
            ListTile(
              leading: const Icon(Icons.add_reaction_outlined),
              title: const Text('Reaction'),
              onTap: () => Navigator.of(context).pop(_MessageAction.reaction),
            ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑消息'),
                subtitle: const Text('发送标准 m.replace 关系事件'),
                onTap: () => Navigator.of(context).pop(_MessageAction.edit),
              ),
            if (canRedact)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('撤回消息'),
                subtitle: const Text('发送 Matrix redaction；无法恢复'),
                onTap: () => Navigator.of(context).pop(_MessageAction.redact),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _MessageAction.reply:
        _prepareReply(message);
      case _MessageAction.thread:
        _prepareThreadReply(message);
      case _MessageAction.reaction:
        await _showReactionPicker(message);
      case _MessageAction.edit:
        await _editMessage(message);
      case _MessageAction.redact:
        await _redactMessage(message);
    }
  }

  Future<void> _showReactionPicker(MatrixMessage message) async {
    if (widget.room.encrypted || message.encrypted || message.redacted) return;
    final reaction = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '发送 Reaction',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _quickReactions
                    .map(
                      (emoji) => ActionChip(
                        label: Text(
                          emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                        onPressed: () => Navigator.of(context).pop(emoji),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 10),
              Text(
                'Reaction 由当前已加载 timeline 本地聚合并按发送者去重。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
    if (reaction == null || !mounted) return;

    try {
      await widget.client.sendReaction(
        widget.room.roomId,
        message.eventId,
        reaction,
      );
      await _loadLatest(
        showSpinner: false,
        scrollToBottom: false,
        preservePaginationCursor: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已发送 reaction $reaction')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _openThread(MatrixMessage root) async {
    final session = widget.client.session;
    if (session == null) {
      if (mounted) setState(() => _error = 'Matrix 会话已失效，请重新登录。');
      return;
    }
    final mediaService = _mediaFor(session);
    _threadRouteActive = true;
    _stopForegroundRefresh();
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => thread_ui.MatrixThreadPage(
            client: widget.client,
            room: widget.room,
            root: root,
            mediaService: mediaService,
          ),
        ),
      );
    } finally {
      _threadRouteActive = false;
      if (mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _startForegroundRefresh();
        await _loadLatest(
          showSpinner: false,
          scrollToBottom: false,
          preservePaginationCursor: true,
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.client.session;
    final currentUserId = session?.userId;
    final mediaService = session == null ? null : _mediaFor(session);
    final hasOlder =
        !_historyExhausted &&
        _nextOlderToken != null &&
        _nextOlderToken!.isNotEmpty;
    final messagesById = <String, MatrixMessage>{
      for (final message in _messages) message.eventId: message,
    };

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            if (widget.room.encrypted) ...<Widget>[
              const Icon(Icons.lock_outline_rounded, size: 18),
              const SizedBox(width: 7),
            ],
            Expanded(
              child: Text(
                widget.room.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新最新消息',
            onPressed: _loading || _refreshingLatest
                ? null
                : () => unawaited(
                    _loadLatest(
                      scrollToBottom: false,
                      preservePaginationCursor: true,
                    ),
                  ),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (widget.room.encrypted)
            Material(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.lock_outline_rounded, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '此房间启用了 E2EE；轻量 REST provider 尚未解密。为避免泄漏明文，发送、回复、thread、reaction、编辑/撤回与 typing 已禁用。',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_error != null)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.error_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!)),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => _loadLatest(
                      scrollToBottom: false,
                      preservePaginationCursor: true,
                    ),
                    child: ListView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      itemCount: _messages.length + (hasOlder ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (hasOlder && index == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Center(
                              child: TextButton.icon(
                                onPressed: _loadingOlder ? null : _loadOlder,
                                icon: _loadingOlder
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.history_rounded),
                                label: Text(_loadingOlder ? '加载中…' : '加载更早消息'),
                              ),
                            ),
                          );
                        }

                        final messageIndex = index - (hasOlder ? 1 : 0);
                        final message = _messages[messageIndex];
                        final own = message.sender == currentUserId;
                        final replyTarget = message.replyToEventId == null
                            ? null
                            : messagesById[message.replyToEventId];
                        return _MatrixMessageBubble(
                          message: message,
                          own: own,
                          mediaService: mediaService,
                          replyTarget: replyTarget,
                          onOpenThread: message.threadCount > 0
                              ? () => _openThread(message)
                              : null,
                          onLongPress:
                              widget.room.encrypted ||
                                  message.encrypted ||
                                  message.redacted
                              ? null
                              : () => _showMessageActions(message),
                        );
                      },
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (_replyTarget != null && !widget.room.encrypted)
                    _ComposerRelationBar(
                      message: _replyTarget!,
                      threadRootEventId: _composerThreadRootEventId,
                      threadFallback: _composerThreadFallback,
                      onClear: () => setState(_clearComposerRelation),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      IconButton(
                        tooltip: widget.room.encrypted
                            ? 'E2EE 尚未启用，不能上传明文附件'
                            : '发送附件',
                        onPressed: _sendingDisabled ? null : _pickAndSendMedia,
                        icon: _uploadingMedia
                            ? SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value: _uploadProgress,
                                ),
                              )
                            : const Icon(Icons.attach_file_rounded),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: TextField(
                          controller: _composerController,
                          enabled: !widget.room.encrypted,
                          minLines: 1,
                          maxLines: 6,
                          textInputAction: TextInputAction.newline,
                          onChanged: _onComposerChanged,
                          decoration: InputDecoration(
                            hintText: widget.room.encrypted
                                ? 'E2EE provider 接入前禁止明文发送'
                                : '发送 Matrix 消息…',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        tooltip: widget.room.encrypted ? 'E2EE 尚未启用' : '发送',
                        onPressed: _sendingDisabled ? null : _send,
                        icon: _sending
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerRelationBar extends StatelessWidget {
  const _ComposerRelationBar({
    required this.message,
    required this.threadRootEventId,
    required this.threadFallback,
    required this.onClear,
  });

  final MatrixMessage message;
  final String? threadRootEventId;
  final bool threadFallback;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final inThread = threadRootEventId != null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Icon(inThread ? Icons.forum_outlined : Icons.reply_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  inThread
                      ? threadFallback
                            ? '在线程中回复 ${message.sender}'
                            : '回复 thread 中的 ${message.sender}'
                      : '回复 ${message.sender}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Text(
                  message.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '取消关系',
            onPressed: onClear,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _MatrixMessageBubble extends StatelessWidget {
  const _MatrixMessageBubble({
    required this.message,
    required this.own,
    this.mediaService,
    this.replyTarget,
    this.onLongPress,
    this.onOpenThread,
  });

  final MatrixMessage message;
  final bool own;
  final MatrixMediaService? mediaService;
  final MatrixMessage? replyTarget;
  final VoidCallback? onLongPress;
  final VoidCallback? onOpenThread;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final time = TimeOfDay.fromDateTime(message.timestamp).format(context);
    final reactionEntries = message.reactions.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));

    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: own
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (!own)
                Text(
                  message.sender,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (!own) const SizedBox(height: 3),
              if (message.replyToEventId != null) ...<Widget>[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                      left: BorderSide(color: colorScheme.primary, width: 3),
                    ),
                  ),
                  child: Text(
                    replyTarget == null
                        ? '↪ ${message.replyToEventId}'
                        : '↪ ${replyTarget!.sender}: ${replyTarget!.body}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (message.encrypted) ...<Widget>[
                    const Icon(Icons.lock_outline_rounded, size: 16),
                    const SizedBox(width: 5),
                  ] else if (message.redacted) ...<Widget>[
                    const Icon(Icons.block_rounded, size: 16),
                    const SizedBox(width: 5),
                  ],
                  Flexible(child: Text(message.body)),
                ],
              ),
              if (message.hasMedia && mediaService != null)
                MatrixMessageMediaView(
                  message: message,
                  mediaService: mediaService!,
                ),
              if (message.threadCount > 0) ...<Widget>[
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  children: <Widget>[
                    _RelationChip(
                      icon: Icons.forum_rounded,
                      label: '${message.threadCount} 条线程回复',
                      onTap: onOpenThread,
                    ),
                  ],
                ),
              ],
              if (reactionEntries.isNotEmpty) ...<Widget>[
                const SizedBox(height: 7),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: reactionEntries
                      .map(
                        (entry) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                          child: Text(
                            '${entry.key} ${entry.value}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              const SizedBox(height: 3),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  message.edited ? '已编辑 · $time' : time,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelationChip extends StatelessWidget {
  const _RelationChip({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.secondaryContainer.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 13),
              const SizedBox(width: 4),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
