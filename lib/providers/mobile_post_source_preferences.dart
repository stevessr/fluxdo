import 'dart:async';

// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/mobile_post_source_service.dart';
import 'theme_provider.dart';

class MobilePostSourcePreferences {
  const MobilePostSourcePreferences({
    this.enabled = false,
    this.customModel,
    this.detectedInfo,
    this.detecting = true,
  });

  final bool enabled;
  final String? customModel;
  final MobilePostSourceInfo? detectedInfo;
  final bool detecting;

  String? get effectiveModel => customModel ?? detectedInfo?.model;
}

class MobilePostSourcePreferencesNotifier
    extends StateNotifier<MobilePostSourcePreferences> {
  MobilePostSourcePreferencesNotifier(this._prefs)
    : super(
        MobilePostSourcePreferences(
          enabled:
              _prefs.getBool(MobilePostSourceService.enabledKey) ?? false,
          customModel: MobilePostSourceService.normalizeCustomModel(
            _prefs.getString(MobilePostSourceService.customModelKey),
          ),
        ),
      ) {
    unawaited(_loadDetectedDevice());
  }

  final SharedPreferences _prefs;

  Future<void> _loadDetectedDevice() async {
    final info = await MobilePostSourceService.detectDeviceInfo();
    state = MobilePostSourcePreferences(
      enabled: state.enabled,
      customModel: state.customModel,
      detectedInfo: info,
      detecting: false,
    );
  }

  Future<void> setEnabled(bool enabled) async {
    if (state.enabled == enabled) return;
    state = MobilePostSourcePreferences(
      enabled: enabled,
      customModel: state.customModel,
      detectedInfo: state.detectedInfo,
      detecting: state.detecting,
    );
    await _prefs.setBool(MobilePostSourceService.enabledKey, enabled);
  }

  Future<void> setCustomModel(String? value) async {
    final normalized = MobilePostSourceService.normalizeCustomModel(value);
    if (state.customModel == normalized) return;

    state = MobilePostSourcePreferences(
      enabled: state.enabled,
      customModel: normalized,
      detectedInfo: state.detectedInfo,
      detecting: state.detecting,
    );

    if (normalized == null) {
      await _prefs.remove(MobilePostSourceService.customModelKey);
    } else {
      await _prefs.setString(
        MobilePostSourceService.customModelKey,
        normalized,
      );
    }
  }
}

final mobilePostSourcePreferencesProvider =
    StateNotifierProvider<
      MobilePostSourcePreferencesNotifier,
      MobilePostSourcePreferences
    >((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return MobilePostSourcePreferencesNotifier(prefs);
    });
