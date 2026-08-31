import 'package:flutter/material.dart';

import 'user_account_management_page.dart';
import 'user_preferences_core_page.dart' as core;

/// Complete native Discourse preferences surface.
///
/// The field-oriented preferences live in [core.UserPreferencesPage]. Account
/// and security actions that require dedicated Discourse endpoints are exposed
/// through the persistent management action below.
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
              heroTag: 'user-preferences-account-management',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => UserAccountManagementPage(username: username),
                ),
              ),
              icon: const Icon(Icons.manage_accounts_outlined),
              label: Text(zh ? '账户与安全' : 'Account & security'),
            ),
          ),
        ),
      ],
    );
  }
}
