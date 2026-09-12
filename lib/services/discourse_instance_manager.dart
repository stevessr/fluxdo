import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/discourse_instance_runtime.dart';

@immutable
class DiscourseInstanceProfile {
  const DiscourseInstanceProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final String baseUrl;
  final bool builtIn;

  static const linuxDo = DiscourseInstanceProfile(
    id: DiscourseInstanceRuntime.defaultInstanceId,
    name: 'LINUX DO',
    baseUrl: DiscourseInstanceRuntime.defaultBaseUrl,
    builtIn: true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'base_url': baseUrl,
  };

  factory DiscourseInstanceProfile.fromJson(Map<String, dynamic> json) {
    final baseUrl = DiscourseInstanceRuntime.normalizeBaseUrl(
      json['base_url']?.toString() ?? '',
    );
    return DiscourseInstanceProfile(
      // 不信任持久化的 id。实例 namespace 必须由 URL 唯一派生，避免损坏的
      // 注册表让两个不同站点共享账号/Secure Storage 边界。
      id: idForBaseUrl(baseUrl),
      name: _normalizeName(json['name']?.toString(), baseUrl),
      baseUrl: baseUrl,
    );
  }

  static String idForBaseUrl(String baseUrl) =>
      DiscourseInstanceRuntime.instanceIdForBaseUrl(baseUrl);

  static String _normalizeName(String? input, String baseUrl) {
    final name = input?.trim();
    if (name != null && name.isNotEmpty) return name;
    return Uri.parse(baseUrl).host;
  }
}

/// 试验性多 Discourse 实例注册表。
///
/// 当前阶段故意保持“一次仅激活一个实例”。选择新实例只修改下次启动使用的
/// 站点，避免运行中只有部分 Dio/WebView/MessageBus 已切换造成跨站请求。
class DiscourseInstanceManager {
  DiscourseInstanceManager._();

  static final DiscourseInstanceManager instance = DiscourseInstanceManager._();

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<bool> isEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(DiscourseInstanceRuntime.enabledPrefKey) ?? false;
  }

  Future<List<DiscourseInstanceProfile>> listInstances() async {
    final prefs = await _prefs;
    final result = <DiscourseInstanceProfile>[
      DiscourseInstanceProfile.linuxDo,
    ];
    final seenUrls = <String>{DiscourseInstanceRuntime.defaultBaseUrl};
    final seenIds = <String>{DiscourseInstanceRuntime.defaultInstanceId};

    final raw = prefs.getString(DiscourseInstanceRuntime.instancesPrefKey);
    if (raw == null || raw.isEmpty) return result;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return result;
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          final profile = DiscourseInstanceProfile.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (!seenUrls.add(profile.baseUrl) || !seenIds.add(profile.id)) {
            continue;
          }
          result.add(profile);
        } catch (e) {
          debugPrint('[MultiDiscourse] 忽略无效实例: $e');
        }
      }
    } catch (e) {
      debugPrint('[MultiDiscourse] 实例注册表解析失败: $e');
    }
    return result;
  }

  Future<DiscourseInstanceProfile> selectedInstance() async {
    final prefs = await _prefs;
    final enabled =
        prefs.getBool(DiscourseInstanceRuntime.enabledPrefKey) ?? false;
    if (!enabled) return DiscourseInstanceProfile.linuxDo;

    final selectedId = prefs.getString(
      DiscourseInstanceRuntime.activeInstanceIdPrefKey,
    );
    final selectedBaseUrl = prefs.getString(
      DiscourseInstanceRuntime.activeBaseUrlPrefKey,
    );
    if (selectedId == null || selectedBaseUrl == null) {
      return DiscourseInstanceProfile.linuxDo;
    }

    late final String normalizedSelectedBaseUrl;
    try {
      normalizedSelectedBaseUrl = DiscourseInstanceRuntime.normalizeBaseUrl(
        selectedBaseUrl,
      );
    } catch (e) {
      debugPrint('[MultiDiscourse] 活动实例地址损坏，回退 linux.do: $e');
      return DiscourseInstanceProfile.linuxDo;
    }

    final instances = await listInstances();
    // 同时校验 id 与 baseUrl。active_* 任一缺失、损坏或陈旧时回退默认站，
    // 不允许凭单个持久化字段恢复到一个未注册/错误的账号 namespace。
    return instances.firstWhere(
      (instance) =>
          instance.id == selectedId &&
          instance.baseUrl == normalizedSelectedBaseUrl,
      orElse: () => DiscourseInstanceProfile.linuxDo,
    );
  }

  Future<DiscourseInstanceProfile> addInstance({
    required String name,
    required String baseUrl,
  }) async {
    final normalized = DiscourseInstanceRuntime.normalizeBaseUrl(baseUrl);
    if (normalized == DiscourseInstanceRuntime.defaultBaseUrl) {
      return DiscourseInstanceProfile.linuxDo;
    }

    final instances = await listInstances();
    final existing = instances.where((item) => item.baseUrl == normalized);
    if (existing.isNotEmpty) return existing.first;

    final profile = DiscourseInstanceProfile(
      id: DiscourseInstanceProfile.idForBaseUrl(normalized),
      name: name.trim().isEmpty ? Uri.parse(normalized).host : name.trim(),
      baseUrl: normalized,
    );
    await _saveCustomInstances([...instances.skip(1), profile]);
    return profile;
  }

  Future<void> removeInstance(String id) async {
    if (id == DiscourseInstanceRuntime.defaultInstanceId) return;
    final prefs = await _prefs;
    final instances = await listInstances();
    await _saveCustomInstances(
      instances.skip(1).where((item) => item.id != id).toList(),
    );

    final selectedId = prefs.getString(
      DiscourseInstanceRuntime.activeInstanceIdPrefKey,
    );
    if (selectedId == id) {
      await selectInstance(DiscourseInstanceRuntime.defaultInstanceId);
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(DiscourseInstanceRuntime.enabledPrefKey, enabled);
    if (!enabled) {
      await prefs.setString(
        DiscourseInstanceRuntime.activeInstanceIdPrefKey,
        DiscourseInstanceRuntime.defaultInstanceId,
      );
      await prefs.setString(
        DiscourseInstanceRuntime.activeBaseUrlPrefKey,
        DiscourseInstanceRuntime.defaultBaseUrl,
      );
    }
  }

  /// 选择下次启动的实例。运行中的 baseUrl 不在这里热切换。
  Future<void> selectInstance(String id) async {
    final prefs = await _prefs;
    final instances = await listInstances();
    final profile = instances.firstWhere(
      (item) => item.id == id,
      orElse: () => DiscourseInstanceProfile.linuxDo,
    );
    await prefs.setString(
      DiscourseInstanceRuntime.activeInstanceIdPrefKey,
      profile.id,
    );
    await prefs.setString(
      DiscourseInstanceRuntime.activeBaseUrlPrefKey,
      profile.baseUrl,
    );
  }

  Future<void> _saveCustomInstances(
    List<DiscourseInstanceProfile> instances,
  ) async {
    final prefs = await _prefs;
    final custom = instances
        .where((item) => !item.builtIn)
        .map((item) => item.toJson())
        .toList(growable: false);
    await prefs.setString(
      DiscourseInstanceRuntime.instancesPrefKey,
      jsonEncode(custom),
    );
  }
}
