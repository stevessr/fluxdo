import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 插件通过 Activity 的公开动作注册，不依赖固定包名。
@immutable
class ExternalPlugin {
  const ExternalPlugin({
    required this.id,
    required this.packageName,
    required this.label,
    this.category = 'app',
  });

  /// Android ComponentName.flattenToString，作为本次发现结果的启动标识。
  final String id;
  final String packageName;
  final String label;
  /// 只有编辑器型插件显示在表情/贴纸面板。
  final String category;

  bool get appearsInEditor => category == 'editor';

  static ExternalPlugin? fromPlatformValue(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final packageName = value['packageName'];
    final label = value['label'];
    final category = value['category'];
    if (id is! String || id.isEmpty ||
        packageName is! String || packageName.isEmpty ||
        label is! String || label.trim().isEmpty ||
        !id.startsWith('$packageName/')) {
      return null;
    }
    return ExternalPlugin(
      id: id,
      packageName: packageName,
      label: label,
      category: category == 'editor' ? 'editor' : 'app',
    );
  }
}

/// 外部插件只在 Android 上安装与发现；站点侧 SitePlugin 为独立机制。
class ExternalPluginService {
  ExternalPluginService({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('com.github.lingyan000.fluxdo/external_plugins');

  static final instance = ExternalPluginService();

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final MethodChannel _channel;

  Future<List<ExternalPlugin>> installedPlugins() async {
    if (!isSupported) return const [];
    try {
      final values = await _channel.invokeListMethod<dynamic>('listPlugins');
      final found = <ExternalPlugin>[];
      final ids = <String>{};
      for (final value in values ?? const <dynamic>[]) {
        final plugin = ExternalPlugin.fromPlatformValue(value);
        if (plugin != null && ids.add(plugin.id)) found.add(plugin);
      }
      return List.unmodifiable(found);
    } on MissingPluginException {
      return const [];
    } on PlatformException catch (error) {
      debugPrint('插件发现失败: ${error.message}');
      return const [];
    }
  }

  Future<bool> launchPlugin(ExternalPlugin plugin) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'launchPlugin',
            {'id': plugin.id},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      debugPrint('插件启动失败: ${error.message}');
      return false;
    }
  }
}
