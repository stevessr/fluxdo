import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../providers/account_quick_switcher_preferences.dart';
import '../../widgets/common/app_bottom_sheet.dart';
import '../settings_model.dart';

SettingsGroup buildAccountQuickSwitcherAppearanceGroup(BuildContext context) {
  final copy = _AccountQuickSwitcherCopy.of(context);
  return SettingsGroup(
    title: copy.groupTitle,
    icon: Icons.manage_accounts_outlined,
    wrapInCard: false,
    items: [
      CustomModel(
        id: 'radialAccountSwitcher',
        title: copy.radialTitle,
        builder: (context, ref) {
          final preferences = ref.watch(accountQuickSwitcherPreferencesProvider);
          final scheme = Theme.of(context).colorScheme;
          return Material(
            color: scheme.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  secondary: Icon(
                    Icons.account_tree_outlined,
                    color: preferences.radialEnabled
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  title: Text(copy.radialTitle),
                  subtitle: Text(copy.radialDescription),
                  value: preferences.radialEnabled,
                  onChanged: (enabled) {
                    HapticFeedback.selectionClick();
                    ref
                        .read(accountQuickSwitcherPreferencesProvider.notifier)
                        .setRadialEnabled(enabled);
                  },
                ),
                if (preferences.radialEnabled) ...[
                  Divider(
                    height: 1,
                    indent: 56,
                    color: scheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                  ListTile(
                    leading: Icon(
                      preferences.trigger == AccountQuickSwitchTrigger.release
                          ? Icons.touch_app_outlined
                          : Icons.timer_outlined,
                      color: scheme.primary,
                    ),
                    title: Text(copy.triggerTitle),
                    subtitle: Text(
                      preferences.trigger == AccountQuickSwitchTrigger.release
                          ? copy.releaseTitle
                          : copy.dwellTitle,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showTriggerPicker(
                      context,
                      current: preferences.trigger,
                      copy: copy,
                      onChanged: (trigger) => ref
                          .read(accountQuickSwitcherPreferencesProvider.notifier)
                          .setTrigger(trigger),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    ],
  );
}

void _showTriggerPicker(
  BuildContext context, {
  required AccountQuickSwitchTrigger current,
  required _AccountQuickSwitcherCopy copy,
  required ValueChanged<AccountQuickSwitchTrigger> onChanged,
}) {
  AppBottomSheet.show<void>(
    context: context,
    title: copy.triggerTitle,
    builder: (sheetContext) {
      return RadioGroup<AccountQuickSwitchTrigger>(
        groupValue: current,
        onChanged: (value) {
          if (value == null) return;
          HapticFeedback.selectionClick();
          onChanged(value);
          Navigator.pop(sheetContext);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<AccountQuickSwitchTrigger>(
              value: AccountQuickSwitchTrigger.release,
              secondary: const Icon(Icons.touch_app_outlined),
              title: Text(copy.releaseTitle),
              subtitle: Text(copy.releaseDescription),
            ),
            RadioListTile<AccountQuickSwitchTrigger>(
              value: AccountQuickSwitchTrigger.dwellFiveSeconds,
              secondary: const Icon(Icons.timer_outlined),
              title: Text(copy.dwellTitle),
              subtitle: Text(copy.dwellDescription),
            ),
          ],
        ),
      );
    },
  );
}

class _AccountQuickSwitcherCopy {
  const _AccountQuickSwitcherCopy({
    required this.groupTitle,
    required this.radialTitle,
    required this.radialDescription,
    required this.triggerTitle,
    required this.releaseTitle,
    required this.releaseDescription,
    required this.dwellTitle,
    required this.dwellDescription,
  });

  final String groupTitle;
  final String radialTitle;
  final String radialDescription;
  final String triggerTitle;
  final String releaseTitle;
  final String releaseDescription;
  final String dwellTitle;
  final String dwellDescription;

  static _AccountQuickSwitcherCopy of(BuildContext context) {
    final locale = Localizations.localeOf(context);
    if (locale.languageCode != 'zh') return _en;
    if (locale.countryCode == 'TW' || locale.countryCode == 'HK') return _zhHant;
    return _zhHans;
  }

  static const _zhHans = _AccountQuickSwitcherCopy(
    groupTitle: '账号快速切换',
    radialTitle: '伞状账号切换',
    radialDescription: '长按账号入口时，根据账号数量和可视区域自动排列为多层圆环；当前账号位于圆心。',
    triggerTitle: '切换触发方式',
    releaseTitle: '释放时切换',
    releaseDescription: '滑到目标账号后松手立即切换。',
    dwellTitle: '停留 5 秒后切换',
    dwellDescription: '停留时头像外圈显示进度；进度走满才切换，移开或提前松手会取消。',
  );

  static const _zhHant = _AccountQuickSwitcherCopy(
    groupTitle: '帳號快速切換',
    radialTitle: '傘狀帳號切換',
    radialDescription: '長按帳號入口時，依帳號數量與可視區域自動排列為多層圓環；目前帳號位於圓心。',
    triggerTitle: '切換觸發方式',
    releaseTitle: '放開時切換',
    releaseDescription: '滑到目標帳號後放開即切換。',
    dwellTitle: '停留 5 秒後切換',
    dwellDescription: '停留時頭像外圈會顯示進度；進度完成才切換，移開或提前放開會取消。',
  );

  static const _en = _AccountQuickSwitcherCopy(
    groupTitle: 'Account quick switching',
    radialTitle: 'Radial account switcher',
    radialDescription: 'On long press, arrange accounts into adaptive concentric rings. The current account stays in the center.',
    triggerTitle: 'Switch trigger',
    releaseTitle: 'Switch on release',
    releaseDescription: 'Slide to an account and release to switch immediately.',
    dwellTitle: 'Switch after a 5-second dwell',
    dwellDescription: 'A progress ring appears around the hovered avatar. Moving away or releasing early cancels the switch.',
  );
}
