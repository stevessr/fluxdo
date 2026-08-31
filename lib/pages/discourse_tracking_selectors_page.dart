import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discourse_providers.dart';
import '../services/discourse/user_preferences_api.dart';
import '../services/discourse/user_tracking_api.dart';
import '../services/preloaded_data_service.dart';
import '../services/toast_service.dart';

class DiscourseTrackingSelectorsPage extends ConsumerStatefulWidget {
  final String username;

  const DiscourseTrackingSelectorsPage({super.key, required this.username});

  @override
  ConsumerState<DiscourseTrackingSelectorsPage> createState() =>
      _DiscourseTrackingSelectorsPageState();
}

class _DiscourseTrackingSelectorsPageState
    extends ConsumerState<DiscourseTrackingSelectorsPage> {
  Map<String, dynamic>? _user;
  Map<String, dynamic> _options = const {};
  Map<String, dynamic> _site = const {};
  Map<String, dynamic> _settings = const {};
  final Map<String, dynamic> _pending = {};
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';
  String _tr(String zh, String en) => _isZh ? zh : en;

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
      final preload = PreloadedDataService();
      final results = await Future.wait<dynamic>([
        ref.read(discourseServiceProvider).getUserPreferences(widget.username),
        preload.getSite(),
        preload.getSiteSettings(),
      ]);
      final user = Map<String, dynamic>.from(results[0] as Map);
      if (!mounted) return;
      setState(() {
        _user = user;
        _options = user['user_option'] is Map
            ? Map<String, dynamic>.from(user['user_option'] as Map)
            : <String, dynamic>{};
        _site = results[1] is Map
            ? Map<String, dynamic>.from(results[1] as Map)
            : <String, dynamic>{};
        _settings = results[2] is Map
            ? Map<String, dynamic>.from(results[2] as Map)
            : <String, dynamic>{};
        _pending.clear();
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

  dynamic _value(String key) {
    if (_pending.containsKey(key)) return _pending[key];
    if (_options.containsKey(key)) return _options[key];
    return _user?[key];
  }

  Set<int> _intSet(String key) {
    final value = _value(key);
    if (value is! List) return <int>{};
    return value
        .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
        .whereType<int>()
        .toSet();
  }

  Set<String> _stringSet(String key) {
    final value = _value(key);
    if (value is! List) return <String>{};
    return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toSet();
  }

  List<Map<String, dynamic>> get _categories {
    final raw = _site['categories'];
    if (raw is! List) return const [];
    final result = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['id'] is num)
        .toList();
    result.sort((a, b) =>
        (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));
    return result;
  }

  List<String> get _categoryFields => [
        'watched_category_ids',
        'tracked_category_ids',
        'watched_first_post_category_ids',
        _settings['mute_all_categories_by_default'] == true
            ? 'regular_category_ids'
            : 'muted_category_ids',
      ];

  List<String> get _tagFields => const [
        'watched_tags',
        'tracked_tags',
        'watching_first_post_tags',
        'muted_tags',
      ];

  Set<int> _blockedCategoryIds(String field) {
    final result = <int>{};
    for (final other in _categoryFields) {
      if (other != field) result.addAll(_intSet(other));
    }
    return result;
  }

  Set<String> _blockedTags(String field) {
    final result = <String>{};
    for (final other in _tagFields) {
      if (other != field) result.addAll(_stringSet(other));
    }
    return result;
  }

  Future<void> _editCategories(String field, String title) async {
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (_) => _CategoryPickerDialog(
        title: title,
        categories: _categories,
        selected: _intSet(field),
        blocked: _blockedCategoryIds(field),
        zh: _isZh,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _pending[field] = result.toList()..sort());
  }

  Future<void> _editTags(String field, String title) async {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _TagPickerDialog(
        title: title,
        selected: _stringSet(field),
        blocked: _blockedTags(field),
        zh: _isZh,
      ),
    );
    if (result == null || !mounted) return;
    final values = result.toList()..sort();
    setState(() => _pending[field] = values);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_pending.isEmpty) {
      ToastService.showInfo(_tr('没有需要保存的更改', 'No changes to save'));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(discourseServiceProvider)
          .updateUserPreferences(widget.username, Map<String, dynamic>.from(_pending));
      await ref.read(currentUserProvider.notifier).refreshSilently(force: true);
      if (!mounted) return;
      ToastService.showSuccess(_tr('跟踪设置已保存', 'Tracking preferences saved'));
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
        title: Text(_tr('分类与标签跟踪', 'Category & tag tracking')),
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
              onPressed: _loading ? null : _save,
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

    final muteAll = _settings['mute_all_categories_by_default'] == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _section(
          _tr('分类', 'Categories'),
          [
            _categoryTile(
              'watched_category_ids',
              _tr('关注的分类', 'Watched categories'),
              Icons.notifications_active_outlined,
            ),
            _categoryTile(
              'tracked_category_ids',
              _tr('跟踪的分类', 'Tracked categories'),
              Icons.track_changes_outlined,
            ),
            _categoryTile(
              'watched_first_post_category_ids',
              _tr('只关注首帖的分类', 'First-post watched categories'),
              Icons.filter_1_outlined,
            ),
            _categoryTile(
              muteAll ? 'regular_category_ids' : 'muted_category_ids',
              muteAll
                  ? _tr('普通分类（其余默认静音）', 'Regular categories (others muted)')
                  : _tr('静音的分类', 'Muted categories'),
              muteAll ? Icons.volume_up_outlined : Icons.volume_off_outlined,
            ),
          ],
          subtitle: _tr(
            '同一分类只能处于一个跟踪级别，与 Discourse CategorySelector 的 blockedCategories 行为一致。',
            'A category can belong to only one tracking level, matching Discourse blockedCategories behavior.',
          ),
        ),
        if (_settings['tagging_enabled'] == true)
          _section(
            _tr('标签', 'Tags'),
            [
              _tagTile('watched_tags', _tr('关注的标签', 'Watched tags')),
              _tagTile('tracked_tags', _tr('跟踪的标签', 'Tracked tags')),
              _tagTile(
                'watching_first_post_tags',
                _tr('只关注首帖的标签', 'First-post watched tags'),
              ),
              _tagTile('muted_tags', _tr('静音的标签', 'Muted tags')),
            ],
            subtitle: _tr(
              '标签搜索直接使用 Discourse 官方 /tags/filter/search。',
              'Tag search uses Discourse’s official /tags/filter/search endpoint.',
            ),
          ),
        _section(_tr('优先级', 'Precedence'), [
          SwitchListTile.adaptive(
            value: _value('watched_precedence_over_muted') == true,
            onChanged: (value) =>
                setState(() => _pending['watched_precedence_over_muted'] = value),
            title: Text(
              _tr('关注优先于静音', 'Watched takes precedence over muted'),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _categoryTile(String field, String title, IconData icon) {
    final selected = _intSet(field);
    final names = selected.map(_categoryName).where((e) => e.isNotEmpty).toList();
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        names.isEmpty ? _tr('未选择', 'None selected') : names.join('、'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text('${selected.length}'),
      onTap: () => _editCategories(field, title),
    );
  }

  String _categoryName(int id) {
    for (final category in _categories) {
      if ((category['id'] as num?)?.toInt() == id) {
        return category['name']?.toString() ?? '#$id';
      }
    }
    return '#$id';
  }

  Widget _tagTile(String field, String title) {
    final selected = _stringSet(field).toList()..sort();
    return ListTile(
      leading: const Icon(Icons.tag),
      title: Text(title),
      subtitle: Text(
        selected.isEmpty ? _tr('未选择', 'None selected') : selected.join('、'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text('${selected.length}'),
      onTap: () => _editTags(field, title),
    );
  }

  Widget _section(String title, List<Widget> children, {String? subtitle}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: Column(children: _withDividers(children)),
            ),
          ],
        ),
      );

  List<Widget> _withDividers(List<Widget> children) {
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) out.add(const Divider(height: 1, indent: 16, endIndent: 16));
      out.add(children[i]);
    }
    return out;
  }
}

class _CategoryPickerDialog extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> categories;
  final Set<int> selected;
  final Set<int> blocked;
  final bool zh;

  const _CategoryPickerDialog({
    required this.title,
    required this.categories,
    required this.selected,
    required this.blocked,
    required this.zh,
  });

  @override
  State<_CategoryPickerDialog> createState() => _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends State<_CategoryPickerDialog> {
  late Set<int> _selected;
  String _query = '';

  String _tr(String zh, String en) => widget.zh ? zh : en;

  @override
  void initState() {
    super.initState();
    _selected = Set<int>.from(widget.selected);
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final visible = widget.categories.where((category) {
      final name = category['name']?.toString() ?? '';
      return query.isEmpty || name.toLowerCase().contains(query);
    }).toList();

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: 500,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: _tr('搜索分类', 'Search categories'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final category = visible[index];
                  final id = (category['id'] as num).toInt();
                  final blocked = widget.blocked.contains(id);
                  return CheckboxListTile(
                    value: _selected.contains(id),
                    onChanged: blocked
                        ? null
                        : (enabled) {
                            setState(() {
                              if (enabled == true) {
                                _selected.add(id);
                              } else {
                                _selected.remove(id);
                              }
                            });
                          },
                    title: Text(category['name']?.toString() ?? '#$id'),
                    subtitle: blocked
                        ? Text(_tr('已用于其他跟踪级别', 'Used by another tracking level'))
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: Text(_tr('确定', 'Done')),
        ),
      ],
    );
  }
}

class _TagPickerDialog extends ConsumerStatefulWidget {
  final String title;
  final Set<String> selected;
  final Set<String> blocked;
  final bool zh;

  const _TagPickerDialog({
    required this.title,
    required this.selected,
    required this.blocked,
    required this.zh,
  });

  @override
  ConsumerState<_TagPickerDialog> createState() => _TagPickerDialogState();
}

class _TagPickerDialogState extends ConsumerState<_TagPickerDialog> {
  final TextEditingController _controller = TextEditingController();
  late Set<String> _selected;
  List<Map<String, dynamic>> _results = const [];
  bool _searching = false;
  Object? _error;

  String _tr(String zh, String en) => widget.zh ? zh : en;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selected);
    Future.microtask(_search);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_searching) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await ref.read(discourseServiceProvider).searchPreferenceTags(
            _controller.text,
            selectedTags: {..._selected, ...widget.blocked},
          );
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final tag in _selected.toList()..sort())
                      InputChip(
                        label: Text(tag),
                        onDeleted: () => setState(() => _selected.remove(tag)),
                      ),
                  ],
                ),
              ),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: _tr('搜索标签', 'Search tags'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _searching ? null : _search,
                  icon: const Icon(Icons.arrow_forward),
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 8),
            if (_searching) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  _error.toString(),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final item = _results[index];
                  final name = item['name']?.toString() ?? '';
                  final blocked = widget.blocked.contains(name);
                  return CheckboxListTile(
                    value: _selected.contains(name),
                    onChanged: blocked || name.isEmpty
                        ? null
                        : (enabled) {
                            setState(() {
                              if (enabled == true) {
                                _selected.add(name);
                              } else {
                                _selected.remove(name);
                              }
                            });
                          },
                    title: Text(name),
                    subtitle: blocked
                        ? Text(_tr('已用于其他跟踪级别', 'Used by another tracking level'))
                        : item['count'] == null
                            ? null
                            : Text('${item['count']}'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: Text(_tr('确定', 'Done')),
        ),
      ],
    );
  }
}
