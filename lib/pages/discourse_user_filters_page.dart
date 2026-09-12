import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discourse_providers.dart';
import '../services/discourse/user_people_preferences_api.dart';
import '../services/discourse/user_preferences_api.dart';
import '../services/toast_service.dart';

class DiscourseUserFiltersPage extends ConsumerStatefulWidget {
  final String username;

  const DiscourseUserFiltersPage({super.key, required this.username});

  @override
  ConsumerState<DiscourseUserFiltersPage> createState() =>
      _DiscourseUserFiltersPageState();
}

class _DiscourseUserFiltersPageState
    extends ConsumerState<DiscourseUserFiltersPage> {
  Map<String, dynamic>? _user;
  Map<String, dynamic> _options = const {};
  Set<String> _muted = {};
  Set<String> _ignored = {};
  Set<String> _allowedPm = {};
  bool _allowPrivateMessages = true;
  bool _enableAllowedPmUsers = false;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  Object? _error;

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';
  String _tr(String zh, String en) => _isZh ? zh : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Set<String> _names(dynamic value) {
    final values = value is List
        ? value.map((e) => e.toString())
        : value is String
            ? value.split(',')
            : const <String>[];
    return values.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
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
        _user = user;
        _options = options;
        _muted = _names(user['muted_usernames']);
        _ignored = _names(user['ignored_usernames']);
        _allowedPm = _names(user['allowed_pm_usernames']);
        _allowPrivateMessages = options['allow_private_messages'] != false;
        _enableAllowedPmUsers = options['enable_allowed_pm_users'] == true;
        _dirty = false;
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

  Future<void> _save() async {
    if (_saving || !_dirty) {
      if (!_dirty) {
        ToastService.showInfo(_tr('没有需要保存的更改', 'No changes to save'));
      }
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(discourseServiceProvider).updateUserPreferences(
        widget.username,
        <String, dynamic>{
          'muted_usernames': _muted.join(','),
          'allowed_pm_usernames': _allowedPm.join(','),
          'allow_private_messages': _allowPrivateMessages,
          'enable_allowed_pm_users': _enableAllowedPmUsers,
        },
      );
      await ref.read(currentUserProvider.notifier).refreshSilently(force: true);
      if (!mounted) return;
      ToastService.showSuccess(_tr('用户偏好已保存', 'User preferences saved'));
      await _load();
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _pickUser(Set<String> excluded) => showDialog<String>(
        context: context,
        builder: (_) => _PreferenceUserSearchDialog(
          excluded: {...excluded, widget.username},
          title: _tr('选择用户', 'Choose user'),
        ),
      );

  Future<void> _addMuted() async {
    final username = await _pickUser(_muted);
    if (username == null || !mounted) return;
    setState(() {
      _muted.add(username);
      _dirty = true;
    });
  }

  Future<void> _addAllowedPm() async {
    final username = await _pickUser(_allowedPm);
    if (username == null || !mounted) return;
    setState(() {
      _allowedPm.add(username);
      _dirty = true;
    });
  }

  Future<DateTime?> _pickIgnoreUntil() async {
    final now = DateTime.now();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(_tr('明天', 'Tomorrow')),
              onTap: () => Navigator.pop(sheetContext, 'tomorrow'),
            ),
            ListTile(
              title: Text(_tr('两周', 'Two weeks')),
              onTap: () => Navigator.pop(sheetContext, '2w'),
            ),
            ListTile(
              title: Text(_tr('一个月', 'One month')),
              onTap: () => Navigator.pop(sheetContext, '1m'),
            ),
            ListTile(
              title: Text(_tr('六个月', 'Six months')),
              onTap: () => Navigator.pop(sheetContext, '6m'),
            ),
            ListTile(
              title: Text(_tr('一年', 'One year')),
              onTap: () => Navigator.pop(sheetContext, '1y'),
            ),
            ListTile(
              title: Text(_tr('永久', 'Forever')),
              onTap: () => Navigator.pop(sheetContext, 'forever'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_calendar_outlined),
              title: Text(_tr('自定义日期', 'Custom date')),
              onTap: () => Navigator.pop(sheetContext, 'custom'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return null;
    switch (choice) {
      case 'tomorrow':
        return now.add(const Duration(days: 1));
      case '2w':
        return now.add(const Duration(days: 14));
      case '1m':
        return now.add(const Duration(days: 30));
      case '6m':
        return now.add(const Duration(days: 183));
      case '1y':
        return now.add(const Duration(days: 365));
      case 'forever':
        return now.add(const Duration(days: 365000));
      case 'custom':
        final date = await showDatePicker(
          context: context,
          firstDate: now.add(const Duration(days: 1)),
          lastDate: DateTime(now.year + 100),
          initialDate: now.add(const Duration(days: 14)),
        );
        if (date == null) return null;
        return DateTime(date.year, date.month, date.day, 23, 59, 59);
    }
    return null;
  }

  Future<void> _addIgnored() async {
    final username = await _pickUser(_ignored);
    if (username == null || !mounted) return;
    final until = await _pickIgnoreUntil();
    if (until == null || !mounted) return;
    final actingUserId = _user?['id'];
    if (actingUserId is! int) {
      ToastService.showError(_tr('无法确定当前用户 ID', 'Could not determine current user ID'));
      return;
    }
    try {
      await ref.read(discourseServiceProvider).setPreferenceUserNotificationLevel(
            username,
            actingUserId: actingUserId,
            level: 'ignore',
            expiringAt: until,
          );
      if (!mounted) return;
      setState(() => _ignored.add(username));
      ToastService.showSuccess(_tr('用户已忽略', 'User ignored'));
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _removeIgnored(String username) async {
    final actingUserId = _user?['id'];
    if (actingUserId is! int) return;
    try {
      await ref.read(discourseServiceProvider).setPreferenceUserNotificationLevel(
            username,
            actingUserId: actingUserId,
            level: 'normal',
          );
      if (!mounted) return;
      setState(() => _ignored.remove(username));
      ToastService.showSuccess(_tr('已取消忽略', 'Ignore removed'));
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  bool get _canIgnore => _user?['can_ignore_users'] == true;
  bool get _canMute => _user?['can_mute_users'] == true;
  bool get _canPm => _user?['can_send_private_messages'] == true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('用户过滤与私信', 'Users & private messages')),
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
        child: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text(_tr('重试', 'Retry')),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        if (_canIgnore)
          _section(
            _tr('忽略用户', 'Ignored users'),
            [
              for (final username in _ignored)
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: Text(username),
                  trailing: IconButton(
                    tooltip: _tr('取消忽略', 'Stop ignoring'),
                    onPressed: () => _removeIgnored(username),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_outlined),
                title: Text(_tr('添加忽略用户', 'Add ignored user')),
                subtitle: Text(_tr('可选择忽略到期时间', 'Choose when the ignore expires')),
                onTap: _addIgnored,
              ),
            ],
            subtitle: _tr(
              '与 Discourse 官方页面一致，忽略是有到期时间的用户通知级别，而不是普通用户名列表。',
              'Matches Discourse: ignore is an expiring user notification level, not a plain username list.',
            ),
          ),
        if (_canMute)
          _section(
            _tr('静音用户', 'Muted users'),
            [
              for (final username in _muted)
                ListTile(
                  leading: const Icon(Icons.volume_off_outlined),
                  title: Text(username),
                  trailing: IconButton(
                    tooltip: _tr('移除', 'Remove'),
                    onPressed: () => setState(() {
                      _muted.remove(username);
                      _dirty = true;
                    }),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_outlined),
                title: Text(_tr('添加静音用户', 'Add muted user')),
                onTap: _addMuted,
              ),
            ],
          ),
        if (_canPm)
          _section(
            _tr('私信', 'Private messages'),
            [
              SwitchListTile.adaptive(
                value: _allowPrivateMessages,
                title: Text(_tr('允许其他用户发送私信', 'Allow private messages')),
                onChanged: (value) => setState(() {
                  _allowPrivateMessages = value;
                  if (!value) _enableAllowedPmUsers = false;
                  _dirty = true;
                }),
              ),
              SwitchListTile.adaptive(
                value: _enableAllowedPmUsers,
                title: Text(
                  _tr('只允许指定用户向我发送私信', 'Only allow specified users to message me'),
                ),
                onChanged: !_allowPrivateMessages
                    ? null
                    : (value) => setState(() {
                          _enableAllowedPmUsers = value;
                          _dirty = true;
                        }),
              ),
              if (_allowPrivateMessages && _enableAllowedPmUsers) ...[
                for (final username in _allowedPm)
                  ListTile(
                    leading: const Icon(Icons.mark_email_read_outlined),
                    title: Text(username),
                    trailing: IconButton(
                      tooltip: _tr('移除', 'Remove'),
                      onPressed: () => setState(() {
                        _allowedPm.remove(username);
                        _dirty = true;
                      }),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_outlined),
                  title: Text(_tr('添加允许私信的用户', 'Add allowed PM user')),
                  onTap: _addAllowedPm,
                ),
              ],
            ],
          ),
      ],
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
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(children: _withDividers(children)),
            ),
          ],
        ),
      );

  List<Widget> _withDividers(List<Widget> children) {
    final result = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) result.add(const Divider(height: 1, indent: 16, endIndent: 16));
      result.add(children[i]);
    }
    return result;
  }
}

