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
  const AccountQuickSwitcherPreferences({
    this.radialEnabled = false,
    this.trigger = AccountQuickSwitchTrigger.release,
  });

  final bool radialEnabled;
  final AccountQuickSwitchTrigger trigger;

  AccountQuickSwitcherPreferences copyWith({
    bool? radialEnabled,
    AccountQuickSwitchTrigger? trigger,
  }) {
    return AccountQuickSwitcherPreferences(
      radialEnabled: radialEnabled ?? this.radialEnabled,
      trigger: trigger ?? this.trigger,
    );
  }
}

class AccountQuickSwitcherPreferencesNotifier
    extends StateNotifier<AccountQuickSwitcherPreferences> {
  static const _radialEnabledKey = 'pref_account_switcher_radial_enabled';
  static const _triggerKey = 'pref_account_switcher_trigger';

  AccountQuickSwitcherPreferencesNotifier(this._prefs)
    : super(
        AccountQuickSwitcherPreferences(
          radialEnabled: _prefs.getBool(_radialEnabledKey) ?? false,
          trigger: AccountQuickSwitchTrigger.fromString(
            _prefs.getString(_triggerKey),
          ),
        ),
      );

  final SharedPreferences _prefs;

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
}

final accountQuickSwitcherPreferencesProvider = StateNotifierProvider<
  AccountQuickSwitcherPreferencesNotifier,
  AccountQuickSwitcherPreferences
>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AccountQuickSwitcherPreferencesNotifier(prefs);
});
