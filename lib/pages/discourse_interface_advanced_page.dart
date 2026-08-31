import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discourse_providers.dart';
import '../services/discourse/user_preferences_api.dart';
import '../services/preloaded_data_service.dart';
import '../services/toast_service.dart';

/// Native editor for the richer controls on Discourse's Preferences > Interface
/// page which depend on site-provided themes, palettes, and locales.
class DiscourseInterfaceAdvancedPage extends ConsumerStatefulWidget {
  final String username;

  const DiscourseInterfaceAdvancedPage({super.key, required this.username});

  @override
  ConsumerState<DiscourseInterfaceAdvancedPage> createState() =>
      _DiscourseInterfaceAdvancedPageState();
}

class _DiscourseInterfaceAdvancedPageState
    extends ConsumerState<DiscourseInterfaceAdvancedPage> {
  static const int _siteDefaultTheme = -999999;

  Map<String, dynamic>? _user;
  Map<String, dynamic> _options = const {};
  Map<String, dynamic> _site = const {};
  Map<String, dynamic> _settings = const {};
  final Map<String, dynamic> _pending = {};
  bool _loading = true;
  bool _saving = false;
  Object? _error;
  int _revision = 0;

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

  dynamic _value(String key) =>
      _pending.containsKey(key) ? _pending[key] : _options[key];

  void _set(String key, dynamic value) => setState(() => _pending[key] = value);

  int _intValue(String key, int fallback) {
    final value = _value(key);
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _stringValue(String key, String fallback) =>
      _value(key)?.toString() ?? fallback;

  List<Map<String, dynamic>> _maps(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<Map<String, dynamic>> get _themes => _maps(_site['user_themes']);

  List<Map<String, dynamic>> get _colorSchemes =>
      _maps(_site['user_color_schemes']);

  int get _selectedThemeId {
    final value = _value('theme_ids');
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is num) return first.toInt();
      final parsed = int.tryParse(first?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return _siteDefaultTheme;
  }

  Map<String, dynamic>? get _selectedTheme {
    final id = _selectedThemeId;
    for (final theme in _themes) {
      final themeId = theme['theme_id'];
      if (themeId is num && themeId.toInt() == id) return theme;
    }
    return null;
  }

  List<Map<String, dynamic>> _schemes({required bool dark}) {
    final selectedTheme = _selectedTheme;
    final selectedThemeId = _selectedThemeId;
    final limitToTheme = selectedTheme?['only_theme_color_schemes'] == true &&
        _colorSchemes.any(
          (scheme) =>
              (scheme['theme_id'] as num?)?.toInt() == selectedThemeId,
        );

    final result = _colorSchemes.where((scheme) {
      if ((scheme['is_dark'] == true) != dark) return false;
      if (limitToTheme &&
          (scheme['theme_id'] as num?)?.toInt() != selectedThemeId) {
        return false;
      }
      return scheme['id'] is num;
    }).toList();
    result.sort((a, b) =>
        (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));
    return result;
  }

  List<_LocaleOption> get _availableLocales {
    dynamic raw = _settings['available_locales'];
    if (raw is String && raw.isNotEmpty) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }
    if (raw is! List) return const [];
    final result = <_LocaleOption>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final value = entry['value']?.toString();
      if (value == null || value.isEmpty) continue;
      final label = entry['native_name']?.toString() ??
          entry['name']?.toString() ??
          value;
      result.add(_LocaleOption(value, label));
    }
    return result;
  }

  Set<String> get _understoodLanguages {
    final value = _value('understood_languages');
    if (value is List) {
      return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toSet();
    }
    if (value is String && value.isNotEmpty) {
      return value
          .split(RegExp(r'[,|\s]+'))
          .where((e) => e.isNotEmpty)
          .toSet();
    }
    return <String>{};
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
      await ref
          .read(discourseServiceProvider)
          .updateUserPreferences(widget.username, Map<String, dynamic>.from(_pending));
      await ref.read(currentUserProvider.notifier).refreshSilently(force: true);
      if (!mounted) return;
      ToastService.showSuccess(_tr('界面偏好已保存', 'Interface preferences saved'));
      await _load();
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetUserTips() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(discourseServiceProvider).updateUserPreferences(
        widget.username,
        {'skip_new_user_tips': false, 'seen_popups': null},
      );
      await ref.read(currentUserProvider.notifier).refreshSilently(force: true);
      if (!mounted) return;
      ToastService.showSuccess(_tr('新用户提示已重置', 'User tips reset'));
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
        title: Text(_tr('界面高级设置', 'Advanced interface')),
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        if (_themes.isNotEmpty || _colorSchemes.isNotEmpty) _appearanceSection(),
        _interactionSection(),
        if (_settings['content_localization_enabled'] == true &&
            _availableLocales.isNotEmpty)
          _contentLanguageSection(),
        if (_site['user_tips'] != null) _tipsSection(),
      ],
    );
  }

  Widget _section(String title, List<Widget> children, {String? subtitle}) {
    return Padding(
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
  }

  List<Widget> _withDividers(List<Widget> children) {
    final result = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) result.add(const Divider(height: 1, indent: 16, endIndent: 16));
      result.add(children[i]);
    }
    return result;
  }

  Widget _appearanceSection() {
    final themeId = _selectedThemeId;
    final lightSchemes = _schemes(dark: false);
    final darkSchemes = _schemes(dark: true);
    final lightId = _intValue('color_scheme_id', -1);
    final darkId = _intValue('dark_scheme_id', -1);

    return _section(
      _tr('主题与配色', 'Theme & color palettes'),
      [
        if (_themes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<int>(
              key: ValueKey('$_revision:theme:$themeId'),
              initialValue: _themes.any(
                        (t) => (t['theme_id'] as num?)?.toInt() == themeId,
                      )
                  ? themeId
                  : _siteDefaultTheme,
              decoration: InputDecoration(
                labelText: _tr('Discourse 主题', 'Discourse theme'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: _siteDefaultTheme,
                  child: Text(_tr('站点默认', 'Site default')),
                ),
                for (final theme in _themes)
                  if (theme['theme_id'] is num)
                    DropdownMenuItem(
                      value: (theme['theme_id'] as num).toInt(),
                      child: Text(theme['name']?.toString() ?? '#${theme['theme_id']}'),
                    ),
              ],
              onChanged: (value) {
                if (value == null) return;
                _set(
                  'theme_ids',
                  value == _siteDefaultTheme ? <int>[] : <int>[value],
                );
              },
            ),
          ),
        if (lightSchemes.isNotEmpty)
          _schemeDropdown(
            keyName: 'color_scheme_id',
            label: _tr('浅色配色方案', 'Light color palette'),
            currentId: lightId,
            schemes: lightSchemes,
          ),
        if (darkSchemes.isNotEmpty)
          _schemeDropdown(
            keyName: 'dark_scheme_id',
            label: _tr('深色配色方案', 'Dark color palette'),
            currentId: darkId,
            schemes: darkSchemes,
          ),
        _stringDropdown(
          'interface_color_mode',
          _tr('界面配色模式', 'Interface color mode'),
          [
            ('auto', _tr('跟随系统', 'Auto')),
            ('light', _tr('浅色', 'Light')),
            ('dark', _tr('深色', 'Dark')),
          ],
          fallback: 'auto',
        ),
      ],
      subtitle: _tr(
        '候选项直接来自当前 Discourse 站点的 user_themes 与 user_color_schemes。',
        'Choices come directly from this Discourse site’s user_themes and user_color_schemes.',
      ),
    );
  }

  Widget _schemeDropdown({
    required String keyName,
    required String label,
    required int currentId,
    required List<Map<String, dynamic>> schemes,
  }) {
    final selectable = schemes.any(
      (scheme) => (scheme['id'] as num?)?.toInt() == currentId,
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: DropdownButtonFormField<int>(
        key: ValueKey('$_revision:$keyName:$currentId:${_selectedThemeId}'),
        initialValue: selectable ? currentId : -1,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          DropdownMenuItem(value: -1, child: Text(_tr('主题默认', 'Theme default'))),
          for (final scheme in schemes)
            if (scheme['id'] is num)
              DropdownMenuItem(
                value: (scheme['id'] as num).toInt(),
                child: Text(scheme['name']?.toString() ?? '#${scheme['id']}'),
              ),
        ],
        onChanged: (value) {
          if (value != null) _set(keyName, value);
        },
      ),
    );
  }

  Widget _interactionSection() => _section(
        _tr('编辑与书签', 'Composer & bookmarks'),
        [
          _stringDropdown(
            'send_shortcut',
            _tr('发送快捷键', 'Send shortcut'),
            [
              ('enter', _tr('Enter 发送', 'Enter sends')),
              ('meta_enter', _tr('Ctrl/Cmd + Enter 发送', 'Ctrl/Cmd + Enter sends')),
            ],
            fallback: 'enter',
          ),
          _intDropdown(
            'bookmark_auto_delete_preference',
            _tr('书签提醒后的处理', 'After bookmark reminder'),
            [
              (0, _tr('从不自动删除书签', 'Never delete bookmark')),
              (3, _tr('仅清除提醒，保留书签', 'Clear reminder, keep bookmark')),
              (1, _tr('发送提醒后删除书签', 'Delete when reminder is sent')),
              (2, _tr('原作者回复后删除书签', 'Delete when owner replies')),
            ],
            fallback: 3,
          ),
        ],
      );

  Widget _contentLanguageSection() {
    final selected = _understoodLanguages;
    return _section(
      _tr('内容语言', 'Content languages'),
      [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _tr('我能理解的语言', 'Languages I understand'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final locale in _availableLocales)
                    FilterChip(
                      label: Text(locale.label),
                      selected: selected.contains(locale.value),
                      onSelected: (enabled) {
                        final next = Set<String>.from(selected);
                        if (enabled) {
                          next.add(locale.value);
                        } else {
                          next.remove(locale.value);
                        }
                        _set('understood_languages', next.toList());
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        SwitchListTile.adaptive(
          value: _value('automatically_translate') == true,
          onChanged: (value) => _set('automatically_translate', value),
          title: Text(_tr('自动翻译内容', 'Automatically translate content')),
        ),
        SwitchListTile.adaptive(
          value: _value('show_original_content') == true,
          onChanged: (value) => _set('show_original_content', value),
          title: Text(_tr('同时显示原文', 'Show original content')),
        ),
      ],
      subtitle: _tr(
        '语言列表与 Discourse 的 available_locales 保持一致。',
        'The language list follows Discourse available_locales.',
      ),
    );
  }

  Widget _tipsSection() => _section(
        _tr('用户提示', 'User tips'),
        [
          ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: Text(_tr('重新显示新用户提示', 'Show new-user tips again')),
            subtitle: Text(
              _tr(
                '清除 seen_popups，并重新启用新用户提示。',
                'Clears seen_popups and re-enables new-user tips.',
              ),
            ),
            trailing: const Icon(Icons.restart_alt),
            onTap: _saving ? null : _resetUserTips,
          ),
        ],
      );

  Widget _stringDropdown(
    String keyName,
    String label,
    List<(String, String)> values, {
    required String fallback,
  }) {
    final current = _stringValue(keyName, fallback);
    final value = values.any((entry) => entry.$1 == current) ? current : fallback;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$_revision:$keyName:$value'),
        initialValue: value,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [
          for (final entry in values)
            DropdownMenuItem(value: entry.$1, child: Text(entry.$2)),
        ],
        onChanged: (next) {
          if (next != null) _set(keyName, next);
        },
      ),
    );
  }

  Widget _intDropdown(
    String keyName,
    String label,
    List<(int, String)> values, {
    required int fallback,
  }) {
    final current = _intValue(keyName, fallback);
    final value = values.any((entry) => entry.$1 == current) ? current : fallback;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: DropdownButtonFormField<int>(
        key: ValueKey('$_revision:$keyName:$value'),
        initialValue: value,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [
          for (final entry in values)
            DropdownMenuItem(value: entry.$1, child: Text(entry.$2)),
        ],
        onChanged: (next) {
          if (next != null) _set(keyName, next);
        },
      ),
    );
  }
}

class _LocaleOption {
  final String value;
  final String label;

  const _LocaleOption(this.value, this.label);
}
