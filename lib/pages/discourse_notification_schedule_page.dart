import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discourse_providers.dart';
import '../services/discourse/user_preferences_api.dart';
import '../services/preloaded_data_service.dart';
import '../services/toast_service.dart';

class DiscourseNotificationSchedulePage extends ConsumerStatefulWidget {
  final String username;

  const DiscourseNotificationSchedulePage({super.key, required this.username});

  @override
  ConsumerState<DiscourseNotificationSchedulePage> createState() =>
      _DiscourseNotificationSchedulePageState();
}

class _DiscourseNotificationSchedulePageState
    extends ConsumerState<DiscourseNotificationSchedulePage> {
  static const _daysZh = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  static const _daysEn = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  Map<String, dynamic> _options = const {};
  Map<String, dynamic> _settings = const {};
  Map<String, dynamic> _schedule = {};
  String _pushLevel = 'all';
  bool _scheduleTouched = false;
  bool _pushTouched = false;
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
      final results = await Future.wait<dynamic>([
        ref.read(discourseServiceProvider).getUserPreferences(widget.username),
        PreloadedDataService().getSiteSettings(),
      ]);
      final user = Map<String, dynamic>.from(results[0] as Map);
      final options = user['user_option'] is Map
          ? Map<String, dynamic>.from(user['user_option'] as Map)
          : <String, dynamic>{};
      final rawSchedule = user['user_notification_schedule'];
      final schedule = rawSchedule is Map
          ? Map<String, dynamic>.from(rawSchedule)
          : <String, dynamic>{'enabled': false};
      if (!mounted) return;
      setState(() {
        _options = options;
        _settings = results[1] is Map
            ? Map<String, dynamic>.from(results[1] as Map)
            : <String, dynamic>{};
        _schedule = schedule;
        _pushLevel = options['push_notification_level']?.toString() ?? 'all';
        _scheduleTouched = false;
        _pushTouched = false;
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

  int _minute(String key, int fallback) {
    final value = _schedule[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  void _setSchedule(String key, dynamic value) {
    setState(() {
      _schedule[key] = value;
      _scheduleTouched = true;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_scheduleTouched && !_pushTouched) {
      ToastService.showInfo(_tr('没有需要保存的更改', 'No changes to save'));
      return;
    }
    final payload = <String, dynamic>{};
    if (_scheduleTouched) payload['user_notification_schedule'] = _schedule;
    if (_pushTouched) payload['push_notification_level'] = _pushLevel;

    setState(() => _saving = true);
    try {
      await ref
          .read(discourseServiceProvider)
          .updateUserPreferences(widget.username, payload);
      await ref.read(currentUserProvider.notifier).refreshSilently(force: true);
      if (!mounted) return;
      ToastService.showSuccess(_tr('通知设置已保存', 'Notification settings saved'));
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
        title: Text(_tr('通知时间表', 'Notification schedule')),
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

    final enabled = _schedule['enabled'] == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _section(
          _tr('推送通知级别', 'Push notification level'),
          [
            Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<String>(
                key: ValueKey('$_revision:push:$_pushLevel'),
                initialValue: _pushValues.any((entry) => entry.$1 == _pushLevel)
                    ? _pushLevel
                    : 'all',
                decoration: InputDecoration(
                  labelText: _tr('Discourse 推送范围', 'Discourse push scope'),
                  helperText: _tr(
                    '这是服务器端通知偏好；系统通知权限仍由 Fluxdo/操作系统管理。',
                    'This is the server-side preference; OS notification permission is still managed by Fluxdo/the system.',
                  ),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final entry in _pushValues)
                    DropdownMenuItem(value: entry.$1, child: Text(entry.$2)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _pushLevel = value;
                    _pushTouched = true;
                  });
                },
              ),
            ),
          ],
        ),
        _section(
          _tr('勿扰时间表', 'Do-not-disturb schedule'),
          [
            SwitchListTile.adaptive(
              value: enabled,
              onChanged: (value) => _setSchedule('enabled', value),
              title: Text(_tr('启用通知时间表', 'Enable notification schedule')),
              subtitle: Text(
                _tr(
                  '按 Discourse 账户时区解释下面的时间。',
                  'Times below are interpreted in your Discourse account timezone.',
                ),
              ),
            ),
            if (enabled)
              for (var day = 0; day < 7; day++) _dayEditor(day),
          ],
          subtitle: _tr(
            '与 Discourse 官方设置一致：每天可选择一个允许通知的时间窗口；“无”表示该日不设置窗口。',
            'Matches Discourse: each day can have a notification window; None disables the window for that day.',
          ),
        ),
      ],
    );
  }

  List<(String, String)> get _pushValues {
    final values = <(String, String)>[
      ('none', _tr('无', 'None')),
      ('all', _tr('全部', 'All')),
    ];
    final chatAvailable = _settings['chat_enabled'] == true &&
        _options['chat_enabled'] == true;
    if (chatAvailable) {
      values.add(('chat_only', _tr('仅聊天', 'Chat only')));
    }
    return values;
  }

  Widget _dayEditor(int day) {
    final startKey = 'day_${day}_start_time';
    final endKey = 'day_${day}_end_time';
    final start = _minute(startKey, -1);
    final defaultEnd = start >= 0
        ? (start + 30).clamp(30, 1440).toInt()
        : 1440;
    var end = _minute(endKey, defaultEnd);
    if (start >= 0 && end <= start) {
      end = (start + 30).clamp(30, 1440).toInt();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isZh ? _daysZh[day] : _daysEn[day],
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('$_revision:$startKey:$start'),
                  initialValue: _startOptions.contains(start) ? start : -1,
                  decoration: InputDecoration(
                    labelText: _tr('开始', 'Start'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(value: -1, child: Text(_tr('无', 'None'))),
                    for (final minute in _startOptions.where((m) => m >= 0))
                      DropdownMenuItem(
                        value: minute,
                        child: Text(_formatMinute(minute)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _schedule[startKey] = value;
                      if (value >= 0) {
                        final currentEnd = _minute(endKey, value + 30);
                        if (currentEnd <= value) {
                          _schedule[endKey] =
                              (value + 30).clamp(30, 1440).toInt();
                        }
                      }
                      _scheduleTouched = true;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('$_revision:$endKey:$end:$start'),
                  initialValue: start < 0 ? null : end,
                  decoration: InputDecoration(
                    labelText: _tr('结束', 'End'),
                    border: const OutlineInputBorder(),
                  ),
                  items: start < 0
                      ? const <DropdownMenuItem<int>>[]
                      : [
                          for (final minute in _endOptions(start))
                            DropdownMenuItem(
                              value: minute,
                              child: Text(_formatMinute(minute)),
                            ),
                        ],
                  onChanged: start < 0
                      ? null
                      : (value) {
                          if (value != null) _setSchedule(endKey, value);
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<int> get _startOptions => [-1, for (var m = 0; m < 1440; m += 30) m];

  List<int> _endOptions(int start) => [
        for (var m = start + 30; m <= 1440; m += 30) m,
      ];

  String _formatMinute(int minute) {
    if (minute == 1440) return _tr('午夜', 'Midnight');
    final hour = minute ~/ 60;
    final min = minute % 60;
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: hour, minute: min),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
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
