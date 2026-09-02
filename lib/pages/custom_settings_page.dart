import 'package:flutter/material.dart';

import '../settings/definitions/custom_settings_defs.dart';
import '../widgets/settings/settings_group_page.dart';

class CustomSettingsPage extends StatelessWidget {
  final String? highlightId;

  const CustomSettingsPage({super.key, this.highlightId});

  static String titleFor(BuildContext context) {
    final locale = Localizations.localeOf(context);
    if (locale.languageCode != 'zh') return 'Custom settings';
    if (locale.scriptCode?.toLowerCase() == 'hant' ||
        locale.countryCode == 'TW' ||
        locale.countryCode == 'HK' ||
        locale.countryCode == 'MO') {
      return '自訂設定';
    }
    return '自定义设置';
  }

  @override
  Widget build(BuildContext context) {
    return SettingsGroupPage(
      title: titleFor(context),
      groupsBuilder: buildCustomSettingsGroups,
      highlightId: highlightId,
    );
  }
}
