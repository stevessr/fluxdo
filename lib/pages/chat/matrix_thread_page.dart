import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';

import '../../services/matrix_client_service.dart';
import '../../services/messaging/matrix_media_service.dart';
import 'matrix_message_media_view.dart';

class MatrixThreadPage extends StatefulWidget {
  const MatrixThreadPage({
    super.key,
    required this.client,
    required this.room,
    required this.root,
    required this.mediaService,
  });

  final MatrixClientService client;
  final MatrixRoomSummary room;
  final MatrixMessage root;
  final MatrixMediaService mediaService;

  @override
  State<MatrixThreadPage> createState() => _MatrixThreadPageState();
}

class _MatrixThreadPageState extends State<MatrixThreadPage> {
  static const Duration _typingIdleDelay = Duration(seconds: 5);
  static const List<String> _quickReactions = <String>[
    '👍',
    '❤️',
    '😂',
    '🎉',
    '👀',
    '🔥',
  ];

  final TextEditingController _composer = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Timer? _typingStopTimer;
  bool _typingSent = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _requestInFlight = false;
  bool _sending = false;
  bool _uploadingMedia = false;
  double? _uploadProgress;
  String? _error;
  String? _nextToken;
  List<MatrixMessage> _messages = const <MatrixMessage>[];

  bool get _composerBusy => _sending || _uploadingMedia;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _typingStopTimer?.cancel();
    if (_typingSent) {
      unawaited(_setTyping(false));
    }
    widget.client.releaseThread(widget.room.roomId, widget.root.eventId);
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({String? from, bool more = false}) async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final page = await widget.client.loadThreadPage(
        widget.room.roomId,
        widget.root.eventId,
        from: from,
      );
      if (!mounted) return;
      setState(() {
        _messages = page.messages;
        final next = page.nextToken;
        _nextToken = next == from ? null : next;
      });
      final latestEventId = page.messages.isEmpty
          ? widget.root.eventId
          : page.messages.last.eventId;
      unawaited(_markRead(latestEventId));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _requestInFlight = false;
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _markRead(String eventId) async {
    try {
      await widget.client.markRead(widget.room.roomId, eventId);
    } catch (_) {
      // Read receipts are best-effort and must not break thread rendering.
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
      await widget.client.setTyping(
        widget.room.roomId,
        typing: typing,
      );
    } catch (_) {
      // Typing is ephemeral. Keep composing even if the request fails.
    }
  }

