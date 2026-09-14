import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/matrix_client_service.dart';

class MatrixChatPage extends StatefulWidget {
  const MatrixChatPage({super.key});

  @override
  State<MatrixChatPage> createState() => _MatrixChatPageState();
}

class _MatrixChatPageState extends State<MatrixChatPage> {
  final MatrixClientService _client = MatrixClientService();
  final TextEditingController _homeserverController = TextEditingController(
    text: 'https://matrix.org',
  );
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _tokenMode = false;
  String? _error;
  MatrixSession? _session;
  List<MatrixRoomSummary> _rooms = const <MatrixRoomSummary>[];

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _homeserverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _userIdController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final session = await _client.restoreSession();
      if (!mounted) return;
      setState(() => _session = session);
      if (session != null) {
        await _loadRooms(showSpinner: false);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signIn() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final MatrixSession session;
      if (_tokenMode) {
        session = await _client.loginWithAccessToken(
          homeserver: _homeserverController.text,
          userId: _userIdController.text,
          accessToken: _tokenController.text,
        );
      } else {
        session = await _client.loginWithPassword(
          homeserver: _homeserverController.text,
          username: _usernameController.text,
          password: _passwordController.text,
        );
      }
      if (!mounted) return;
      _passwordController.clear();
      _tokenController.clear();
      setState(() => _session = session);
      await _loadRooms(showSpinner: false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _loadRooms({bool showSpinner = true}) async {
    if (_session == null) return;
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final rooms = await _client.loadRooms();
      if (!mounted) return;
      setState(() => _rooms = rooms);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (showSpinner && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await _client.logout();
    if (!mounted) return;
    setState(() {
      _session = null;
      _rooms = const <MatrixRoomSummary>[];
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final session = _session;
    if (session == null) return _buildLogin();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matrix'),
        actions: <Widget>[
          IconButton(
            tooltip: '增量刷新房间',
            onPressed: _loading ? null : _loadRooms,
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') _logout();
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  session.userId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Text('退出 Matrix'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: <Widget>[
                  Icon(Icons.science_outlined, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '实验性 Matrix：房间列表使用增量 /sync；支持文本、已读、typing 与 reaction。E2EE 暂显示占位符。',
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
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.error_outline_rounded, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!)),
                  ],
                ),
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadRooms(showSpinner: false),
              child: _rooms.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const <Widget>[
                        SizedBox(height: 120),
                        Icon(Icons.forum_outlined, size: 48),
                        SizedBox(height: 16),
                        Center(child: Text('没有已加入的 Matrix 房间')),
                      ],
                    )
                  : ListView.separated(
                      itemCount: _rooms.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final room = _rooms[index];
                        final last = room.lastMessage;
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              room.name.isEmpty
                                  ? '#'
                                  : room.name.characters.first.toUpperCase(),
                            ),
                          ),
                          title: Text(
                            room.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: last == null
                              ? Text(
                                  room.roomId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : Row(
                                  children: <Widget>[
                                    if (last.encrypted) ...<Widget>[
                                      const Icon(Icons.lock_outline, size: 14),
                                      const SizedBox(width: 4),
                                    ],
                                    Expanded(
                                      child: Text(
                                        last.body,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                          trailing: room.unreadCount > 0
                              ? Badge(
                                  label: Text(
                                    room.unreadCount > 99
                                        ? '99+'
                                        : room.unreadCount.toString(),
                                  ),
                                )
                              : null,
                          onTap: () async {
                            await Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => MatrixRoomPage(
                                  client: _client,
                                  room: room,
                                ),
                              ),
                            );
                            if (mounted) {
                              await _loadRooms(showSpinner: false);
                            }
                          },
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogin() {
    return Scaffold(
      appBar: AppBar(title: const Text('Matrix 登录')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Icon(Icons.hub_outlined, size: 52),
                    const SizedBox(height: 20),
                    const Text(
                      '连接 Matrix homeserver',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _tokenMode
                          ? '适用于 SSO 登录后取得 access token 的服务器。Token 仅保存在系统安全存储；User ID 可由 /whoami 自动识别。'
                          : '使用 Matrix Client-Server API 登录，不会经过 Fluxdo 服务器。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _homeserverController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Homeserver',
                        hintText: 'https://matrix.org',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_tokenMode) ...<Widget>[
                      TextField(
                        controller: _userIdController,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'User ID（可选，仅用于校验）',
                          hintText: '@name:example.org',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _tokenController,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        onSubmitted: (_) => _signIn(),
                        decoration: const InputDecoration(
                          labelText: 'Access token',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ] else ...<Widget>[
                      TextField(
                        controller: _usernameController,
                        autofillHints: const <String>[AutofillHints.username],
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: '用户名 / Matrix ID',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        autofillHints: const <String>[AutofillHints.password],
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        onSubmitted: (_) => _signIn(),
                        decoration: const InputDecoration(
                          labelText: '密码',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('使用 Access Token'),
                      subtitle: const Text('密码登录不可用或 homeserver 使用 SSO 时启用'),
                      value: _tokenMode,
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _tokenMode = value),
                    ),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _signIn,
                      icon: _submitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login_rounded),
                      label: Text(_submitting ? '连接中…' : '登录'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MatrixRoomPage extends StatefulWidget {
  const MatrixRoomPage({
    super.key,
    required this.client,
    required this.room,
  });

  final MatrixClientService client;
  final MatrixRoomSummary room;

  @override
  State<MatrixRoomPage> createState() => _MatrixRoomPageState();
}

class _MatrixRoomPageState extends State<MatrixRoomPage> {
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
  bool _sending = false;
  String? _error;
  List<MatrixMessage> _messages = const <MatrixMessage>[];

  @override
  void initState() {
    super.initState();
    _loadMessages();
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

  Future<void> _loadMessages() async {
    try {
      final messages = await widget.client.loadMessages(widget.room.roomId);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _error = null;
      });
      if (messages.isNotEmpty) {
        unawaited(_markRead(messages.last.eventId));
      }
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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
      await _loadMessages();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showReactionPicker(MatrixMessage message) async {
    if (message.encrypted) return;
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
                '当前实验 UI 只发送 m.reaction；服务端聚合计数展示将在 SDK/E2EE 层接入后补齐。',
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.room.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _loading
                ? null
                : () {
                    setState(() => _loading = true);
                    _loadMessages();
                  },
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
                    onRefresh: _loadMessages,
                    child: ListView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final own = message.sender == currentUserId;
                        return _MatrixMessageBubble(
                          message: message,
                          own: own,
                          onLongPress: message.encrypted
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
                  ],
                  Flexible(child: Text(message.body)),
                ],
              ),
              const SizedBox(height: 3),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  time,
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