class _PreferenceUserSearchDialog extends ConsumerStatefulWidget {
  final Set<String> excluded;
  final String title;

  const _PreferenceUserSearchDialog({
    required this.excluded,
    required this.title,
  });

  @override
  ConsumerState<_PreferenceUserSearchDialog> createState() =>
      _PreferenceUserSearchDialogState();
}

class _PreferenceUserSearchDialogState
    extends ConsumerState<_PreferenceUserSearchDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = const [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(value));
  }

  Future<void> _search(String value) async {
    if (value.trim().isEmpty) {
      if (mounted) setState(() => _results = const []);
      return;
    }
    if (mounted) setState(() => _searching = true);
    try {
      final results = await ref.read(discourseServiceProvider).searchPreferenceUsers(
            value,
            excludeUsernames: widget.excluded,
          );
      if (mounted && value == _controller.text) {
        setState(() => _results = results);
      }
    } catch (_) {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: 'Username',
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              onChanged: _onChanged,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final user = _results[index];
                  final username = user['username']?.toString() ?? '';
                  final name = user['name']?.toString();
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                    title: Text(username),
                    subtitle: name == null || name.isEmpty ? null : Text(name),
                    onTap: username.isEmpty
                        ? null
                        : () => Navigator.pop(context, username),
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
      ],
    );
  }
}
