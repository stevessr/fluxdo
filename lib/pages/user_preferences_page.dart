import 'package:flutter/material.dart';

import 'discourse_language_page.dart';
import 'user_account_management_page.dart';
import 'user_preferences_core_page.dart' as core;

/// Complete native Discourse preferences surface.
///
/// The field-oriented preferences live in [core.UserPreferencesPage]. Account,
/// security, and site-locale actions that need additional server context are
/// exposed through the persistent actions below.
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'user-preferences-language',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DiscourseLanguagePage(username: username),
                    ),
                  ),
                  icon: const Icon(Icons.language_outlined),
                  label: Text(zh ? 'Discourse 语言' : 'Discourse language'),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'user-preferences-account-management',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          UserAccountManagementPage(username: username),
                    ),
                  ),
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: Text(zh ? '账户与安全' : 'Account & security'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
