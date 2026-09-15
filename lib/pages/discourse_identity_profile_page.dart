import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discourse_providers.dart';
import '../services/discourse/user_preferences_api.dart';
import '../services/preloaded_data_service.dart';
import '../services/toast_service.dart';

/// Native editor for the identity/profile controls exposed by Discourse's
/// account and profile preference pages.
class DiscourseIdentityProfilePage extends ConsumerStatefulWidget {
  final String username;

  const DiscourseIdentityProfilePage({super.key, required this.username});

  @override
  ConsumerState<DiscourseIdentityProfilePage> createState() =>
      _DiscourseIdentityProfilePageState();
}

class _DiscourseIdentityProfilePageState
    extends ConsumerState<DiscourseIdentityProfilePage> {
  Map<String, dynamic>? _user;
  Map<String, dynamic> _options = const {};
  Map<String, dynamic> _site = const {};
  Map<String, dynamic> _siteSettings = const {};
  final Map<String, dynamic> _pending = {};
  Map<String, dynamic> _userFields = {};
  Map<String, dynamic>? _status;
  bool _userFieldsTouched = false;
  bool _statusTouched = false;
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
      final service = ref.read(discourseServiceProvider);
      final preload = PreloadedDataService();
      final results = await Future.wait<dynamic>([
        service.getUserPreferences(widget.username),
        preload.getSite(),
        preload.getSiteSettings(),
      ]);
      final user = Map<String, dynamic>.from(results[0] as Map);
      final options = user['user_option'] is Map
          ? Map<String, dynamic>.from(user['user_option'] as Map)
          : <String, dynamic>{};
      final site = results[1] is Map
          ? Map<String, dynamic>.from(results[1] as Map)
          : <String, dynamic>{};
      final settings = results[2] is Map
          ? Map<String, dynamic>.from(results[2] as Map)
          : <String, dynamic>{};
      final userFields = user['user_fields'] is Map
          ? Map<String, dynamic>.from(user['user_fields'] as Map)
          : <String, dynamic>{};
      final status = user['status'] is Map
          ? Map<String, dynamic>.from(user['status'] as Map)
          : null;

      if (!mounted) return;
      setState(() {
        _user = user;
        _options = options;
        _site = site;
        _siteSettings = settings;
        _pending.clear();
        _userFields = userFields;
        _status = status;
        _userFieldsTouched = false;
        _statusTouched = false;
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

  dynamic _value(String key) {
    if (_pending.containsKey(key)) return _pending[key];
    if (_options.containsKey(key)) return _options[key];
    return _user?[key];
  }

  String _string(String key) => _value(key)?.toString() ?? '';

  bool _bool(String key, [bool fallback = false]) {
    final value = _value(key);
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value == 'true' || value == '1';
    return fallback;
  }

  void _set(String key, dynamic value) {
    setState(() => _pending[key] = value);
  }

  bool _capability(String key, {bool fallback = true}) {
    final value = _user?[key];
    return value is bool ? value : fallback;
  }

  bool get _isStaff =>
      _user?['admin'] == true || _user?['moderator'] == true || _user?['staff'] == true;

  List<Map<String, dynamic>> get _groups {
    final raw = _user?['visibleGroups'] ??
        _user?['visible_groups'] ??
        _user?['groups'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<String> get _availableTitles {
    final titles = <String>{};
    for (final group in _groups) {
      final title = group['title']?.toString().trim();
      if (title != null && title.isNotEmpty) titles.add(title);
    }
    final badges = _user?['badges'];
    if (badges is List) {
      for (final badge in badges.whereType<Map>()) {
        if (badge['allow_title'] == true) {
          final name = badge['name']?.toString().trim();
          if (name != null && name.isNotEmpty) titles.add(name);
        }
      }
    }
    final current = _string('title').trim();
    if (current.isNotEmpty) titles.add(current);
    final result = titles.toList()..sort();
    return result;
  }

  List<Map<String, dynamic>> get _availablePrimaryGroups {
    return _groups.where((group) {
      if (group['automatic'] != true) return true;
      final name = group['name']?.toString();
      return name == 'moderators';
    }).toList();
  }

  List<Map<String, dynamic>> get _availableFlairs => _groups
      .where((group) => (group['flair_url']?.toString().isNotEmpty ?? false))
      .toList();

  List<Map<String, dynamic>> get _siteUserFields {
    final raw = _site['user_fields'];
    if (raw is! List) return const [];
    final fields = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((field) => _isStaff || field['editable'] == true)
        .toList();
    fields.sort((a, b) {
      final ap = (a['position'] as num?)?.toInt() ?? 0;
      final bp = (b['position'] as num?)?.toInt() ?? 0;
      return ap.compareTo(bp);
    });
    return fields;
  }

  Future<void> _save() async {
    if (_saving || _user == null) return;

    for (final field in _siteUserFields) {
      if (field['required'] != true) continue;
      final id = field['id']?.toString();
      if (id == null) continue;
      final value = _userFields[id];
      final missing = value == null ||
          (value is String && value.trim().isEmpty) ||
          (value is List && value.isEmpty) ||
          (field['field_type'] == 'confirm' && value != true);
      if (missing) {
        ToastService.showError(
          _tr(
            '请填写必填资料：${field['name'] ?? id}',
            'Please complete required field: ${field['name'] ?? id}',
          ),
        );
        return;
      }
    }

    final payload = Map<String, dynamic>.from(_pending);
    if (_userFieldsTouched) payload['user_fields'] = _userFields;
    if (_statusTouched) payload['status'] = _status;
    if (payload.isEmpty) {
      ToastService.showSuccess(_tr('没有需要保存的更改', 'No changes to save'));
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(discourseServiceProvider)
          .updateUserPreferences(widget.username, payload);
      await ref.read(currentUserProvider.notifier).refreshSilently(force: true);
      if (!mounted) return;
      ToastService.showSuccess(_tr('身份与个人资料已保存', 'Identity and profile saved'));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('身份与个人资料', 'Identity & profile')),
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
        _identitySection(),
        _statusSection(),
        _profileSection(),
        if (_siteUserFields.isNotEmpty) _customFieldsSection(),
      ],
    );
  }

  Widget _section(String title, List<Widget> children, {String? subtitle}) {
    final theme = Theme.of(context);
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
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: theme.textTheme.bodySmall),
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

  Widget _identitySection() {
    final titles = _availableTitles;
    final primaryGroups = _availablePrimaryGroups;
    final flairs = _availableFlairs;
    final currentTitle = _string('title');
    final primaryGroupId = _value('primary_group_id') is num
        ? (_value('primary_group_id') as num).toInt()
        : int.tryParse(_value('primary_group_id')?.toString() ?? '');
    final flairGroupId = _value('flair_group_id') is num
        ? (_value('flair_group_id') as num).toInt()
        : int.tryParse(_value('flair_group_id')?.toString() ?? '');
    final canSelectPrimary =
        _siteSettings['user_selected_primary_groups'] == true && primaryGroups.isNotEmpty;

    return _section(
      _tr('身份', 'Identity'),
      [
        if (titles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<String?>(
              key: ValueKey('$_revision:title:$currentTitle'),
              initialValue: currentTitle.isEmpty ? null : currentTitle,
              decoration: InputDecoration(
                labelText: _tr('头衔', 'Title'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(_tr('无头衔', 'No title')),
                ),
                for (final title in titles)
                  DropdownMenuItem<String?>(value: title, child: Text(title)),
              ],
              onChanged: (value) => _set('title', value ?? ''),
            ),
          )
        else
          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: Text(_tr('头衔', 'Title')),
            subtitle: Text(
              currentTitle.isEmpty
                  ? _tr('当前没有可选择的头衔', 'No selectable titles are available')
                  : currentTitle,
            ),
          ),
        if (canSelectPrimary)
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<int?>(
              key: ValueKey('$_revision:primary:$primaryGroupId'),
              initialValue: primaryGroups.any((g) => g['id'] == primaryGroupId)
                  ? primaryGroupId
                  : null,
              decoration: InputDecoration(
                labelText: _tr('主要群组', 'Primary group'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<int?>(
                  value: null,
                  child: Text(_tr('无主要群组', 'No primary group')),
                ),
                for (final group in primaryGroups)
                  if (group['id'] is num)
                    DropdownMenuItem<int?>(
                      value: (group['id'] as num).toInt(),
                      child: Text(group['name']?.toString() ?? '#${group['id']}'),
                    ),
              ],
              onChanged: (value) => _set('primary_group_id', value),
            ),
          ),
        if (flairs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<int?>(
              key: ValueKey('$_revision:flair:$flairGroupId'),
              initialValue: flairs.any((g) => g['id'] == flairGroupId)
                  ? flairGroupId
                  : null,
              decoration: InputDecoration(
                labelText: _tr('资质 / Flair', 'Flair'),
                helperText: _tr('来自你所属且提供 Flair 的群组', 'From groups you belong to that provide flair'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<int?>(
                  value: null,
                  child: Text(_tr('不显示资质', 'No flair')),
                ),
                for (final group in flairs)
                  if (group['id'] is num)
                    DropdownMenuItem<int?>(
                      value: (group['id'] as num).toInt(),
                      child: Text(group['name']?.toString() ?? '#${group['id']}'),
                    ),
              ],
              onChanged: (value) => _set('flair_group_id', value),
            ),
          ),
      ],
      subtitle: _tr(
        '选项来自 Discourse 返回的群组与徽章权限，不允许凭空设置未获得的头衔或资质。',
        'Options are derived from Discourse group and badge permissions, so unavailable titles or flair cannot be invented.',
      ),
    );
  }

  Widget _statusSection() {
    if (_siteSettings['enable_user_status'] != true) {
      return _section(_tr('自定义状态', 'Custom status'), [
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(_tr('站点未启用自定义状态', 'User status is disabled by this site')),
        ),
      ]);
    }

    final status = _status;
    final description = status?['description']?.toString() ?? '';
    final emoji = status?['emoji']?.toString() ?? '';
    final endsAt = DateTime.tryParse(status?['ends_at']?.toString() ?? '');

    return _section(_tr('自定义状态', 'Custom status'), [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextFormField(
          key: ValueKey('$_revision:status-description:$description'),
          initialValue: description,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: _tr('状态文字', 'Status description'),
            hintText: _tr('你正在做什么？', 'What are you doing?'),
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) {
            setState(() {
              _status ??= <String, dynamic>{};
              _status!['description'] = value;
              _status!['emoji'] ??= 'speech_balloon';
              _statusTouched = true;
            });
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextFormField(
          key: ValueKey('$_revision:status-emoji:$emoji'),
          initialValue: emoji,
          decoration: InputDecoration(
            labelText: _tr('Emoji shortcode', 'Emoji shortcode'),
            hintText: 'speech_balloon',
            helperText: _tr(
              '填写 Discourse emoji 名称，不需要冒号，例如 coffee。',
              'Use the Discourse emoji name without colons, for example coffee.',
            ),
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) {
            setState(() {
              _status ??= <String, dynamic>{};
              _status!['emoji'] = value.trim();
              _statusTouched = true;
            });
          },
        ),
      ),
      ListTile(
        leading: const Icon(Icons.schedule_outlined),
        title: Text(_tr('自动清除时间', 'Clear status at')),
        subtitle: Text(
          endsAt == null
              ? _tr('永不自动清除', 'Never')
              : MaterialLocalizations.of(context).formatFullDate(endsAt.toLocal()),
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            if (endsAt != null)
              IconButton(
                tooltip: _tr('设为永久', 'Never clear'),
                onPressed: () {
                  setState(() {
                    _status ??= <String, dynamic>{};
                    _status!['ends_at'] = null;
                    _statusTouched = true;
                  });
                },
                icon: const Icon(Icons.all_inclusive),
              ),
            IconButton(
              tooltip: _tr('选择时间', 'Choose time'),
              onPressed: _pickStatusEnd,
              icon: const Icon(Icons.edit_calendar_outlined),
            ),
          ],
        ),
      ),
      if (status != null)
        ListTile(
          leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
          title: Text(
            _tr('清除自定义状态', 'Clear custom status'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          onTap: () {
            setState(() {
              _status = null;
              _statusTouched = true;
              _revision++;
            });
          },
        ),
    ]);
  }

  Future<void> _pickStatusEnd() async {
    final current = DateTime.tryParse(_status?['ends_at']?.toString() ?? '')?.toLocal();
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    final local = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      _status ??= <String, dynamic>{};
      _status!['ends_at'] = local.toUtc().toIso8601String();
      _statusTouched = true;
    });
  }

  Widget _profileSection() {
    final allowHide = _siteSettings['allow_users_to_hide_profile'] == true;
    return _section(_tr('个人资料', 'Profile'), [
      if (_capability('can_change_bio'))
        _textField('bio_raw', _tr('个人简介', 'Bio'), maxLines: 6),
      _textField('timezone', _tr('时区', 'Timezone'), hint: 'Asia/Shanghai'),
      if (_capability('can_change_location'))
        _textField('location', _tr('地点', 'Location')),
      if (_capability('can_change_website'))
        _textField(
          'website',
          _tr('网站', 'Website'),
          keyboardType: TextInputType.url,
        ),
      _textField('date_of_birth', _tr('生日', 'Date of birth'), hint: 'YYYY-MM-DD'),
      if (allowHide)
        SwitchListTile.adaptive(
          value: _bool('hide_profile'),
          onChanged: (value) => _set('hide_profile', value),
          title: Text(_tr('隐藏公开个人资料', 'Hide public profile')),
        ),
    ]);
  }

  Widget _textField(
    String key,
    String label, {
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextFormField(
        key: ValueKey('$_revision:profile:$key'),
        initialValue: _string(key),
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) => _set(key, value),
      ),
    );
  }

  Widget _customFieldsSection() => _section(
        _tr('站点自定义资料', 'Site custom profile fields'),
        [for (final field in _siteUserFields) _customField(field)],
        subtitle: _tr(
          '这些字段由 Discourse 站点定义，Fluxdo 会按字段类型原生编辑并整体保存 user_fields。',
          'These fields are defined by the Discourse site and are saved natively as user_fields.',
        ),
      );

  Widget _customField(Map<String, dynamic> field) {
    final id = field['id']?.toString() ?? '';
    final name = field['name']?.toString() ?? id;
    final description = field['description']?.toString();
    final type = field['field_type']?.toString() ?? 'text';
    final required = field['required'] == true;
    final label = required ? '$name *' : name;
    final value = _userFields[id];
    final options = field['options'] is List
        ? (field['options'] as List).map((e) => e.toString()).toList()
        : const <String>[];

    void update(dynamic next) {
      setState(() {
        _userFields[id] = next;
        _userFieldsTouched = true;
      });
    }

    if (type == 'confirm') {
      return SwitchListTile.adaptive(
        value: value == true,
        onChanged: update,
        title: Text(label),
        subtitle: description == null || description.isEmpty ? null : Text(description),
      );
    }

    if (type == 'dropdown' && options.isNotEmpty) {
      final current = value?.toString();
      return Padding(
        padding: const EdgeInsets.all(16),
        child: DropdownButtonFormField<String>(
          key: ValueKey('$_revision:user-field:$id:$current'),
          initialValue: options.contains(current) ? current : null,
          decoration: InputDecoration(
            labelText: label,
            helperText: description,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final option in options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: update,
        ),
      );
    }

    if (type == 'multiselect' && options.isNotEmpty) {
      final selected = value is List
          ? value.map((e) => e.toString()).toSet()
          : <String>{};
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final option in options)
                  FilterChip(
                    label: Text(option),
                    selected: selected.contains(option),
                    onSelected: (enabled) {
                      final next = Set<String>.from(selected);
                      if (enabled) {
                        next.add(option);
                      } else {
                        next.remove(option);
                      }
                      update(next.toList());
                    },
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextFormField(
        key: ValueKey('$_revision:user-field:$id'),
        initialValue: value?.toString() ?? '',
        minLines: type == 'textarea' ? 3 : 1,
        maxLines: type == 'textarea' ? 6 : 1,
        decoration: InputDecoration(
          labelText: label,
          helperText: description,
          hintText: type == 'date' ? 'YYYY-MM-DD' : null,
          border: const OutlineInputBorder(),
        ),
        onChanged: (next) => update(next.trim().isEmpty ? null : next),
      ),
    );
  }
}
