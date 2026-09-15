import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/matrix_client_service.dart';
import 'matrix_message_media_view.dart';

class MatrixThreadPage extends StatefulWidget {
  const MatrixThreadPage({
    super.key,
    required this.client,
    required this.room,
    required this.root,
  });

  final MatrixClientService client;
  final MatrixRoomSummary room;
  final MatrixMessage root;

  @override
  State<MatrixThreadPage> createState() => _MatrixThreadPageState();
}

class _MatrixThreadPageState extends State<MatrixThreadPage> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _loadingMore = false;
  bool _requestInFlight = false;
  bool _sending = false;
  String? _error;
  String? _nextToken;
  List<MatrixMessage> _messages = const <MatrixMessage>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
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

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending || widget.room.encrypted) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final fallbackTarget = _messages.isEmpty
          ? widget.root.eventId
          : _messages.last.eventId;
      await widget.client.sendText(
        widget.room.roomId,
        text,
        threadRootEventId: widget.root.eventId,
        replyToEventId: fallbackTarget,
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
                        session: session,
                        label: 'Thread root',
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
                          session: session,
                          replyTarget: message.replyToEventId == null
                              ? null
                              : messagesById[message.replyToEventId],
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
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      enabled: !widget.room.encrypted,
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
                    onPressed: widget.room.encrypted || _sending ? null : _send,
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
    required this.session,
    this.replyTarget,
    this.label,
  });

  final MatrixMessage message;
  final bool own;
  final MatrixSession? session;
  final MatrixMessage? replyTarget;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final time = TimeOfDay.fromDateTime(message.timestamp).format(context);
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
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
            if (message.hasMedia && session != null)
              MatrixMessageMediaView(message: message, session: session!),
            if (message.reactions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Wrap(
                spacing: 5,
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
    );
  }
}
