import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants.dart';
import '../models/community_user_preferences.dart';
import '../providers/core_providers.dart';
import '../providers/discourse_parity_providers.dart';
import 'webview_page.dart';

/// Native editor for server-side Discourse preferences.
///
/// This page intentionally stays separate from FluxDO local settings. Every
/// value shown here comes from Discourse and writes back through the same user
/// update path used by the web client.
class CommunityAccountSettingsPage extends ConsumerWidget {
  const CommunityAccountSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(communityUserPreferencesProvider);
    final zh = Localizations.localeOf(context).languageCode == 'zh';

    return Scaffold(
      appBar: AppBar(
        title: Text(zh ? '社区账户设置' : 'Community settings'),
      ),
      body: preferences.when(
        data: (value) => _CommunityPreferencesForm(
          key: ValueKey('${value.username}:${value.raw.hashCode}'),
          preferences: value,
        ),
        loading: () => const Center(
          child: CircularProgressIndicator.adaptive(),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 36),
                const SizedBox(height: 12),
                Text(error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.invalidate(communityUserPreferencesProvider),
                  child: Text(zh ? '重试' : 'Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommunityPreferencesForm extends ConsumerStatefulWidget {
  const _CommunityPreferencesForm({
    super.key,
    required this.preferences,
  });

  final CommunityUserPreferences preferences;

  @override
  ConsumerState<_CommunityPreferencesForm> createState() =>
      _CommunityPreferencesFormState();
}

class _CommunityPreferencesFormState
    extends ConsumerState<_CommunityPreferencesForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _locationController;
  late final TextEditingController _websiteController;
  late final TextEditingController _timezoneController;

  late String? _title;
  late int? _primaryGroupId;
  late int? _flairGroupId;

  late bool _emailDigests;
  late bool _includeTl0InDigests;
  late bool _mailingListMode;
  late bool _allowPrivateMessages;
  late bool _hideProfile;
  late bool _hidePresence;
  late bool _externalLinksInNewTab;
  late bool _enableQuoting;
  late bool _dynamicFavicon;
  late bool _automaticallyUnpinTopics;
  late bool _notifyOnLinkedPosts;
  late bool _skipNewUserTips;
  late bool _sidebarLinkToFilteredList;
  late bool _sidebarShowCountOfNewItems;
  late bool _watchedPrecedenceOverMuted;
  late bool _automaticallyTranslate;

  late int? _emailLevel;
  late int? _emailMessagesLevel;
  late int? _likeNotificationFrequency;
  late int? _pushNotificationLevel;
  late int? _notificationLevelWhenReplying;

  bool _saving = false;

  CommunityUserPreferences get _initial => widget.preferences;
  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  String _text(String zh, String en) => _zh ? zh : en;

  @override
  void initState() {
    super.initState();
    final value = widget.preferences;
    _nameController = TextEditingController(text: value.name ?? '');
    _bioController = TextEditingController(text: value.bioRaw ?? '');
    _locationController = TextEditingController(text: value.location ?? '');
    _websiteController = TextEditingController(text: value.website ?? '');
    _timezoneController = TextEditingController(text: value.timezone ?? '');

    _title = value.title;
    _primaryGroupId = value.primaryGroupId;
    _flairGroupId = value.flairGroupId;

    _emailDigests = value.emailDigests;
    _includeTl0InDigests = value.includeTl0InDigests;
    _mailingListMode = value.mailingListMode;
    _allowPrivateMessages = value.allowPrivateMessages;
    _hideProfile = value.hideProfile;
    _hidePresence = value.hidePresence;
    _externalLinksInNewTab = value.externalLinksInNewTab;
    _enableQuoting = value.enableQuoting;
    _dynamicFavicon = value.dynamicFavicon;
    _automaticallyUnpinTopics = value.automaticallyUnpinTopics;
    _notifyOnLinkedPosts = value.notifyOnLinkedPosts;
    _skipNewUserTips = value.skipNewUserTips;
    _sidebarLinkToFilteredList = value.sidebarLinkToFilteredList;
    _sidebarShowCountOfNewItems = value.sidebarShowCountOfNewItems;
    _watchedPrecedenceOverMuted = value.watchedPrecedenceOverMuted;
    _automaticallyTranslate = value.automaticallyTranslate;

    _emailLevel = value.emailLevel;
    _emailMessagesLevel = value.emailMessagesLevel;
    _likeNotificationFrequency = value.likeNotificationFrequency;
    _pushNotificationLevel = value.pushNotificationLevel;
    _notificationLevelWhenReplying = value.notificationLevelWhenReplying;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    _websiteController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  bool _hasOption(String key) => _initial.userOptionRaw.containsKey(key);

  void _addTextChange(
    Map<String, dynamic> changes,
    String key,
    TextEditingController controller,
    String? initial, {
    required bool enabled,
    bool trim = true,
  }) {
    if (!enabled) return;
    final value = trim ? controller.text.trim() : controller.text;
    final oldValue = trim ? (initial ?? '').trim() : (initial ?? '');
    if (value != oldValue) changes[key] = value;
  }

  void _addBoolOptionChange(
    Map<String, dynamic> changes,
    String key,
    bool value,
    bool initial,
  ) {
    if (_initial.canEdit && _hasOption(key) && value != initial) {
      changes[key] = value;
    }
  }

  void _addIntOptionChange(
    Map<String, dynamic> changes,
    String key,
    int? value,
    int? initial,
  ) {
    if (_initial.canEdit &&
        _hasOption(key) &&
        value != null &&
        value != initial) {
      changes[key] = value;
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final changes = <String, dynamic>{};

    _addTextChange(
      changes,
      'name',
      _nameController,
      _initial.name,
      enabled: _initial.canEditName,
    );

    if (_initial.canEdit &&
        _initial.availableTitles.isNotEmpty &&
        _title != _initial.title) {
      changes['title'] = _title ?? '';
    }
    if (_initial.canEdit &&
        _initial.userSelectedPrimaryGroups &&
        (_initial.availablePrimaryGroups.isNotEmpty ||
            _initial.primaryGroupId != null) &&
        _primaryGroupId != _initial.primaryGroupId) {
      changes['primary_group_id'] = _primaryGroupId?.toString() ?? '';
    }
    if (_initial.canEdit &&
        (_initial.availableFlairGroups.isNotEmpty ||
            _initial.flairGroupId != null) &&
        _flairGroupId != _initial.flairGroupId) {
      changes['flair_group_id'] = _flairGroupId?.toString() ?? '';
    }

    _addTextChange(
      changes,
      'bio_raw',
      _bioController,
      _initial.bioRaw,
      enabled: _initial.canChangeBio,
      trim: false,
    );
    _addTextChange(
      changes,
      'location',
      _locationController,
      _initial.location,
      enabled: _initial.canChangeLocation,
    );
    _addTextChange(
      changes,
      'website',
      _websiteController,
      _initial.website,
      enabled: _initial.canChangeWebsite,
    );
    _addTextChange(
      changes,
      'timezone',
      _timezoneController,
      _initial.timezone,
      enabled: _initial.canEdit &&
          (_initial.timezone != null || _hasOption('timezone')),
    );

    _addBoolOptionChange(
      changes,
      'email_digests',
      _emailDigests,
      _initial.emailDigests,
    );
    _addBoolOptionChange(
      changes,
      'include_tl0_in_digests',
      _includeTl0InDigests,
      _initial.includeTl0InDigests,
    );
    _addBoolOptionChange(
      changes,
      'mailing_list_mode',
      _mailingListMode,
      _initial.mailingListMode,
    );
    _addBoolOptionChange(
      changes,
      'allow_private_messages',
      _allowPrivateMessages,
      _initial.allowPrivateMessages,
    );
    _addBoolOptionChange(
      changes,
      'hide_profile',
      _hideProfile,
      _initial.hideProfile,
    );
    _addBoolOptionChange(
      changes,
      'hide_presence',
      _hidePresence,
      _initial.hidePresence,
    );
    _addBoolOptionChange(
      changes,
      'external_links_in_new_tab',
      _externalLinksInNewTab,
      _initial.externalLinksInNewTab,
    );
    _addBoolOptionChange(
      changes,
      'enable_quoting',
      _enableQuoting,
      _initial.enableQuoting,
    );
    _addBoolOptionChange(
      changes,
      'dynamic_favicon',
      _dynamicFavicon,
      _initial.dynamicFavicon,
    );
    _addBoolOptionChange(
      changes,
      'automatically_unpin_topics',
      _automaticallyUnpinTopics,
      _initial.automaticallyUnpinTopics,
    );
    _addBoolOptionChange(
      changes,
      'notify_on_linked_posts',
      _notifyOnLinkedPosts,
      _initial.notifyOnLinkedPosts,
    );
    _addBoolOptionChange(
      changes,
      'skip_new_user_tips',
      _skipNewUserTips,
      _initial.skipNewUserTips,
    );
    _addBoolOptionChange(
      changes,
      'sidebar_link_to_filtered_list',
      _sidebarLinkToFilteredList,
      _initial.sidebarLinkToFilteredList,
    );
    _addBoolOptionChange(
      changes,
      'sidebar_show_count_of_new_items',
      _sidebarShowCountOfNewItems,
      _initial.sidebarShowCountOfNewItems,
    );
    _addBoolOptionChange(
      changes,
      'watched_precedence_over_muted',
      _watchedPrecedenceOverMuted,
      _initial.watchedPrecedenceOverMuted,
    );
    _addBoolOptionChange(
      changes,
      'automatically_translate',
      _automaticallyTranslate,
      _initial.automaticallyTranslate,
    );

    _addIntOptionChange(
      changes,
      'email_level',
      _emailLevel,
      _initial.emailLevel,
    );
    _addIntOptionChange(
      changes,
      'email_messages_level',
      _emailMessagesLevel,
      _initial.emailMessagesLevel,
    );
    _addIntOptionChange(
      changes,
      'like_notification_frequency',
      _likeNotificationFrequency,
      _initial.likeNotificationFrequency,
    );
    _addIntOptionChange(
      changes,
      'push_notification_level',
      _pushNotificationLevel,
      _initial.pushNotificationLevel,
    );
    _addIntOptionChange(
      changes,
      'notification_level_when_replying',
      _notificationLevelWhenReplying,
      _initial.notificationLevelWhenReplying,
    );

    if (changes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('没有需要保存的修改', 'No changes to save'))),
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(discourseServiceProvider)
          .updateCommunityUserPreferences(changes);
      ref.invalidate(communityUserPreferencesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('社区设置已同步', 'Community settings synced'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openWebPreferences() {
    WebViewPage.open(
      context,
      '${AppConstants.baseUrl}/u/${Uri.encodeComponent(_initial.username)}/preferences/account',
      title: _text('完整社区设置', 'Full community settings'),
    );
  }

  Widget _sectionTitle(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    bool enabled = true,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? hintText,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled && !_saving,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _toggle({
    required String keyName,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    if (!_hasOption(keyName)) return const SizedBox.shrink();
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: value,
      onChanged: _initial.canEdit && !_saving ? onChanged : null,
    );
  }

  Widget _selectOption({
    required String keyName,
    required String title,
    String? subtitle,
    required int? value,
    required Map<int, String> options,
    required ValueChanged<int?> onChanged,
  }) {
    if (!_hasOption(keyName) || value == null) {
      return const SizedBox.shrink();
    }

    final effectiveOptions = Map<int, String>.from(options);
    effectiveOptions.putIfAbsent(
      value,
      () => _text('未知值 ($value)', 'Unknown value ($value)'),
    );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            isExpanded: true,
            value: value,
            onChanged: _initial.canEdit && !_saving ? onChanged : null,
            items: effectiveOptions.entries
                .map(
                  (entry) => DropdownMenuItem<int>(
                    value: entry.key,
                    child: Text(
                      entry.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
  }

  Widget _titleChoice() {
    final choices = _initial.availableTitles;
    if (choices.isEmpty) return const SizedBox.shrink();
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(value: '', child: Text(_text('无', 'None'))),
      ...choices.map(
        (title) => DropdownMenuItem<String>(
          value: title,
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Text(_text('头衔', 'Title')),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: _title ?? '',
            onChanged: _initial.canEdit && !_saving
                ? (value) => setState(
                      () => _title = value == null || value.isEmpty ? null : value,
                    )
                : null,
            items: items,
          ),
        ),
      ),
    );
  }

  Widget _groupChoice({
    required String title,
    required int? value,
    required List<CommunityPreferenceGroup> groups,
    required ValueChanged<int?> onChanged,
  }) {
    if (groups.isEmpty && value == null) return const SizedBox.shrink();
    final labels = <int, String>{for (final group in groups) group.id: group.label};
    if (value != null && !labels.containsKey(value)) {
      labels[value] = _text('当前组 (#$value)', 'Current group (#$value)');
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Text(title),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            isExpanded: true,
            value: value ?? -1,
            onChanged: _initial.canEdit && !_saving
                ? (selected) => onChanged(selected == -1 ? null : selected)
                : null,
            items: [
              DropdownMenuItem(value: -1, child: Text(_text('无', 'None'))),
              ...labels.entries.map(
                (entry) => DropdownMenuItem<int>(
                  value: entry.key,
                  child: Text(
                    entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canEditTimezone = _initial.canEdit &&
        (_initial.timezone != null || _hasOption('timezone'));
    final emailDeliveryOptions = <int, String>{
      0: _text('始终', 'Always'),
      1: _text('仅离开时', 'Only when away'),
      2: _text('从不', 'Never'),
    };
    final likeOptions = <int, String>{
      0: _text('始终', 'Always'),
      1: _text('首次且每天一次', 'First time & daily'),
      2: _text('仅首次', 'First time'),
      3: _text('从不', 'Never'),
    };
    final pushOptions = <int, String>{
      0: _text('无', 'None'),
      1: _text('全部', 'All'),
      2: _text('仅聊天', 'Chat only'),
    };
    final replyTrackingOptions = <int, String>{
      3: _text('关注', 'Watching'),
      2: _text('跟踪', 'Tracking'),
      1: _text('常规', 'Regular'),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_sync_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _text(
                      '这里修改的是 Discourse 社区账户设置，会同步到网页版和其他客户端；它与 FluxDO 本地设置彼此独立。',
                      'These are server-side Discourse account settings. They sync with the web UI and other clients and are separate from FluxDO local settings.',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _sectionTitle(_text('账户', 'Account')),
        if (_initial.canEditName) ...[
          _field(
            controller: _nameController,
            label: _text('姓名', 'Name'),
          ),
          const SizedBox(height: 12),
        ],
        if (_initial.canEdit &&
            (_initial.availableTitles.isNotEmpty ||
                _initial.availablePrimaryGroups.isNotEmpty ||
                _initial.primaryGroupId != null ||
                _initial.availableFlairGroups.isNotEmpty ||
                _initial.flairGroupId != null))
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _titleChoice(),
                if (_initial.userSelectedPrimaryGroups)
                  _groupChoice(
                    title: _text('主要群组', 'Primary group'),
                    value: _primaryGroupId,
                    groups: _initial.availablePrimaryGroups,
                    onChanged: (value) =>
                        setState(() => _primaryGroupId = value),
                  ),
                _groupChoice(
                  title: _text('徽标群组', 'Flair group'),
                  value: _flairGroupId,
                  groups: _initial.availableFlairGroups,
                  onChanged: (value) => setState(() => _flairGroupId = value),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        _sectionTitle(_text('资料', 'Profile')),
        if (_initial.canChangeBio) ...[
          _field(
            controller: _bioController,
            label: _text('个人简介', 'About me'),
            maxLines: 5,
          ),
          const SizedBox(height: 12),
        ],
        if (_initial.canChangeLocation) ...[
          _field(
            controller: _locationController,
            label: _text('位置', 'Location'),
          ),
          const SizedBox(height: 12),
        ],
        if (_initial.canChangeWebsite) ...[
          _field(
            controller: _websiteController,
            label: _text('网站', 'Website'),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
        ],
        if (canEditTimezone) ...[
          _field(
            controller: _timezoneController,
            label: _text('时区', 'Timezone'),
            hintText: 'Asia/Shanghai',
          ),
          const SizedBox(height: 12),
        ],
        _sectionTitle(_text('邮件', 'Email')),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _selectOption(
                keyName: 'email_level',
                title: _text('主题邮件通知', 'Topic email notifications'),
                value: _emailLevel,
                options: emailDeliveryOptions,
                onChanged: (value) => setState(() => _emailLevel = value),
              ),
              _selectOption(
                keyName: 'email_messages_level',
                title: _text('私信邮件通知', 'Message email notifications'),
                value: _emailMessagesLevel,
                options: emailDeliveryOptions,
                onChanged: (value) =>
                    setState(() => _emailMessagesLevel = value),
              ),
              _toggle(
                keyName: 'email_digests',
                title: _text('邮件摘要', 'Email digests'),
                value: _emailDigests,
                onChanged: (value) => setState(() => _emailDigests = value),
              ),
              _toggle(
                keyName: 'include_tl0_in_digests',
                title: _text('摘要包含新用户内容', 'Include new users in digests'),
                value: _includeTl0InDigests,
                onChanged: (value) =>
                    setState(() => _includeTl0InDigests = value),
              ),
              _toggle(
                keyName: 'mailing_list_mode',
                title: _text('邮件列表模式', 'Mailing list mode'),
                value: _mailingListMode,
                onChanged: (value) => setState(() => _mailingListMode = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionTitle(_text('通知与隐私', 'Notifications & privacy')),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _selectOption(
                keyName: 'like_notification_frequency',
                title: _text('点赞通知频率', 'Like notification frequency'),
                value: _likeNotificationFrequency,
                options: likeOptions,
                onChanged: (value) =>
                    setState(() => _likeNotificationFrequency = value),
              ),
              _selectOption(
                keyName: 'push_notification_level',
                title: _text('推送通知', 'Push notifications'),
                value: _pushNotificationLevel,
                options: pushOptions,
                onChanged: (value) =>
                    setState(() => _pushNotificationLevel = value),
              ),
              _selectOption(
                keyName: 'notification_level_when_replying',
                title: _text('回复后的话题级别', 'Topic level after replying'),
                value: _notificationLevelWhenReplying,
                options: replyTrackingOptions,
                onChanged: (value) =>
                    setState(() => _notificationLevelWhenReplying = value),
              ),
              _toggle(
                keyName: 'allow_private_messages',
                title: _text('允许私信', 'Allow private messages'),
                value: _allowPrivateMessages,
                onChanged: (value) =>
                    setState(() => _allowPrivateMessages = value),
              ),
              _toggle(
                keyName: 'hide_profile',
                title: _text('隐藏个人资料', 'Hide profile'),
                value: _hideProfile,
                onChanged: (value) => setState(() => _hideProfile = value),
              ),
              _toggle(
                keyName: 'hide_presence',
                title: _text('隐藏在线状态', 'Hide presence'),
                value: _hidePresence,
                onChanged: (value) => setState(() => _hidePresence = value),
              ),
              _toggle(
                keyName: 'notify_on_linked_posts',
                title: _text('链接到我的帖子时通知', 'Notify on linked posts'),
                value: _notifyOnLinkedPosts,
                onChanged: (value) =>
                    setState(() => _notifyOnLinkedPosts = value),
              ),
              _toggle(
                keyName: 'watched_precedence_over_muted',
                title: _text('关注优先于静音', 'Watched takes precedence over muted'),
                value: _watchedPrecedenceOverMuted,
                onChanged: (value) =>
                    setState(() => _watchedPrecedenceOverMuted = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionTitle(_text('界面与阅读', 'Interface & reading')),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _toggle(
                keyName: 'external_links_in_new_tab',
                title: _text('外部链接在新窗口打开', 'Open external links separately'),
                value: _externalLinksInNewTab,
                onChanged: (value) =>
                    setState(() => _externalLinksInNewTab = value),
              ),
              _toggle(
                keyName: 'enable_quoting',
                title: _text('启用引用', 'Enable quoting'),
                value: _enableQuoting,
                onChanged: (value) => setState(() => _enableQuoting = value),
              ),
              _toggle(
                keyName: 'dynamic_favicon',
                title: _text('动态站点图标', 'Dynamic favicon'),
                value: _dynamicFavicon,
                onChanged: (value) => setState(() => _dynamicFavicon = value),
              ),
              _toggle(
                keyName: 'automatically_unpin_topics',
                title: _text('阅读后自动取消置顶', 'Automatically unpin read topics'),
                value: _automaticallyUnpinTopics,
                onChanged: (value) =>
                    setState(() => _automaticallyUnpinTopics = value),
              ),
              _toggle(
                keyName: 'skip_new_user_tips',
                title: _text('跳过新用户提示', 'Skip new-user tips'),
                value: _skipNewUserTips,
                onChanged: (value) => setState(() => _skipNewUserTips = value),
              ),
              _toggle(
                keyName: 'sidebar_link_to_filtered_list',
                title: _text('侧栏链接到筛选列表', 'Sidebar links to filtered lists'),
                value: _sidebarLinkToFilteredList,
                onChanged: (value) =>
                    setState(() => _sidebarLinkToFilteredList = value),
              ),
              _toggle(
                keyName: 'sidebar_show_count_of_new_items',
                title: _text('侧栏显示新项目数量', 'Show new-item counts in sidebar'),
                value: _sidebarShowCountOfNewItems,
                onChanged: (value) =>
                    setState(() => _sidebarShowCountOfNewItems = value),
              ),
              _toggle(
                keyName: 'automatically_translate',
                title: _text('自动翻译', 'Automatically translate'),
                value: _automaticallyTranslate,
                onChanged: (value) =>
                    setState(() => _automaticallyTranslate = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _initial.canEdit && !_saving ? _save : null,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_upload_outlined),
          label: Text(_text('保存并同步', 'Save and sync')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _saving ? null : _openWebPreferences,
          icon: const Icon(Icons.open_in_browser_rounded),
          label: Text(_text('打开完整网页设置', 'Open full web preferences')),
        ),
        if (!_initial.canEdit) ...[
          const SizedBox(height: 12),
          Text(
            _text(
              '服务器没有授予当前会话编辑权限；这里只显示可读取的账户状态。',
              'The server did not grant edit permission to this session; this page is read-only.',
            ),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
