import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/prompt_preset.dart';

/// PromptPreset 持久化层
///
/// 存储 schema (v1):
/// ```json
/// {
///   "version": 1,
///   "customizations": [PresetCustomization, ...],
///   "userPresets": [PromptPreset, ...]
/// }
/// ```
///
/// - `customizations`: 用户对内置 preset 的覆盖（pin/hide/sortOrder/...）
/// - `userPresets`: 完全自定义的 preset 列表
class PromptPresetStorage {
  PromptPresetStorage(this._prefs);

  static const String _key = 'ai_prompt_presets_v1';

  final SharedPreferences _prefs;

  ({List<PresetCustomization> customizations, List<PromptPreset> userPresets})
  load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return (customizations: const [], userPresets: const []);
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final customizations =
          (json['customizations'] as List<dynamic>?)
              ?.map(
                (e) => PresetCustomization.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const <PresetCustomization>[];
      final userPresets =
          (json['userPresets'] as List<dynamic>?)
              ?.map((e) => PromptPreset.fromJson(e as Map<String, dynamic>))
              // 防御：用户自定义存进去的若被错误标记为 builtIn，强制纠正
              .map((p) => p.copyWith(builtIn: false))
              .toList() ??
          const <PromptPreset>[];
      return (customizations: customizations, userPresets: userPresets);
    } catch (_) {
      // 数据损坏时丢弃，避免阻塞启动
      return (customizations: const [], userPresets: const []);
    }
  }

  Future<void> save({
    required List<PresetCustomization> customizations,
    required List<PromptPreset> userPresets,
  }) async {
    final json = <String, dynamic>{
      'version': 1,
      'customizations': customizations.map((e) => e.toJson()).toList(),
      'userPresets': userPresets.map((e) => e.toJson()).toList(),
    };
    await _prefs.setString(_key, jsonEncode(json));
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
  }
}
