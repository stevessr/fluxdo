import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/matrix_client_service.dart';

class MatrixRoomPageV2 extends StatefulWidget {
  const MatrixRoomPageV2({
    super.key,
    required this.client,
    required this.room,
  });

  final MatrixClientService client;
  final MatrixRoomSummary room;

  @override
  State<MatrixRoomPageV2> createState() => _MatrixRoomPageV2State();
}

class _MatrixRoomPageV2State extends State<MatrixRoomPageV2> {
  static const Duration _typingIdleDelay = Duration(seconds: 5);
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
  bool _typingSent = false;
  bool _loading = true;
  bool _loadingOlder = false;
  bool _sending = false;
  String? _error;
  String? _nextToken;
  List<MatrixMessage> _messages = const <MatrixMessage>[];

  @override
  void initState() {
    super.initState();
    unawaited(_loadLatest());
  }

  @override
  void dispose() {
    _typingStopTimer?.cancel();
    if (_typingSent) {
      unawaited(_setTyping(false));
    }
    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLatest({
    bool showSpinner = true,
    bool scrollToBottom = true,
  }) async {
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
        _nextToken = page.endToken;
        _error = null;
      });
      if (_messages.isNotEmpty) {
        unawaited(_markRead(_messages.last.eventId));
      }
      if (scrollToBottom) _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (showSpinner && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadOlder() async {
    final token = _nextToken;
    if (token == null || token.isEmpty || _loadingOlder) return;

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
      setState(() {
        _messages = page.messages;
        // A homeserver returning the same token forever must not create an
        // infinite "load older" loop.
        _nextToken = page.endToken == token ? null : page.endToken;
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
    if (_typingSent == typing) return;
    _typingSent = typing;
    try {
      await widget.client.setTyping(
        widget.room.roomId,
        typing: typing,
      );
    } catch (_) {
      // Typing is ephemeral. Network failures should not disturb composing.
    }
  }

  Future<void> _send() async {
    final text = _composerController.text.trim();
    if (text.isEmpty || _sending) return;

    _typingStopTimer?.cancel();
    unawaited(_setTyping(false));
    setState(() => _sending = true);
    try {
      await widget.client.sendText(widget.room.roomId, text);
      _composerController.clear();
      await _loadLatest(showSpinner: false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showReactionPicker(MatrixMessage message) async {
    if (message.encrypted || message.redacted) return;
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
      // Re-fetch the newest page so the just-sent relation becomes part of the
      // room event accumulator and its count is visible immediately.
      await _loadLatest(showSpinner: false, scrollToBottom: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已发送 reaction $reaction')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
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
    final currentUserId = widget.client.session?.userId;
    final hasOlder = _nextToken != null && _nextToken!.isNotEmpty;

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
            onPressed: _loading
                ? null
                : () => unawaited(_loadLatest(scrollToBottom: false)),
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
                        '此房间启用了 E2EE；轻量 REST provider 尚未解密，密文消息会明确显示为占位符。',
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    onRefresh: () => _loadLatest(scrollToBottom: false),
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
                                label: Text(
                                  _loadingOlder ? '加载中…' : '加载更早消息',
                                ),
                              ),
                            ),
                          );
                        }

                        final messageIndex = index - (hasOlder ? 1 : 0);
                        final message = _messages[messageIndex];
                        final own = message.sender == currentUserId;
                        return _MatrixMessageBubble(
                          message: message,
                          own: own,
                          onLongPress: message.encrypted || message.redacted
                              ? null
                              : () => _showReactionPicker(message),
                        );
                      },
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _composerController,
                      minLines: 1,
                      maxLines: 6,
                      textInputAction: TextInputAction.newline,
                      onChanged: _onComposerChanged,
                      decoration: const InputDecoration(
                        hintText: '发送 Matrix 消息…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    tooltip: '发送',
                    onPressed: _sending ? null : _send,
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

class _MatrixMessageBubble extends StatelessWidget {
  const _MatrixMessageBubble({
    required this.message,
    required this.own,
    this.onLongPress,
  });

  final MatrixMessage message;
  final bool own;
  final VoidCallback? onLongPress;

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
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
