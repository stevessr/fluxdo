import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android APK extensions communicate through signed Binder services rather
/// than loading code into the Flutter engine. Other platforms see no plugins.
class AndroidOptionalPluginService {
  AndroidOptionalPluginService._();

  static final instance = AndroidOptionalPluginService._();
  static const _channel = MethodChannel(
    'com.github.lingyan000.fluxdo/optional_plugins',
  );

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<List<AndroidOptionalPlugin>> list() async {
    if (!supported) return const [];
    final items = await _channel.invokeMethod<List<dynamic>>('list');
    return (items ?? const [])
        .whereType<Map>()
        .map((item) => AndroidOptionalPlugin.fromMap(item))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> invoke(
    String id,
    String operation, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (!supported) throw UnsupportedError('Android plugins are unavailable');
    final raw = await _channel.invokeMethod<String>('invoke', {
      'id': id,
      'operation': operation,
      'payload': jsonEncode(payload),
    });
    final decoded = jsonDecode(raw ?? '{}');
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid optional plugin response');
    }
    return decoded;
  }
}

class AndroidOptionalPlugin {
  const AndroidOptionalPlugin({
    required this.id,
    required this.name,
    required this.packageName,
    required this.installed,
    required this.compatible,
    required this.reason,
    this.version,
  });

  final String id;
  final String name;
  final String packageName;
  final bool installed;
  final bool compatible;
  final String reason;
  final String? version;

  factory AndroidOptionalPlugin.fromMap(Map<dynamic, dynamic> data) {
    return AndroidOptionalPlugin(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? '',
      packageName: data['package'] as String? ?? '',
      installed: data['installed'] == true,
      compatible: data['compatible'] == true,
      reason: data['reason'] as String? ?? 'unknown',
      version: data['version'] as String?,
    );
  }
}
