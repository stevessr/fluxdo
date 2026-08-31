import 'package:flutter/material.dart';

import 'discourse_identity_profile_page.dart';
import 'discourse_language_page.dart';
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
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
            ],
          ),
        ),
      ),
    );
  }
}
