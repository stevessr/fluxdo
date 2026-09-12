// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_provider.dart';

/// 快速阅读设置。
///
/// 默认关闭，避免升级后在用户不知情的情况下把进入的话题直接标记为已读。
class QuickReadingPreferences {
  const QuickReadingPreferences({this.enabled = false});

  final bool enabled;

  QuickReadingPreferences copyWith({bool? enabled}) {
    return QuickReadingPreferences(enabled: enabled ?? this.enabled);
  }
}

class QuickReadingPreferencesNotifier
    extends StateNotifier<QuickReadingPreferences> {
  /// ScreenTrack 也会直接读取这个 key，因此保持为公开常量，避免两处写死。
  static const enabledKey = 'pref_quick_reading_enabled';

  QuickReadingPreferencesNotifier(this._prefs)
    : super(
        QuickReadingPreferences(
          enabled: _prefs.getBool(enabledKey) ?? false,
        ),
      );

  final SharedPreferences _prefs;

  Future<void> setEnabled(bool enabled) async {
    if (state.enabled == enabled) return;
    state = state.copyWith(enabled: enabled);
    await _prefs.setBool(enabledKey, enabled);
  }
}

final quickReadingPreferencesProvider = StateNotifierProvider<
  QuickReadingPreferencesNotifier,
  QuickReadingPreferences
>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return QuickReadingPreferencesNotifier(prefs);
});
