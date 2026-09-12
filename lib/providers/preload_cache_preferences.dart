// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/preload_cache_service.dart';
import 'theme_provider.dart';

/// preload cache 实验开关。
///
/// 默认开启；关闭后网络层立即停止读取和写入持久缓存，已有缓存保留到
/// 7 天自动过期或用户在「自定义实验」中统一清理。
class PreloadCachePreferences {
  const PreloadCachePreferences({this.enabled = true});

  final bool enabled;

  PreloadCachePreferences copyWith({bool? enabled}) {
    return PreloadCachePreferences(enabled: enabled ?? this.enabled);
  }
}

class PreloadCachePreferencesNotifier
    extends StateNotifier<PreloadCachePreferences> {
  PreloadCachePreferencesNotifier(this._prefs)
    : super(
        PreloadCachePreferences(
          enabled:
              _prefs.getBool(PreloadCacheService.enabledPreferenceKey) ?? true,
        ),
      );

  final SharedPreferences _prefs;

  Future<void> setEnabled(bool enabled) async {
    if (state.enabled == enabled) return;
    state = state.copyWith(enabled: enabled);
    await _prefs.setBool(PreloadCacheService.enabledPreferenceKey, enabled);
  }
}

final preloadCachePreferencesProvider = StateNotifierProvider<
  PreloadCachePreferencesNotifier,
  PreloadCachePreferences
>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return PreloadCachePreferencesNotifier(prefs);
});
