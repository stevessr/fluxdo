import 'package:flutter/material.dart';

import '../../services/matrix_client_service.dart';
import '../../services/messaging/matrix_homeserver_discovery.dart';
import 'matrix_room_page.dart';

class MatrixChatPage extends StatefulWidget {
  const MatrixChatPage({super.key});

  @override
  State<MatrixChatPage> createState() => _MatrixChatPageState();
}

class _MatrixChatPageState extends State<MatrixChatPage> {
  final MatrixClientService _client = MatrixClientService();
  final MatrixHomeserverDiscoveryService _discovery =
      MatrixHomeserverDiscoveryService();
  final TextEditingController _homeserverController = TextEditingController(
    text: 'https://matrix.org',
  );
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _discovering = false;
  bool _homeserverEdited = false;
  bool _tokenMode = false;
  String? _error;
  String? _discoveryStatus;
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

  String? get _matrixIdCandidate {
    final value = (_tokenMode
            ? _userIdController.text
            : _usernameController.text)
        .trim();
    return MatrixHomeserverDiscoveryService.serverNameFromInput(value) != null &&
            value.startsWith('@')
        ? value
        : null;
  }

  Future<MatrixHomeserverDiscoveryResult> _resolveHomeserver({
    required bool preferMatrixId,
  }) async {
    final matrixId = _matrixIdCandidate;
    final target = preferMatrixId && matrixId != null
        ? matrixId
        : _homeserverController.text.trim();

    if (target.isEmpty) {
      throw const MatrixHomeserverDiscoveryException(
        '请输入 Matrix ID、服务器域名或 homeserver URL。',
      );
    }

    if (mounted) {
      setState(() {
        _discovering = true;
        _error = null;
        _discoveryStatus = null;
      });
    }

    try {
      final result = await _discovery.discover(target);
      if (mounted) {
        _homeserverController.text = result.baseUrl;
        setState(() {
          _discoveryStatus = switch (result.source) {
            MatrixHomeserverDiscoverySource.wellKnown =>
              '已通过 .well-known 发现 ${result.baseUrl}',
            MatrixHomeserverDiscoverySource.directServerName =>
              '未提供 .well-known；已验证直连 ${result.baseUrl}',
            MatrixHomeserverDiscoverySource.explicitUrl =>
              '已验证 homeserver ${result.baseUrl}',
          };
        });
      }
      return result;
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Future<void> _discoverHomeserver() async {
    if (_discovering || _submitting) return;
    try {
      await _resolveHomeserver(preferMatrixId: _matrixIdCandidate != null);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _signIn() async {
    if (_submitting || _discovering) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // A full Matrix ID can safely drive server discovery as long as the user
      // has not explicitly overridden the homeserver field. Otherwise validate
      // the user's explicit endpoint before any credential-bearing request.
      final discovery = await _resolveHomeserver(
        preferMatrixId: !_homeserverEdited && _matrixIdCandidate != null,
      );

      final MatrixSession session;
      if (_tokenMode) {
        session = await _client.loginWithAccessToken(
          homeserver: discovery.baseUrl,
          userId: _userIdController.text,
          accessToken: _tokenController.text,
        );
      } else {
        session = await _client.loginWithPassword(
          homeserver: discovery.baseUrl,
          username: _usernameController.text,
          password: _passwordController.text,
        );
      }
      if (!mounted) return;
      _passwordController.clear();
      _tokenController.clear();
      setState(() => _session = session);
      await _loadRooms(showSpinner: false, forceFull: true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _loadRooms({
    bool showSpinner = true,
    bool forceFull = false,
  }) async {
    if (_session == null) return;
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final rooms = await _client.loadRooms(forceFull: forceFull);
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _error = null;
      });
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
      _discoveryStatus = null;
    });
  }

  Future<void> _handleMenu(String value) async {
    switch (value) {
      case 'full-sync':
        await _loadRooms(forceFull: true);
      case 'logout':
        await _logout();
    }
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
            tooltip: '增量同步',
            onPressed: _loading ? null : _loadRooms,
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => _handleMenu(value),
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
                value: 'full-sync',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.sync_rounded),
                  title: Text('重建房间同步缓存'),
                  subtitle: Text('丢弃 next_batch 并重新执行初始 /sync'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'logout',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout_rounded),
                  title: Text('退出 Matrix'),
                ),
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
                      '实验性 Matrix：增量 /sync、历史分页、已读、typing、reaction 聚合与 edit 已启用；E2EE 仍等待 SDK provider。',
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
                          title: Row(
                            children: <Widget>[
                              if (room.encrypted) ...<Widget>[
                                const Icon(Icons.lock_outline_rounded, size: 15),
                                const SizedBox(width: 5),
                              ],
                              Expanded(
                                child: Text(
                                  room.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          subtitle: last == null
                              ? Text(
                                  room.roomId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : Text(
                                  last.body,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
    final busy = _submitting || _discovering;
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
                          : '完整 Matrix ID 会先按规范自动发现 homeserver；显式填写的服务器则先验证 /_matrix/client/versions，再发送登录请求。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _homeserverController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enabled: !busy,
                      onChanged: (_) {
                        _homeserverEdited = true;
                        if (_discoveryStatus != null) {
                          setState(() => _discoveryStatus = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Homeserver / server name',
                        hintText: 'https://matrix.org 或 example.org',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: '自动发现并验证 homeserver',
                          onPressed: busy ? null : _discoverHomeserver,
                          icon: _discovering
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.travel_explore_rounded),
                        ),
                      ),
                    ),
                    if (_discoveryStatus != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            Icons.verified_outlined,
                            size: 17,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _discoveryStatus!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (_tokenMode) ...<Widget>[
                      TextField(
                        controller: _userIdController,
                        autocorrect: false,
                        enabled: !busy,
                        decoration: const InputDecoration(
                          labelText: 'User ID（可选，可用于自动发现/校验）',
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
                        enabled: !busy,
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
                        enabled: !busy,
                        decoration: const InputDecoration(
                          labelText: '用户名 / Matrix ID',
                          hintText: '@name:example.org',
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
                        enabled: !busy,
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
                      onChanged: busy
                          ? null
                          : (value) => setState(() {
                              _tokenMode = value;
                              _discoveryStatus = null;
                            }),
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
                      onPressed: busy ? null : _signIn,
                      icon: busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login_rounded),
                      label: Text(
                        _discovering
                            ? '发现服务器中…'
                            : _submitting
                            ? '连接中…'
                            : '登录',
                      ),
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