  String get _fallbackTarget =>
      _messages.isEmpty ? widget.root.eventId : _messages.last.eventId;

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _composerBusy || widget.room.encrypted) return;
    _typingStopTimer?.cancel();
    unawaited(_setTyping(false));
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.client.sendText(
        widget.room.roomId,
        text,
        threadRootEventId: widget.root.eventId,
        replyToEventId: _fallbackTarget,
        threadFallback: true,
      );
      _composer.clear();
      widget.client.releaseThread(widget.room.roomId, widget.root.eventId);
      await _load();
      _scrollToBottom();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendMedia() async {
    if (_composerBusy || widget.room.encrypted) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.single;

    _typingStopTimer?.cancel();
    unawaited(_setTyping(false));
    setState(() {
      _uploadingMedia = true;
      _uploadProgress = 0;
      _error = null;
    });
    try {
      int? serverMaxBytes;
      try {
        serverMaxBytes = await widget.mediaService.maxUploadBytes();
      } on MatrixMediaException {
        // Some older homeservers do not expose media/config.
      }
      const fallbackUploadLimit = 512 * 1024 * 1024;
      final effectiveMax = serverMaxBytes ?? fallbackUploadLimit;
      if (file.size > effectiveMax) {
        throw MatrixMediaException(
          '附件 ${file.name} 为 ${_formatBytes(file.size)}；当前允许上限为 '
          '${_formatBytes(effectiveMax)}。',
        );
      }

      final contentType = lookupMimeType(file.name) ?? 'application/octet-stream';
      var lastRenderedProgress = -1.0;
      final uploaded = await widget.mediaService.uploadStream(
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
      await widget.mediaService.sendUpload(
        widget.room.roomId,
        uploaded,
        threadRootEventId: widget.root.eventId,
        replyToEventId: _fallbackTarget,
        threadFallback: true,
      );
      widget.client.releaseThread(widget.room.roomId, widget.root.eventId);
      await _load();
      _scrollToBottom();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _uploadingMedia = false;
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _showReactionPicker(MatrixMessage message) async {
    if (widget.room.encrypted || message.encrypted || message.redacted) return;
    final reaction = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: _quickReactions
                .map(
                  (value) => ActionChip(
                    label: Text(value, style: const TextStyle(fontSize: 22)),
                    onPressed: () => Navigator.of(context).pop(value),
                  ),
                )
                .toList(growable: false),
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
      widget.client.releaseThread(widget.room.roomId, widget.root.eventId);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kib = bytes / 1024;
    if (kib < 1024) return '${kib.toStringAsFixed(1)} KiB';
    final mib = kib / 1024;
    return '${mib.toStringAsFixed(1)} MiB';
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.client.session;
    final currentUserId = session?.userId;
    final messagesById = <String, MatrixMessage>{
      widget.root.eventId: widget.root,
      for (final message in _messages) message.eventId: message,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Thread · ${widget.room.name}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新 Thread',
            onPressed: _requestInFlight ? null : () => _load(),
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
                        '此 Thread 属于 E2EE 房间；SDK crypto provider 接入前禁止发送明文、reaction 与附件。',
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
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.error_outline_rounded, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!)),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    children: <Widget>[
                      _ThreadMessageCard(
                        message: widget.root,
                        own: widget.root.sender == currentUserId,
                        mediaService: widget.mediaService,
                        label: 'Thread root',
                        onLongPress: widget.room.encrypted ||
                                widget.root.encrypted ||
                                widget.root.redacted
                            ? null
                            : () => _showReactionPicker(widget.root),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(),
                      ),
                      if (_nextToken != null)
                        Center(
                          child: TextButton.icon(
                            onPressed: _requestInFlight
                                ? null
                                : () => _load(from: _nextToken, more: true),
                            icon: _loadingMore
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.history_rounded),
                            label: Text(_loadingMore ? '加载中…' : '加载更多关系'),
                          ),
                        ),
                      for (final message in _messages)
                        _ThreadMessageCard(
                          message: message,
                          own: message.sender == currentUserId,
                          mediaService: widget.mediaService,
                          replyTarget: message.replyToEventId == null
                              ? null
                              : messagesById[message.replyToEventId],
                          onLongPress: widget.room.encrypted ||
                                  message.encrypted ||
                                  message.redacted
                              ? null
                              : () => _showReactionPicker(message),
                        ),
                      if (_messages.isEmpty && !_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(child: Text('这个 Thread 还没有回复')),
                        ),
                    ],
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  IconButton(
                    tooltip: widget.room.encrypted
                        ? 'E2EE 尚未启用，不能上传明文附件'
                        : '发送附件到 Thread',
                    onPressed: widget.room.encrypted || _composerBusy
                        ? null
                        : _pickAndSendMedia,
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
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      enabled: !widget.room.encrypted && !_uploadingMedia,
                      onChanged: _onComposerChanged,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: widget.room.encrypted
                            ? 'E2EE provider 接入前禁止明文发送'
                            : '回复 Thread…',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    tooltip: '回复 Thread',
                    onPressed: widget.room.encrypted || _composerBusy ? null : _send,
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
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

class _ThreadMessageCard extends StatelessWidget {
  const _ThreadMessageCard({
    required this.message,
    required this.own,
    required this.mediaService,
    this.replyTarget,
    this.label,
    this.onLongPress,
  });

  final MatrixMessage message;
  final bool own;
  final MatrixMediaService mediaService;
  final MatrixMessage? replyTarget;
  final String? label;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final time = TimeOfDay.fromDateTime(message.timestamp).format(context);
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: own
                ? colors.primaryContainer
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (label != null)
                Text(
                  label!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (!own)
                Text(
                  message.sender,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (replyTarget != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  '↪ ${replyTarget!.sender}: ${replyTarget!.body}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 4),
              Text(message.body),
              if (message.hasMedia)
                MatrixMessageMediaView(
                  message: message,
                  mediaService: mediaService,
                ),
              if (message.reactions.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: message.reactions.entries
                      .map((entry) => Text('${entry.key} ${entry.value}'))
                      .toList(growable: false),
                ),
              ],
              const SizedBox(height: 3),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  message.edited ? '已编辑 · $time' : time,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
