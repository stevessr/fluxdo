import 'package:flutter/material.dart';

import '../services/discourse/discourse_service.dart';
import '../services/preloaded_data_service.dart';
import '../utils/time_utils.dart';
import 'topic_detail_page/topic_detail_page.dart';

/// Discourse AI Bot 官方私信会话入口。
///
/// 这里只负责 AI 插件特有的“新会话 / Agent+LLM 选择 / 历史 / 收藏”。
/// 对话内容本身仍然进入 [TopicDetailPage]，与 Discourse 一样复用 PM Topic/Post，
/// 避免客户端形成第二套不兼容的消息协议。
class AiBotConversationsPage extends StatefulWidget {
  const AiBotConversationsPage({super.key});

  @override
  State<AiBotConversationsPage> createState() =>
      _AiBotConversationsPageState();
}

class _AiBotConversationsPageState extends State<AiBotConversationsPage> {
  static const int _perPage = 40;

  final DiscourseService _service = DiscourseService();
  final PreloadedDataService _preloaded = PreloadedDataService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<AiBotConversation> _conversations = [];
  List<AiBotAgent> _agents = const [];
  List<AiBotLlm> _llms = const [];
  AiBotAgent? _selectedAgent;
  AiBotLlm? _selectedLlm;

  int _page = 0;
  int _minPmLength = 10;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  bool _pluginUnavailable = false;
  Object? _error;
  final Set<int> _starringTopicIds = {};

  bool get _isZh =>
      Localizations.localeOf(context).languageCode.toLowerCase().startsWith('zh');

