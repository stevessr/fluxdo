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
                    leading: Icon(Icons.touch_app_outlined, color: scheme.primary),
                    title: Text(copy.holdDurationTitle),
                    subtitle: Text(
                      copy.holdDurationValue(preferences.holdDurationMs),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showHoldDurationPicker(
                      context,
                      current: preferences.holdDurationMs,
                      copy: copy,
                      onChanged: (milliseconds) => ref
                          .read(accountQuickSwitcherPreferencesProvider.notifier)
                          .setHoldDurationMs(milliseconds),
                    ),
                  ),
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

void _showHoldDurationPicker(
  BuildContext context, {
  required int current,
  required _AccountQuickSwitcherCopy copy,
  required ValueChanged<int> onChanged,
}) {
  var draft = current
      .clamp(
        AccountQuickSwitcherPreferences.minHoldDurationMs,
        AccountQuickSwitcherPreferences.maxHoldDurationMs,
      )
      .toDouble();

  AppBottomSheet.show<void>(
    context: context,
    title: copy.holdDurationTitle,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final milliseconds = draft.round();
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  copy.holdDurationDescription,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  copy.holdDurationValue(milliseconds),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Slider(
                  min: AccountQuickSwitcherPreferences.minHoldDurationMs
                      .toDouble(),
                  max: AccountQuickSwitcherPreferences.maxHoldDurationMs
                      .toDouble(),
                  divisions:
                      (AccountQuickSwitcherPreferences.maxHoldDurationMs -
                          AccountQuickSwitcherPreferences.minHoldDurationMs) ~/
                      100,
                  value: draft,
                  label: copy.holdDurationValue(milliseconds),
                  onChanged: (value) {
                    setSheetState(() => draft = value);
                  },
                  onChangeEnd: (value) {
                    HapticFeedback.selectionClick();
                    onChanged(value.round());
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      copy.holdDurationValue(
                        AccountQuickSwitcherPreferences.minHoldDurationMs,
                      ),
                    ),
                    Text(
                      copy.holdDurationValue(
                        AccountQuickSwitcherPreferences.maxHoldDurationMs,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
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
    required this.holdDurationTitle,
    required this.holdDurationDescription,
    required this.millisecondsUnit,
    required this.secondsUnit,
    required this.triggerTitle,
    required this.releaseTitle,
    required this.releaseDescription,
    required this.dwellTitle,
    required this.dwellDescription,
  });

  final String groupTitle;
  final String radialTitle;
  final String radialDescription;
  final String holdDurationTitle;
  final String holdDurationDescription;
  final String millisecondsUnit;
  final String secondsUnit;
  final String triggerTitle;
  final String releaseTitle;
  final String releaseDescription;
  final String dwellTitle;
  final String dwellDescription;

  String holdDurationValue(int milliseconds) {
    if (milliseconds % 1000 == 0) {
      return '${milliseconds ~/ 1000} $secondsUnit';
    }
    if (milliseconds > 1000) {
      final seconds = (milliseconds / 1000).toStringAsFixed(1);
      return '$seconds $secondsUnit';
    }
    return '$milliseconds $millisecondsUnit';
  }

  static _AccountQuickSwitcherCopy of(BuildContext context) {
    final locale = Localizations.localeOf(context);
    if (locale.languageCode != 'zh') return _en;
    if (locale.countryCode == 'TW' || locale.countryCode == 'HK') return _zhHant;
    return _zhHans;
  }

  static const _zhHans = _AccountQuickSwitcherCopy(
    groupTitle: '账号快速切换',
    radialTitle: '伞状账号切换',
    radialDescription: '以长按入口为圆心，只向屏幕内侧展开约 90° 多层圆弧；当前账号固定在圆心，账号管理位于最外层中间。',
    holdDurationTitle: '长按触发时间',
    holdDurationDescription: '按住时入口外围会显示进度环，并随进度逐级增强振动；松开或手势取消后立即归零。',
    millisecondsUnit: '毫秒',
    secondsUnit: '秒',
    triggerTitle: '选中账号触发方式',
    releaseTitle: '释放时切换',
    releaseDescription: '滑到目标账号后松手立即切换。',
    dwellTitle: '停留 5 秒后切换',
    dwellDescription: '停留时头像外圈显示进度；进度走满才切换，移开或提前松手会取消。',
  );

  static const _zhHant = _AccountQuickSwitcherCopy(
    groupTitle: '帳號快速切換',
    radialTitle: '傘狀帳號切換',
    radialDescription: '以長按入口為圓心，只向螢幕內側展開約 90° 多層圓弧；目前帳號固定在圓心，帳號管理位於最外層中間。',
    holdDurationTitle: '長按觸發時間',
    holdDurationDescription: '按住時入口外圍會顯示進度環，並隨進度逐級增強震動；放開或手勢取消後立即歸零。',
    millisecondsUnit: '毫秒',
    secondsUnit: '秒',
    triggerTitle: '選中帳號觸發方式',
    releaseTitle: '放開時切換',
    releaseDescription: '滑到目標帳號後放開即切換。',
    dwellTitle: '停留 5 秒後切換',
    dwellDescription: '停留時頭像外圈會顯示進度；進度完成才切換，移開或提前放開會取消。',
  );

  static const _en = _AccountQuickSwitcherCopy(
    groupTitle: 'Account quick switching',
    radialTitle: 'Radial account switcher',
    radialDescription: 'Use the pressed entry as the pivot and open only an inward-facing ~90° multi-layer arc. The current account stays at the pivot and account management sits at the middle of the outermost arc.',
    holdDurationTitle: 'Long-press duration',
    holdDurationDescription: 'A progress ring appears around the entry while holding. Haptics become progressively stronger as the hold approaches completion; releasing or cancellation resets it.',
    millisecondsUnit: 'ms',
    secondsUnit: 's',
    triggerTitle: 'Account selection trigger',
    releaseTitle: 'Switch on release',
    releaseDescription: 'Slide to an account and release to switch immediately.',
    dwellTitle: 'Switch after a 5-second dwell',
    dwellDescription: 'A progress ring appears around the hovered avatar. Moving away or releasing early cancels the switch.',
  );
}
