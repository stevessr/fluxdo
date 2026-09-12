import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';

import '../../providers/quick_reading_preferences.dart';
import 'account_quick_switcher_appearance_defs.dart';
import '../settings_model.dart';

/// 自定义设置数据声明。
List<SettingsGroup> buildCustomSettingsGroups(BuildContext context) {
  final copy = _CustomSettingsCopy.of(context);
  return [
    SettingsGroup(
      title: copy.readingGroupTitle,
      icon: Symbols.auto_stories_rounded,
      items: [
        SwitchModel(
          id: 'quickReading',
          title: copy.quickReadingTitle,
          subtitle: copy.quickReadingDescription,
          icon: Symbols.speed_rounded,
          getValue: (ref) => ref.watch(quickReadingPreferencesProvider).enabled,
          onChanged: (ref, value) => ref
              .read(quickReadingPreferencesProvider.notifier)
              .setEnabled(value),
        ),
      ],
    ),
    buildAccountQuickSwitcherAppearanceGroup(context),
  ];
}

class _CustomSettingsCopy {
  const _CustomSettingsCopy({
    required this.readingGroupTitle,
    required this.quickReadingTitle,
    required this.quickReadingDescription,
  });

  final String readingGroupTitle;
  final String quickReadingTitle;
  final String quickReadingDescription;

  static _CustomSettingsCopy of(BuildContext context) {
    final locale = Localizations.localeOf(context);
    if (locale.languageCode != 'zh') return _en;
    if (locale.scriptCode?.toLowerCase() == 'hant' ||
        locale.countryCode == 'TW' ||
        locale.countryCode == 'HK' ||
        locale.countryCode == 'MO') {
      return _zhHant;
    }
    return _zhHans;
  }

  static const _zhHans = _CustomSettingsCopy(
    readingGroupTitle: '阅读增强',
    quickReadingTitle: '快速阅读',
    quickReadingDescription:
        '进入话题时立即上报当前所有未读楼层；超过 2000 个楼层时按每批 2000 个分批发送。',
  );

  static const _zhHant = _CustomSettingsCopy(
    readingGroupTitle: '閱讀增強',
    quickReadingTitle: '快速閱讀',
    quickReadingDescription:
        '進入話題時立即上報目前所有未讀樓層；超過 2000 個樓層時按每批 2000 個分批傳送。',
  );

  static const _en = _CustomSettingsCopy(
    readingGroupTitle: 'Reading enhancements',
    quickReadingTitle: 'Quick reading',
    quickReadingDescription:
        'Immediately reports every currently unread post when entering a topic. More than 2,000 posts are sent in batches of 2,000.',
  );
}
