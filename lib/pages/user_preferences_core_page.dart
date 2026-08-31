import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discourse_providers.dart';
import '../services/discourse/user_preferences_api.dart';
import '../services/toast_service.dart';

/// Native counterpart of Discourse's `/u/:username/preferences/*` pages.
///
/// The sections and save fields intentionally follow the upstream Discourse
/// preferences controllers. Values under `user_option` are sent flattened,
/// matching `User.save()` in the Discourse frontend.
class UserPreferencesPage extends ConsumerStatefulWidget {
  final String username;

  const UserPreferencesPage({super.key, required this.username});

  @override
  ConsumerState<UserPreferencesPage> createState() =>
      _UserPreferencesPageState();
}

class _UserPreferencesPageState extends ConsumerState<UserPreferencesPage>
    with SingleTickerProviderStateMixin {
  static const _tabs = <_PreferenceTab>[
    _PreferenceTab('账户', 'Account', Icons.account_circle_outlined),
    _PreferenceTab('安全', 'Security', Icons.lock_outline),
    _PreferenceTab('个人资料', 'Profile', Icons.badge_outlined),
    _PreferenceTab('邮件', 'Emails', Icons.mail_outline),
    _PreferenceTab('通知', 'Notifications', Icons.notifications_none),
    _PreferenceTab('跟踪', 'Tracking', Icons.track_changes_outlined),
    _PreferenceTab('用户', 'Users', Icons.people_outline),
    _PreferenceTab('界面', 'Interface', Icons.desktop_windows_outlined),
    _PreferenceTab('导航', 'Navigation', Icons.menu),
    _PreferenceTab('日历', 'Calendar', Icons.calendar_month_outlined),
  ];

  late final TabController _tabController;
  late String _username;
  Map<String, dynamic>? _user;
  Map<String, dynamic> _options = const {};
  final Map<String, dynamic> _pending = {};
  String? _pendingUsername;
  String? _pendingEmail;
  bool _loading = true;
  bool _saving = false;
  Object? _error;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _username = widget.username;
    _tabController = TabController(length: _tabs.length, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';
  String _tr(String zh, String en) => _isZh ? zh : en;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(discourseServiceProvider)
          .getUserPreferences(_username);
      if (!mounted) return;
      final options = user['user_option'] is Map
          ? Map<String, dynamic>.from(user['user_option'] as Map)
          : <String, dynamic>{};
      setState(() {
        _user = user;
        _options = options;
        _pending.clear();
        _pendingUsername = (user['username'] ?? _username).toString();
        _pendingEmail = user['email']?.toString();
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

  String _string(String key, [String fallback = '']) =>
      _value(key)?.toString() ?? fallback;

  bool _bool(String key, [bool fallback = false]) {
    final value = _value(key);
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value == 'true' || value == '1';
    return fallback;
  }

  int? _int(String key) {
    final value = _value(key);
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  List<dynamic> _list(String key) {
    final value = _value(key);
    if (value is List) return List<dynamic>.from(value);
    return const [];
  }

  void _set(String key, dynamic value) {
    setState(() => _pending[key] = value);
  }

  bool _capability(String key, {bool fallback = true}) {
    final value = _user?[key];
    return value is bool ? value : fallback;
  }

  Future<void> _save() async {
    if (_saving || _user == null) return;
    final service = ref.read(discourseServiceProvider);
    final oldUsername = _username;
    final nextUsername = (_pendingUsername ?? oldUsername).trim();
    final oldEmail = _user?['email']?.toString() ?? '';
    final nextEmail = (_pendingEmail ?? oldEmail).trim();

    setState(() => _saving = true);
    try {
      if (_pending.isNotEmpty) {
        await service.updateUserPreferences(oldUsername, Map.of(_pending));
      }
      if (nextEmail.isNotEmpty && nextEmail != oldEmail) {
        await service.changePreferenceEmail(oldUsername, nextEmail);
      }
      if (nextUsername.isNotEmpty && nextUsername != oldUsername) {
        await service.changePreferenceUsername(oldUsername, nextUsername);
        await service.saveUsername(nextUsername);
        _username = nextUsername;
      }
      await ref.read(currentUserProvider.notifier).refreshSilently(force: true);
      if (!mounted) return;
      ToastService.showSuccess(_tr('个人设置已保存', 'Preferences saved'));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      setState(() => _saving = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestPasswordReset() async {
    final login = (_pendingEmail?.trim().isNotEmpty ?? false)
        ? _pendingEmail!.trim()
        : _username;
    try {
      await ref
          .read(discourseServiceProvider)
          .requestPreferencePasswordReset(login: login);
      if (!mounted) return;
      ToastService.showSuccess(
        _tr('密码重置邮件已请求，请检查邮箱', 'Password reset email requested'),
      );
    } catch (e) {
      ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _revokeToken(Map<String, dynamic> token) async {
    final id = token['id'] as int?;
    if (id == null || token['is_active'] == true) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_tr('撤销会话？', 'Revoke session?')),
        content: Text(
          _tr('该设备将需要重新登录。', 'That device will need to sign in again.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_tr('撤销', 'Revoke')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(discourseServiceProvider)
          .revokePreferenceAuthToken(_username, tokenId: id);
      if (!mounted) return;
      ToastService.showSuccess(_tr('会话已撤销', 'Session revoked'));
      await _load();
    } catch (e) {
      ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('个人设置', 'Preferences')),
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
        bottom: _loading || _error != null
            ? null
            : TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final tab in _tabs)
                    Tab(
                      icon: Icon(tab.icon, size: 18),
                      text: _isZh ? tab.zh : tab.en,
                    ),
                ],
              ),
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

    return TabBarView(
      controller: _tabController,
      children: [
        _accountTab(),
        _securityTab(),
        _profileTab(),
        _emailsTab(),
        _notificationsTab(),
        _trackingTab(),
        _usersTab(),
        _interfaceTab(),
        _navigationTab(),
        _calendarTab(),
      ],
    );
  }

  Widget _page(List<Widget> children) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
    children: children,
  );

  Widget _group(String title, List<Widget> children, {String? subtitle}) {
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
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
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
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) out.add(const Divider(height: 1, indent: 16, endIndent: 16));
      out.add(children[i]);
    }
    return out;
  }

  Widget _textField(
    String key,
    String label, {
    String? hint,
    int maxLines = 1,
    bool enabled = true,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextFormField(
        key: ValueKey('$_revision:$key'),
        initialValue: _string(key),
        enabled: enabled,
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

  Widget _accountTextField({
    required String field,
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    bool enabled = true,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextFormField(
        key: ValueKey('$_revision:account:$field'),
        initialValue: value,
        enabled: enabled,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        onChanged: onChanged,
      ),
    );
  }

  Widget _switch(
    String key,
    String title, {
    String? subtitle,
    bool enabled = true,
  }) => SwitchListTile.adaptive(
    value: _bool(key),
    onChanged: enabled ? (value) => _set(key, value) : null,
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
  );

  Widget _intSelect(
    String key,
    String label,
    List<(int, String)> values, {
    String? subtitle,
  }) {
    final current = _int(key);
    final available = values.any((item) => item.$1 == current);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: DropdownButtonFormField<int>(
        initialValue: available ? current : null,
        decoration: InputDecoration(
          labelText: label,
          helperText: subtitle,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final item in values)
            DropdownMenuItem(value: item.$1, child: Text(item.$2)),
        ],
        onChanged: (value) {
          if (value != null) _set(key, value);
        },
      ),
    );
  }

  Widget _stringSelect(
    String key,
    String label,
    List<(String, String)> values,
  ) {
    final current = _string(key);
    final available = values.any((item) => item.$1 == current);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: DropdownButtonFormField<String>(
        initialValue: available ? current : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final item in values)
            DropdownMenuItem(value: item.$1, child: Text(item.$2)),
        ],
        onChanged: (value) {
          if (value != null) _set(key, value);
        },
      ),
    );
  }

  Widget _stringListField(String key, String label, {String? hint}) {
    final initial = _list(key).map((e) => e.toString()).join(', ');
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextFormField(
        key: ValueKey('$_revision:list:$key'),
        initialValue: initial,
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: _tr('使用逗号分隔', 'Separate items with commas'),
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) => _set(
          key,
          value
              .split(RegExp(r'[,，\n]'))
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
        ),
      ),
    );
  }

  Widget _intListField(String key, String label) {
    final initial = _list(key).map((e) => e.toString()).join(', ');
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextFormField(
        key: ValueKey('$_revision:int-list:$key'),
        initialValue: initial,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          helperText: _tr('使用逗号分隔分类 ID', 'Comma-separated category IDs'),
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) => _set(
          key,
          value
              .split(RegExp(r'[,，\s]+'))
              .map((e) => int.tryParse(e.trim()))
              .whereType<int>()
              .toList(),
        ),
      ),
    );
  }

  Widget _accountTab() => _page([
    _group(
      _tr('账户信息', 'Account'),
      [
        _accountTextField(
          field: 'username',
          label: _tr('用户名', 'Username'),
          value: _pendingUsername ?? _username,
          enabled: _capability('can_edit_username'),
          onChanged: (v) => _pendingUsername = v,
        ),
        _accountTextField(
          field: 'email',
          label: _tr('邮箱', 'Email'),
          value: _pendingEmail ?? '',
          enabled: _capability('can_edit_email'),
          keyboardType: TextInputType.emailAddress,
          onChanged: (v) => _pendingEmail = v,
        ),
        _textField('name', _tr('姓名 / 显示名', 'Name')),
        _textField('title', _tr('头衔', 'Title')),
      ],
      subtitle: _tr(
        '用户名和邮箱使用 Discourse 官方独立接口；邮箱变更可能需要邮件确认。',
        'Username and email use Discourse’s dedicated APIs; email changes may require confirmation.',
      ),
    ),
  ]);

  Widget _securityTab() {
    final tokens = (_user?['user_auth_tokens'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final passkeys = (_user?['user_passkeys'] as List? ?? const []);
    final secondFactor = _user?['second_factor_enabled'] == true;
    return _page([
      _group(_tr('登录安全', 'Login security'), [
        ListTile(
          leading: Icon(
            secondFactor ? Icons.verified_user : Icons.shield_outlined,
          ),
          title: Text(_tr('双重验证', 'Two-factor authentication')),
          subtitle: Text(
            secondFactor
                ? _tr('已启用', 'Enabled')
                : _tr('未启用', 'Not enabled'),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.key_outlined),
          title: Text(_tr('Passkey', 'Passkeys')),
          subtitle: Text(_tr('${passkeys.length} 个', '${passkeys.length} configured')),
        ),
        ListTile(
          leading: const Icon(Icons.password_outlined),
          title: Text(_tr('修改密码', 'Change password')),
          subtitle: Text(
            _tr('发送 Discourse 密码重置邮件', 'Send a Discourse password reset email'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _requestPasswordReset,
        ),
      ]),
      if (tokens.isNotEmpty)
        _group(
          _tr('已登录设备', 'Signed-in devices'),
          [
            for (final token in tokens)
              ListTile(
                leading: Icon(
                  token['is_active'] == true
                      ? Icons.phone_android
                      : Icons.devices_other,
                ),
                title: Text(
                  token['client_ip']?.toString() ??
                      token['device']?.toString() ??
                      _tr('登录会话', 'Login session'),
                ),
                subtitle: Text(
                  [
                    token['location']?.toString(),
                    token['seen_at']?.toString(),
                  ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
                ),
                trailing: token['is_active'] == true
                    ? Text(_tr('当前', 'Current'))
                    : IconButton(
                        tooltip: _tr('撤销', 'Revoke'),
                        onPressed: () => _revokeToken(token),
                        icon: const Icon(Icons.logout),
                      ),
              ),
          ],
        ),
    ]);
  }

  Widget _profileTab() => _page([
    _group(_tr('关于我', 'About me'), [
      _textField(
        'bio_raw',
        _tr('个人简介', 'Bio'),
        maxLines: 6,
        enabled: _capability('can_change_bio'),
      ),
      _textField(
        'location',
        _tr('位置', 'Location'),
        enabled: _capability('can_change_location'),
      ),
      _textField(
        'website',
        _tr('网站', 'Website'),
        keyboardType: TextInputType.url,
        enabled: _capability('can_change_website'),
      ),
      _textField('date_of_birth', _tr('生日', 'Date of birth'), hint: 'YYYY-MM-DD'),
    ]),
    _group(_tr('隐私与时区', 'Privacy & timezone'), [
      _textField('timezone', _tr('时区', 'Timezone'), hint: 'Asia/Shanghai'),
      _switch(
        'hide_profile',
        _tr('隐藏公开个人资料', 'Hide public profile'),
      ),
    ]),
  ]);

  Widget _emailsTab() => _page([
    _group(_tr('邮件通知', 'Email notifications'), [
      _intSelect('email_level', _tr('话题和回复邮件', 'Topic/reply emails'), [
        (0, _tr('始终', 'Always')),
        (1, _tr('仅离开时', 'Only when away')),
        (2, _tr('从不', 'Never')),
      ]),
      _intSelect('email_messages_level', _tr('私信邮件', 'Message emails'), [
        (0, _tr('始终', 'Always')),
        (1, _tr('仅离开时', 'Only when away')),
        (2, _tr('从不', 'Never')),
      ]),
      _switch('email_in_reply_to', _tr('回复邮件中包含原文', 'Include post in reply email')),
      _intSelect('email_previous_replies', _tr('包含之前的回复', 'Previous replies'), [
        (0, _tr('始终', 'Always')),
        (1, _tr('未通过邮件发送时', 'Unless already emailed')),
        (2, _tr('从不', 'Never')),
      ]),
    ]),
    _group(_tr('摘要', 'Digest'), [
      _switch('email_digests', _tr('发送活动摘要', 'Send activity digests')),
      _intSelect('digest_after_minutes', _tr('摘要频率', 'Digest frequency'), [
        (30, _tr('每 30 分钟', 'Every 30 minutes')),
        (60, _tr('每小时', 'Hourly')),
        (1440, _tr('每天', 'Daily')),
        (10080, _tr('每周', 'Weekly')),
        (43200, _tr('每月', 'Monthly')),
        (259200, _tr('每六个月', 'Every six months')),
      ]),
      _switch('include_tl0_in_digests', _tr('摘要包含新用户内容', 'Include new-user content in digests')),
    ]),
    _group(_tr('邮件列表模式', 'Mailing list mode'), [
      _switch('mailing_list_mode', _tr('启用邮件列表模式', 'Enable mailing list mode')),
      _intSelect('mailing_list_mode_frequency', _tr('邮件列表频率', 'Mailing list frequency'), [
        (1, _tr('发送每篇新帖', 'Send every new post')),
        (2, _tr('发送但不回显自己的帖子', 'Send except my own posts')),
      ]),
    ]),
  ]);

  Widget _notificationsTab() => _page([
    _group(_tr('通知行为', 'Notification behavior'), [
      _switch('allow_private_messages', _tr('允许其他用户发送私信', 'Allow private messages')),
      _switch('enable_allowed_pm_users', _tr('只允许指定用户私信', 'Only allow listed users to message me')),
      _switch('notify_on_linked_posts', _tr('有人链接我的帖子时通知', 'Notify when my post is linked')),
      _switch(
        'enable_upcoming_change_available_notifications',
        _tr('接收即将推出功能通知', 'Notify me about upcoming features'),
      ),
      _intSelect('like_notification_frequency', _tr('点赞通知频率', 'Like notification frequency'), [
        (0, _tr('每次', 'Always')),
        (1, _tr('首次及每天一次', 'First time and daily')),
        (2, _tr('仅首次', 'First time')),
        (3, _tr('从不', 'Never')),
      ]),
    ]),
  ]);

  Widget _trackingTab() => _page([
    _group(_tr('话题跟踪', 'Topic tracking'), [
      _intSelect('new_topic_duration_minutes', _tr('将话题视为“新”的时长', 'Consider topics new'), [
        (-1, _tr('直到我看过', 'Until viewed')),
        (1440, _tr('1 天', '1 day')),
        (2880, _tr('2 天', '2 days')),
        (10080, _tr('1 周', '1 week')),
        (20160, _tr('2 周', '2 weeks')),
        (-2, _tr('从上次访问开始', 'Since last visit')),
      ]),
      _intSelect('auto_track_topics_after_msecs', _tr('自动跟踪话题', 'Auto-track topics after'), [
        (-1, _tr('从不', 'Never')),
        (0, _tr('立即', 'Immediately')),
        (30000, _tr('30 秒', '30 seconds')),
        (60000, _tr('1 分钟', '1 minute')),
        (120000, _tr('2 分钟', '2 minutes')),
        (180000, _tr('3 分钟', '3 minutes')),
        (300000, _tr('5 分钟', '5 minutes')),
        (600000, _tr('10 分钟', '10 minutes')),
      ]),
      _intSelect('notification_level_when_replying', _tr('回复话题时', 'When replying'), [
        (3, _tr('关注话题', 'Watch topic')),
        (2, _tr('跟踪话题', 'Track topic')),
        (1, _tr('不改变', 'Do nothing')),
      ]),
      _switch('watched_precedence_over_muted', _tr('关注优先于静音', 'Watched takes precedence over muted')),
    ]),
    _group(_tr('分类', 'Categories'), [
      _intListField('watched_category_ids', _tr('关注的分类', 'Watched categories')),
      _intListField('tracked_category_ids', _tr('跟踪的分类', 'Tracked categories')),
      _intListField('watched_first_post_category_ids', _tr('只关注首帖的分类', 'First-post watched categories')),
      _intListField('muted_category_ids', _tr('静音的分类', 'Muted categories')),
      if (_user?.containsKey('regular_category_ids') == true)
        _intListField('regular_category_ids', _tr('普通分类', 'Regular categories')),
    ]),
    _group(_tr('标签', 'Tags'), [
      _stringListField('watched_tags', _tr('关注的标签', 'Watched tags')),
      _stringListField('tracked_tags', _tr('跟踪的标签', 'Tracked tags')),
      _stringListField('watching_first_post_tags', _tr('只关注首帖的标签', 'First-post watched tags')),
      _stringListField('muted_tags', _tr('静音的标签', 'Muted tags')),
    ]),
  ]);

  Widget _usersTab() => _page([
    _group(_tr('用户过滤', 'User filters'), [
      _stringListField('muted_usernames', _tr('静音用户', 'Muted users'), hint: 'alice, bob'),
      _stringListField('ignored_usernames', _tr('忽略用户', 'Ignored users'), hint: 'alice, bob'),
      _stringListField('allowed_pm_usernames', _tr('允许私信的用户', 'Allowed PM users'), hint: 'alice, bob'),
    ]),
  ]);

  Widget _interfaceTab() => _page([
    _group(_tr('阅读与交互', 'Reading & interaction'), [
      _switch('external_links_in_new_tab', _tr('外部链接在新标签页打开', 'Open external links in a new tab')),
      _switch('enable_quoting', _tr('启用引用回复', 'Enable quote reply')),
      _switch('enable_smart_lists', _tr('启用智能列表', 'Enable smart lists')),
      _switch('automatically_unpin_topics', _tr('阅读后自动取消置顶', 'Automatically unpin topics after reading')),
      _switch('dynamic_favicon', _tr('动态图标显示通知数量', 'Show notification count on favicon')),
      _switch('enable_markdown_monospace_font', _tr('Markdown 编辑使用等宽字体', 'Use monospace font for Markdown')),
      _switch('skip_new_user_tips', _tr('跳过新用户提示', 'Skip new-user tips')),
    ]),
    _group(_tr('外观与首页', 'Appearance & home'), [
      _stringSelect('text_size', _tr('文字大小', 'Text size'), [
        ('smallest', _tr('最小', 'Smallest')),
        ('smaller', _tr('较小', 'Smaller')),
        ('normal', _tr('正常', 'Normal')),
        ('larger', _tr('较大', 'Larger')),
        ('largest', _tr('最大', 'Largest')),
      ]),
      _stringSelect('title_count_mode', _tr('标题计数', 'Title count mode'), [
        ('notifications', _tr('通知', 'Notifications')),
        ('contextual', _tr('上下文', 'Contextual')),
      ]),
      _intSelect('homepage_id', _tr('默认首页', 'Default homepage'), [
        (-1, _tr('站点默认', 'Site default')),
        (1, _tr('最新', 'Latest')),
        (2, _tr('分类', 'Categories')),
        (3, _tr('未读', 'Unread')),
        (4, _tr('新内容', 'New')),
        (5, _tr('热门', 'Top')),
        (6, _tr('书签', 'Bookmarks')),
        (7, _tr('未看', 'Unseen')),
        (8, _tr('热议', 'Hot')),
      ]),
      _stringSelect('interface_color_mode', _tr('界面配色模式', 'Interface color mode'), [
        ('auto', _tr('跟随系统', 'Auto')),
        ('light', _tr('浅色', 'Light')),
        ('dark', _tr('深色', 'Dark')),
      ]),
    ]),
    _group(_tr('隐私与语言', 'Privacy & language'), [
      _switch('hide_presence', _tr('隐藏在线状态', 'Hide presence')),
      _switch('automatically_translate', _tr('自动翻译内容', 'Automatically translate content')),
      _switch('show_original_content', _tr('同时显示原文', 'Show original content')),
      _stringListField('understood_languages', _tr('我能理解的语言', 'Understood languages'), hint: 'zh_CN, en'),
      _textField('locale', _tr('界面语言', 'Interface locale'), hint: 'zh_CN'),
    ]),
  ]);

  Widget _navigationTab() => _page([
    _group(_tr('侧边栏', 'Sidebar'), [
      _switch('sidebar_link_to_filtered_list', _tr('侧边栏链接打开筛选列表', 'Sidebar links open filtered lists')),
      _switch('sidebar_show_count_of_new_items', _tr('显示新内容数量', 'Show new-item counts')),
      _intListField('sidebar_category_ids', _tr('固定分类', 'Pinned categories')),
      _stringListField('sidebar_tag_names', _tr('固定标签', 'Pinned tags')),
    ]),
  ]);

  Widget _calendarTab() => _page([
    _group(_tr('日历偏好', 'Calendar preferences'), [
      _stringSelect('default_calendar', _tr('默认日历', 'Default calendar'), [
        ('google', 'Google Calendar'),
        ('ics', 'ICS'),
        ('none_selected', _tr('未选择', 'Not selected')),
      ]),
    ], subtitle: _tr(
      '对应 Discourse 个人资料中的默认日历设置。站点若启用日历订阅插件，订阅本身由插件接口提供。',
      'Matches Discourse’s default calendar preference. Calendar subscriptions themselves are plugin-provided when enabled.',
    )),
  ]);
}

class _PreferenceTab {
  final String zh;
  final String en;
  final IconData icon;

  const _PreferenceTab(this.zh, this.en, this.icon);
}
