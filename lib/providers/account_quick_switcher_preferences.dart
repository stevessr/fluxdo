// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_provider.dart';

enum AccountQuickSwitchTrigger {
  release,
  dwellFiveSeconds;

  static AccountQuickSwitchTrigger fromString(String? value) {
    return AccountQuickSwitchTrigger.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => AccountQuickSwitchTrigger.release,
    );
  }
}

class AccountQuickSwitcherPreferences {
  static const int defaultHoldDurationMs = 500;
  static const int minHoldDurationMs = 300;
  static const int maxHoldDurationMs = 2000;

  const AccountQuickSwitcherPreferences({
    this.radialEnabled = false,
    this.trigger = AccountQuickSwitchTrigger.release,
    this.holdDurationMs = defaultHoldDurationMs,
  });

  final bool radialEnabled;
  final AccountQuickSwitchTrigger trigger;

  /// 长按入口进入伞状切换器所需时间。
  ///
  /// 与进入切换器后的“停留 5 秒切换账号”是两套独立计时器。
  final int holdDurationMs;

  Duration get holdDuration => Duration(milliseconds: holdDurationMs);

  AccountQuickSwitcherPreferences copyWith({
    bool? radialEnabled,
    AccountQuickSwitchTrigger? trigger,
    int? holdDurationMs,
  }) {
    return AccountQuickSwitcherPreferences(
      radialEnabled: radialEnabled ?? this.radialEnabled,
      trigger: trigger ?? this.trigger,
      holdDurationMs: holdDurationMs ?? this.holdDurationMs,
    );
  }
}

class AccountQuickSwitcherPreferencesNotifier
    extends StateNotifier<AccountQuickSwitcherPreferences> {
  static const _radialEnabledKey = 'pref_account_switcher_radial_enabled';
  static const _triggerKey = 'pref_account_switcher_trigger';
  static const _holdDurationKey = 'pref_account_switcher_hold_duration_ms';

  AccountQuickSwitcherPreferencesNotifier(this._prefs)
    : super(
        AccountQuickSwitcherPreferences(
          radialEnabled: _prefs.getBool(_radialEnabledKey) ?? false,
          trigger: AccountQuickSwitchTrigger.fromString(
            _prefs.getString(_triggerKey),
          ),
          holdDurationMs: _normalizeHoldDuration(
            _prefs.getInt(_holdDurationKey) ??
                AccountQuickSwitcherPreferences.defaultHoldDurationMs,
          ),
        ),
      );

  final SharedPreferences _prefs;

  static int _normalizeHoldDuration(int milliseconds) {
    return milliseconds
        .clamp(
          AccountQuickSwitcherPreferences.minHoldDurationMs,
          AccountQuickSwitcherPreferences.maxHoldDurationMs,
        )
        .toInt();
  }

  Future<void> setRadialEnabled(bool enabled) async {
    if (state.radialEnabled == enabled) return;
    state = state.copyWith(radialEnabled: enabled);
    await _prefs.setBool(_radialEnabledKey, enabled);
  }

  Future<void> setTrigger(AccountQuickSwitchTrigger trigger) async {
    if (state.trigger == trigger) return;
    state = state.copyWith(trigger: trigger);
    await _prefs.setString(_triggerKey, trigger.name);
  }

  Future<void> setHoldDurationMs(int milliseconds) async {
    final normalized = _normalizeHoldDuration(milliseconds);
    if (state.holdDurationMs == normalized) return;
    state = state.copyWith(holdDurationMs: normalized);
    await _prefs.setInt(_holdDurationKey, normalized);
  }
}

final accountQuickSwitcherPreferencesProvider = StateNotifierProvider<
  AccountQuickSwitcherPreferencesNotifier,
  AccountQuickSwitcherPreferences
>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AccountQuickSwitcherPreferencesNotifier(prefs);
});
