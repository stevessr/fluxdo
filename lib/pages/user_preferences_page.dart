import 'package:flutter/material.dart';

import 'discourse_account_danger_page.dart';
import 'discourse_avatar_page.dart';
import 'discourse_calendar_subscriptions_page.dart';
import 'discourse_identity_profile_page.dart';
import 'discourse_interface_advanced_page.dart';
import 'discourse_language_page.dart';
import 'discourse_notification_schedule_page.dart';
import 'discourse_passkeys_management_page.dart';
import 'discourse_profile_extras_page.dart';
import 'discourse_security_advanced_page.dart';
import 'discourse_tracking_selectors_page.dart';
import 'discourse_user_filters_page.dart';
import 'user_account_management_page.dart';
import 'user_preferences_core_page.dart' as core;

/// Complete native Discourse preferences surface.
///
/// The field-oriented preferences live in [core.UserPreferencesPage]. Actions
/// that need richer server context are grouped behind one native "More" entry
/// instead of stacking multiple floating buttons over the preferences content.
class UserPreferencesPage extends StatelessWidget {
  final String username;

  const UserPreferencesPage({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Stack(
      children: [
        Positioned.fill(child: core.UserPreferencesPage(username: username)),
        Positioned(
          right: 16,
          bottom: 16,
          child: SafeArea(
            child: FloatingActionButton.extended(
              heroTag: 'user-preferences-more',
              onPressed: () => _showMoreActions(context, zh),
              icon: const Icon(Icons.tune_outlined),
              label: Text(zh ? '更多设置' : 'More settings'),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showMoreActions(BuildContext context, bool zh) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(zh ? '头像' : 'Avatar'),
                  subtitle: Text(
                    zh
                        ? '系统头像、自定义上传、Gravatar、站点预设头像'
                        : 'System, uploaded, Gravatar, and site-provided avatars',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DiscourseAvatarPage(username: username),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(zh ? '身份与个人资料' : 'Identity & profile'),
                  subtitle: Text(
                    zh
                        ? '头衔、资质、主要群组、自定义状态、时区、地点、网站等'
                        : 'Title, flair, primary group, custom status, timezone, location, website, and more',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            DiscourseIdentityProfilePage(username: username),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: Text(zh ? '资料背景与精选话题' : 'Profile media & featured topic'),
                  subtitle: Text(
                    zh
                        ? '个人资料背景、用户卡片背景、个人资料精选话题'
                        : 'Profile background, user-card background, and featured topic',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            DiscourseProfileExtrasPage(username: username),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: Text(zh ? '界面高级设置' : 'Advanced interface'),
                  subtitle: Text(
                    zh
                        ? 'Discourse 主题、配色、发送快捷键、书签行为、内容语言'
                        : 'Discourse theme, palettes, send shortcut, bookmark behavior, and content languages',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DiscourseInterfaceAdvancedPage(
                          username: username,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: Text(zh ? '通知时间表' : 'Notification schedule'),
                  subtitle: Text(
                    zh
                        ? '推送范围与周一到周日通知时间窗口'
                        : 'Push scope and Monday–Sunday notification windows',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DiscourseNotificationSchedulePage(
                          username: username,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.track_changes_outlined),
                  title: Text(zh ? '分类与标签跟踪' : 'Category & tag tracking'),
                  subtitle: Text(
                    zh
                        ? '按名称选择关注、跟踪、首帖关注、静音分类和标签'
                        : 'Select watched, tracked, first-post, and muted categories/tags by name',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DiscourseTrackingSelectorsPage(
                          username: username,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: Text(zh ? '用户过滤与私信' : 'Users & private messages'),
                  subtitle: Text(
                    zh
                        ? '搜索管理忽略/静音用户、允许私信用户和私信权限'
                        : 'Search and manage ignored/muted users, allowed PM users, and PM permissions',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DiscourseUserFiltersPage(
                          username: username,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: Text(zh ? '日历订阅' : 'Calendar subscriptions'),
                  subtitle: Text(
                    zh
                        ? '生成、轮换、复制或撤销 Discourse 私密 ICS feeds'
                        : 'Generate, rotate, copy, or revoke private Discourse ICS feeds',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DiscourseCalendarSubscriptionsPage(
                          username: username,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(zh ? 'Discourse 语言' : 'Discourse language'),
                  subtitle: Text(
                    zh
                        ? '修改论坛账户的界面语言'
                        : 'Change the forum account interface language',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DiscourseLanguagePage(username: username),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.security_outlined),
                  title: Text(zh ? '密码与授权应用' : 'Password & authorized apps'),
                  subtitle: Text(
                    zh
                        ? '设置或移除密码、重发邮箱验证、管理 User API 授权'
                        : 'Set/remove password, resend email verification, and manage User API authorizations',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DiscourseSecurityAdvancedPage(
                          username: username,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: Text(zh ? '已有 Passkey' : 'Existing Passkeys'),
                  subtitle: Text(
                    zh
                        ? '查看、重命名或删除已经注册的 Passkey；不创建新的 Passkey'
                        : 'View, rename, or delete registered Passkeys without creating new ones',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DiscoursePasskeysManagementPage(
                          username: username,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: Text(zh ? '账户与安全' : 'Account & security'),
                  subtitle: Text(
                    zh
                        ? '邮箱、关联账户、TOTP、备份码、登录设备等'
                        : 'Email, linked accounts, TOTP, backup codes, sessions, and more',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            UserAccountManagementPage(username: username),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(zh ? '账户危险操作' : 'Account danger zone'),
                  subtitle: Text(
                    zh
                        ? '按 Discourse 服务器权限永久删除账户'
                        : 'Permanently delete the account when Discourse allows it',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DiscourseAccountDangerPage(
                          username: username,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