  String _text(String zh, String en) => _isZh ? zh : en;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !_hasMore || _loadingMore) return;
    if (_scrollController.position.extentAfter < 500) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _pluginUnavailable = false;
      });
    }

    try {
      await Future.wait([_loadBotOptions(), _loadMinLength()]);
      final result = await _service.getAiBotConversations(
        page: 0,
        perPage: _perPage,
      );
      if (!mounted) return;
      setState(() {
        _conversations
          ..clear()
          ..addAll(result.conversations);
        _page = 0;
        _hasMore = result.hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        // Discourse 未安装 / 未启用 discourse-ai 时通常为 404；这里用字符串
        // 兜底，因为统一 API 层可能已把 DioException 包装成 Exception。
        _pluginUnavailable = e.toString().contains('404');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMinLength() async {
    await _preloaded.ensureLoaded();
    final settings = _preloaded.siteSettingsSync;
    final value = settings?['min_personal_message_post_length'];
    final parsed = switch (value) {
      int v => v,
      String v => int.tryParse(v),
      _ => null,
    };
    if (parsed != null && parsed > 0) _minPmLength = parsed;
  }

  Future<void> _loadBotOptions() async {
    await _preloaded.ensureLoaded();
    final currentUser = _preloaded.currentUserSync;
    if (currentUser == null) return;

    final rawAgents = currentUser['ai_enabled_agents'] as List<dynamic>? ?? const [];
    final rawBots =
        currentUser['ai_enabled_chat_bots'] as List<dynamic>? ?? const [];

    final agents = rawAgents
        .whereType<Map<String, dynamic>>()
        .map(AiBotAgent.fromJson)
        .where((agent) => agent.id > 0 && agent.allowPersonalMessages)
        .toList();
    final llms = rawBots
        .whereType<Map<String, dynamic>>()
        .map(AiBotLlm.fromJson)
        .where((bot) => !bot.isAgent && bot.id > 0 && bot.username.isNotEmpty)
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    if (!mounted) return;
    setState(() {
      _agents = agents;
      _llms = llms;
      if (_selectedAgent == null ||
          !agents.any((agent) => agent.id == _selectedAgent!.id)) {
        _selectedAgent = agents.isEmpty ? null : agents.first;
      }
      if (_selectedLlm == null ||
          !llms.any((llm) => llm.id == _selectedLlm!.id)) {
        _selectedLlm = llms.isEmpty ? null : llms.first;
      }
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final result = await _service.getAiBotConversations(
        page: nextPage,
        perPage: _perPage,
      );
      if (!mounted) return;
      final known = _conversations.map((e) => e.id).toSet();
      setState(() {
        _conversations.addAll(
          result.conversations.where((item) => !known.contains(item.id)),
        );
        _page = nextPage;
        _hasMore = result.hasMore;
      });
    } catch (e) {
      if (mounted) _showMessage(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String? get _targetUsername {
    final agent = _selectedAgent;
    if (agent != null && agent.forceDefaultLlm) {
      final username = agent.username?.trim();
      return username != null && username.isNotEmpty ? username : null;
    }

    final llmUsername = _selectedLlm?.username.trim();
    if (llmUsername != null && llmUsername.isNotEmpty) return llmUsername;

    final agentUsername = agent?.username?.trim();
    if (agentUsername != null && agentUsername.isNotEmpty) return agentUsername;
    return null;
  }

  Future<void> _submit() async {
    if (_sending) return;
    final raw = _inputController.text.trim();
    if (raw.length < _minPmLength) {
      _showMessage(
        _text(
          '至少输入 $_minPmLength 个字符',
          'Please enter at least $_minPmLength characters',
        ),
      );
      return;
    }

    final targetUsername = _targetUsername;
    if (targetUsername == null) {
      _showMessage(
        _text(
          '当前账号没有可用的 AI Bot / Agent',
          'No AI Bot or Agent is available for this account',
        ),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final result = await _service.createAiBotConversation(
        raw: raw,
        targetUsername: targetUsername,
        aiAgentId: _selectedAgent?.id,
      );
      if (!mounted) return;
      _inputController.clear();

      // 官方新会话本质是 PM Topic。先刷新索引，让返回后列表立即出现，
      // 再进入通用 TopicDetailPage 继续对话。
      _refreshInBackground();
      await _openConversation(
        AiBotConversation(
          id: result.topicId,
          title: _text('AI 对话', 'AI conversation'),
          slug: result.topicSlug ?? '',
          postsCount: 1,
          lastPostedAt: null,
          starred: false,
        ),
      );
    } catch (e) {
      if (mounted) _showMessage(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _refreshInBackground() async {
    try {
      final result = await _service.getAiBotConversations(
        page: 0,
        perPage: _perPage,
      );
      if (!mounted) return;
      setState(() {
        _conversations
          ..clear()
          ..addAll(result.conversations);
        _page = 0;
        _hasMore = result.hasMore;
      });
    } catch (_) {
      // 创建已经成功时，索引刷新失败不应阻止进入会话。
    }
  }

  Future<void> _toggleStar(AiBotConversation item) async {
    if (_starringTopicIds.contains(item.id)) return;
    setState(() => _starringTopicIds.add(item.id));
    try {
      final starred = await _service.setAiBotConversationStarred(
        topicId: item.id,
        starred: !item.starred,
      );
      if (!mounted) return;
      final index = _conversations.indexWhere((e) => e.id == item.id);
      if (index < 0) return;
      setState(() {
        _conversations[index] = _conversations[index].copyWith(
          starred: starred,
          starredAt: starred ? DateTime.now() : null,
        );
        // 对齐 Discourse：收藏会话优先显示；取消收藏后按最后回复时间归位。
        _conversations.sort((a, b) {
          if (a.starred != b.starred) return a.starred ? -1 : 1;
          if (a.starred && b.starred) {
            final aTime = a.starredAt;
            final bTime = b.starredAt;
            if (aTime != null && bTime != null) return bTime.compareTo(aTime);
          }
          final aTime = a.lastPostedAt;
          final bTime = b.lastPostedAt;
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime);
        });
      });
    } catch (e) {
      if (mounted) _showMessage(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _starringTopicIds.remove(item.id));
    }
  }

  Future<void> _openConversation(AiBotConversation item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TopicDetailPage(
          topicId: item.id,
          initialTitle: item.title,
        ),
      ),
    );
    if (mounted) _refreshInBackground();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyError(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    if (raw.contains('404')) {
      return _text(
        '当前站点没有启用 Discourse AI Bot',
        'Discourse AI Bot is not enabled on this site',
      );
    }
    return raw.isEmpty ? _text('操作失败', 'Operation failed') : raw;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_text('AI 聊天', 'AI chat')),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadInitial,
            tooltip: _text('刷新', 'Refresh'),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pluginUnavailable) {
      return _buildUnavailable();
    }

    if (_error != null && _conversations.isEmpty) {
      return _buildError();
    }

    return RefreshIndicator(
      onRefresh: _loadInitial,
      child: ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildComposer(),
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                _text('历史会话', 'Conversations'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_conversations.isNotEmpty)
                Text(
                  _text('${_conversations.length} 个', '${_conversations.length}'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_conversations.isEmpty)
            _buildEmpty()
          else
            ..._conversations.map(_buildConversationTile),
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final theme = Theme.of(context);
    final agent = _selectedAgent;
    final showAgentSelector = _agents.length > 1;
    final showLlmSelector =
        _llms.length > 1 && !(agent?.forceDefaultLlm ?? false);
    final noBot = _targetUsername == null;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.smart_toy_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _text('开始新的 AI 对话', 'Start a new AI conversation'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _inputController,
              enabled: !_sending && !noBot,
              minLines: 2,
              maxLines: 8,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: _text('向 AI 提问…', 'Ask the AI…'),
                filled: true,
                fillColor: theme.colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) {
                // 移动端换行键不自动发送；桌面端用户可直接点右侧发送按钮，
                // 与官方“Shift+Enter 换行”相比更不容易误发长内容。
              },
            ),
            if (showAgentSelector || showLlmSelector) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (showAgentSelector) _buildAgentDropdown(),
                  if (showLlmSelector) _buildLlmDropdown(),
                ],
              ),
            ],
            if (agent != null && agent.description.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                agent.description.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (noBot) ...[
              const SizedBox(height: 12),
              Text(
                _text(
                  '此账号当前没有可用于私信的 AI Agent / LLM。',
                  'This account currently has no AI Agent / LLM available for personal messages.',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _text(
                      'AI 可能会犯错，请核对重要信息。',
                      'AI can make mistakes. Check important information.',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _sending || noBot ? null : _submit,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(_text('发送', 'Send')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentDropdown() {
    return DropdownMenu<int>(
      initialSelection: _selectedAgent?.id,
      label: Text(_text('Agent', 'Agent')),
      leadingIcon: const Icon(Icons.smart_toy_outlined),
      dropdownMenuEntries: [
        for (final agent in _agents)
          DropdownMenuEntry<int>(value: agent.id, label: agent.name),
      ],
      onSelected: (id) {
        if (id == null) return;
        setState(() {
          _selectedAgent = _agents.firstWhere((agent) => agent.id == id);
        });
      },
    );
  }

  Widget _buildLlmDropdown() {
    return DropdownMenu<int>(
      initialSelection: _selectedLlm?.id,
      label: Text(_text('模型', 'Model')),
      leadingIcon: const Icon(Icons.public_rounded),
      dropdownMenuEntries: [
        for (final llm in _llms)
          DropdownMenuEntry<int>(value: llm.id, label: llm.displayName),
      ],
      onSelected: (id) {
        if (id == null) return;
        setState(() {
          _selectedLlm = _llms.firstWhere((llm) => llm.id == id);
        });
      },
    );
  }

  Widget _buildConversationTile(AiBotConversation item) {
    final theme = Theme.of(context);
    final starring = _starringTopicIds.contains(item.id);
    final time = TimeUtils.formatRelativeTime(item.lastPostedAt);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _openConversation(item),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.smart_toy_outlined,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          item.title.isEmpty ? _text('AI 对话', 'AI conversation') : item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            if (item.postsCount > 0)
              _text('${item.postsCount} 条消息', '${item.postsCount} messages'),
            if (time.isNotEmpty) time,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          onPressed: starring ? null : () => _toggleStar(item),
          tooltip: item.starred
              ? _text('取消收藏', 'Unstar')
              : _text('收藏', 'Star'),
          icon: starring
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  item.starred ? Icons.star_rounded : Icons.star_border_rounded,
                  color: item.starred ? theme.colorScheme.primary : null,
                ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.forum_outlined, size: 40),
          const SizedBox(height: 12),
          Text(_text('还没有 AI 对话', 'No AI conversations yet')),
          const SizedBox(height: 4),
          Text(
            _text(
              '在上方输入问题即可开始。',
              'Ask a question above to get started.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildUnavailable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smart_toy_outlined, size: 52),
            const SizedBox(height: 16),
            Text(
              _text('AI Bot 不可用', 'AI Bot unavailable'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _text(
                '当前站点未启用 Discourse AI Bot，或当前账号没有使用权限。',
                'Discourse AI Bot is disabled on this site, or this account does not have access.',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: _loadInitial,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_text('重试', 'Retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 12),
            Text(
              _friendlyError(_error!),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _loadInitial,
              child: Text(_text('重试', 'Retry')),
            ),
          ],
        ),
      ),
    );
  }
}
