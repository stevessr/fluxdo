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
  final String category;

  bool get appearsInEditor => category == 'editor';

  static ExternalPlugin? fromPlatformValue(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final packageName = value['packageName'];
    final label = value['label'];
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
      category: value['category'] == 'editor' ? 'editor' : 'app',
    );
  }
}

/// A companion-generated image to be uploaded by Fluxdo's active composer.
@immutable
class GeneratedPluginImage {
  const GeneratedPluginImage({required this.bytes, required this.fileName});
  final Uint8List bytes;
  final String fileName;

  static GeneratedPluginImage? fromPlatformValue(Object? value) {
    if (value is! Map) return null;
    final bytes = value['bytes'];
    final fileName = value['fileName'];
    if (bytes is! Uint8List ||
        bytes.isEmpty ||
        bytes.length > 12 * 1024 * 1024 ||
        fileName is! String ||
        !RegExp(r'^stevessr_generated\.(png|jpg|webp|avif)$').hasMatch(fileName)) {
      return null;
    }
    return GeneratedPluginImage(bytes: bytes, fileName: fileName);
  }
}

/// 外部插件只在 Android 上安装与发现；站点侧 SitePlugin 为独立机制。
class ExternalPluginService {
  ExternalPluginService({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('com.github.lingyan000.fluxdo/external_plugins') {
    _channel.setMethodCallHandler(_onPlatformMethod);
  }

  static final instance = ExternalPluginService();

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final MethodChannel _channel;

  /// A result belongs only to the editor that initiated this launch.
  ValueChanged<GeneratedPluginImage>? _imageReceiver;

  Future<void> _onPlatformMethod(MethodCall call) async {
    if (call.method != 'generatedImage' && call.method != 'generatedImageCancelled') return;
    final receiver = _imageReceiver;
    _imageReceiver = null;
    if (call.method != 'generatedImage') return;
    final image = GeneratedPluginImage.fromPlatformValue(call.arguments);
    if (image != null) receiver?.call(image);
  }

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

  Future<bool> launchPlugin(ExternalPlugin plugin, {
    ValueChanged<GeneratedPluginImage>? onGeneratedImage,
    String? themeSnapshot,
  }) async {
    if (!isSupported) return false;
    _imageReceiver = onGeneratedImage;
    try {
      final launched = await _channel.invokeMethod<bool>(
            'launchPlugin',
            {'id': plugin.id, if (themeSnapshot != null) 'theme': themeSnapshot},
          ) ??
          false;
      if (!launched) _imageReceiver = null;
      return launched;
    } on MissingPluginException {
      _imageReceiver = null;
      return false;
    } on PlatformException catch (error) {
      _imageReceiver = null;
      debugPrint('插件启动失败: ${error.message}');
      return false;
    }
  }
}
