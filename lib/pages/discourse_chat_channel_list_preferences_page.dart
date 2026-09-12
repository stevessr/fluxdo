import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discourse_providers.dart';
import '../services/discourse/user_preferences_api.dart';
import '../services/toast_service.dart';

/// Native counterpart for the channel list filter/sort preferences introduced
/// by Discourse Chat in September 2026.
///
/// Upstream persists one filter and one sort value for each list type:
/// public channels, direct messages, and starred channels. They are regular
/// `user_option` attributes and are saved through `/u/:username.json`.
class DiscourseChatChannelListPreferencesPage extends ConsumerStatefulWidget {
  final String username;

  const DiscourseChatChannelListPreferencesPage({
    super.key,
    required this.username,
  });

  @override
  ConsumerState<DiscourseChatChannelListPreferencesPage> createState() =>
      _DiscourseChatChannelListPreferencesPageState();
}

class _DiscourseChatChannelListPreferencesPageState
    extends ConsumerState<DiscourseChatChannelListPreferencesPage> {
  static const _filterValues = <String>[
    'all',
    'active',
    'unread',
    'mentions',
  ];
  static const _sortValues = <String>[
    'alphabetical',
    'recent_activity',
    'priority',
  ];

  static const _filterById = <int, String>{
    0: 'all',
    1: 'active',
    2: 'unread',
    3: 'mentions',
  };
  static const _sortById = <int, String>{
    0: 'alphabetical',
    1: 'recent_activity',
    2: 'priority',
  };

  Map<String, dynamic> _options = const {};
  final Map<String, dynamic> _pending = {};
  bool _loading = true;
  bool _saving = false;
  Object? _error;
  int _revision = 0;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  String _tr(String zh, String en) => _zh ? zh : en;

  bool get _supported => const <String>{
    'chat_channel_list_filter',
    'chat_channel_list_filter_dms',
    'chat_channel_list_filter_starred',
    'chat_channel_list_sort',
    'chat_channel_list_sort_dms',
    'chat_channel_list_sort_starred',
  }.any(_options.containsKey);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(discourseServiceProvider)
          .getUserPreferences(widget.username);
      final options = user['user_option'] is Map
          ? Map<String, dynamic>.from(user['user_option'] as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _options = options;
        _pending.clear();
        _revision++;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  String _enumValue(
    String key,
    String fallback,
    Map<int, String> numericValues,
    List<String> allowed,
  ) {
    final raw = _pending.containsKey(key) ? _pending[key] : _options[key];
    final value = switch (raw) {
      int id => numericValues[id],
      num id => numericValues[id.toInt()],
      _ => raw?.toString(),
    };
    return value != null && allowed.contains(value) ? value : fallback;
  }

  void _set(String key, String value) {
    setState(() => _pending[key] = value);
  }

  Future<void> _save() async {
    if (_saving || _pending.isEmpty) {
      if (_pending.isEmpty) {
        ToastService.showInfo(_tr('没有需要保存的更改', 'No changes to save'));
      }
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(discourseServiceProvider).updateUserPreferences(
        widget.username,
        Map<String, dynamic>.from(_pending),
      );
      await ref.read(currentUserProvider.notifier).refreshSilently(force: true);
      if (!mounted) return;
      ToastService.showSuccess(
        _tr('聊天频道列表偏好已保存', 'Chat channel list preferences saved'),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('聊天频道列表', 'Chat channel lists')),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton.icon(
              onPressed: _loading || !_supported ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_tr('保存', 'Save')),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 12),
              Text(_error.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(_tr('重试', 'Retry')),
              ),
            ],
          ),
        ),
      );
    }

    if (!_supported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.forum_outlined, size: 44),
              const SizedBox(height: 12),
              Text(
                _tr(
                  '当前 Discourse 站点未提供新版聊天频道列表偏好。',
                  'This Discourse site does not expose the new chat channel list preferences.',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _section(
          _tr('公开频道', 'Public channels'),
          filterKey: 'chat_channel_list_filter',
          sortKey: 'chat_channel_list_sort',
          defaultSort: 'alphabetical',
        ),
        _section(
          _tr('直接消息', 'Direct messages'),
          filterKey: 'chat_channel_list_filter_dms',
          sortKey: 'chat_channel_list_sort_dms',
          defaultSort: 'priority',
        ),
        _section(
          _tr('收藏频道', 'Starred channels'),
          filterKey: 'chat_channel_list_filter_starred',
          sortKey: 'chat_channel_list_sort_starred',
          defaultSort: 'alphabetical',
        ),
      ],
    );
  }

  Widget _section(
    String title, {
    required String filterKey,
    required String sortKey,
    required String defaultSort,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                _dropdown(
                  keyName: filterKey,
                  label: _tr('筛选', 'Filter'),
                  fallback: 'all',
                  allowed: _filterValues,
                  numericValues: _filterById,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _dropdown(
                  keyName: sortKey,
                  label: _tr('排序', 'Sort'),
                  fallback: defaultSort,
                  allowed: _sortValues,
                  numericValues: _sortById,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown({
    required String keyName,
    required String label,
    required String fallback,
    required List<String> allowed,
    required Map<int, String> numericValues,
  }) {
    final current = _enumValue(
      keyName,
      fallback,
      numericValues,
      allowed,
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$_revision:$keyName:$current'),
        initialValue: current,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final value in allowed)
            DropdownMenuItem(
              value: value,
              child: Text(_labelFor(value)),
            ),
        ],
        onChanged: (value) {
          if (value != null) _set(keyName, value);
        },
      ),
    );
  }

  String _labelFor(String value) => switch (value) {
    'all' => _tr('全部', 'All'),
    'active' => _tr('活跃', 'Active'),
    'unread' => _tr('未读', 'Unread'),
    'mentions' => _tr('提及', 'Mentions'),
    'alphabetical' => _tr('按名称', 'Alphabetical'),
    'recent_activity' => _tr('最近活动', 'Recent activity'),
    'priority' => _tr('优先级', 'Priority'),
    _ => value,
  };
}
