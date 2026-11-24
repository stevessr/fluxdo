import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/external_plugin_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.github.lingyan000.fluxdo/external_plugins');
  final messenger = TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('已安装插件按原生发现结果显示，重复和不完整数据被忽略', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'listPlugins');
      return [
        {
          'id': 'example.plugin/example.plugin.MainActivity',
          'packageName': 'example.plugin',
          'label': 'StevesSR 表情生成器',
        },
        {
          'id': 'example.plugin/example.plugin.MainActivity',
          'packageName': 'example.plugin',
          'label': '重复项',
        },
        {'id': 'invalid', 'packageName': 'other', 'label': '错误'},
        {'id': '', 'packageName': '', 'label': ''},
      ];
    });

    final plugins = await ExternalPluginService(channel: channel).installedPlugins();
    expect(plugins, hasLength(1));
    expect(plugins.single.label, 'StevesSR 表情生成器');
    expect(plugins.single.packageName, 'example.plugin');
  });

  test('启动只向原生层提交已发现的组件标识', () async {
    const plugin = ExternalPlugin(
      id: 'example.plugin/example.plugin.MainActivity',
      packageName: 'example.plugin',
      label: '表情生成器',
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'launchPlugin');
      expect(call.arguments, {'id': plugin.id});
      return true;
    });

    expect(await ExternalPluginService(channel: channel).launchPlugin(plugin), isTrue);
  });

  test('未安装或原生通道不可用时显示空列表并安全回退', () async {
    final service = ExternalPluginService(channel: channel);
    expect(await service.installedPlugins(), isEmpty);
    const plugin = ExternalPlugin(
      id: 'example.plugin/example.plugin.MainActivity',
      packageName: 'example.plugin',
      label: '表情生成器',
    );
    expect(await service.launchPlugin(plugin), isFalse);
  });

  test('generated image is delivered once to the initiating composer', () async {
    final service = ExternalPluginService(channel: channel);
    const plugin = ExternalPlugin(id: 'example.plugin/Main', packageName: 'example.plugin', label: 'Generator');
    messenger.setMockMethodCallHandler(channel, (_) async => true);
    final received = <GeneratedPluginImage>[];
    expect(await service.launchPlugin(plugin, onGeneratedImage: received.add), isTrue);
    final payload = const StandardMethodCodec().encodeMethodCall(MethodCall('generatedImage', {
      'bytes': Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
      'fileName': 'stevessr_generated.png',
    }));
    await messenger.handlePlatformMessage(channel.name, payload, (_) {});
    await messenger.handlePlatformMessage(channel.name, payload, (_) {});
    expect(received, hasLength(1));
  });

  test('generated image handoff validates name, type and size', () {
    final bytes = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);
    final image = GeneratedPluginImage.fromPlatformValue({
      'bytes': bytes,
      'fileName': 'stevessr_generated.png',
    });
    expect(image, isNotNull);
    expect(image!.bytes, same(bytes));
    expect(image.fileName, 'stevessr_generated.png');

    expect(GeneratedPluginImage.fromPlatformValue({
      'bytes': bytes,
      'fileName': '../unsafe.png',
    }), isNull);
    expect(GeneratedPluginImage.fromPlatformValue({
      'bytes': bytes,
      'fileName': 'stevessr_generated.svg',
    }), isNull);
    expect(GeneratedPluginImage.fromPlatformValue({
      'bytes': Uint8List(12 * 1024 * 1024 + 1),
      'fileName': 'stevessr_generated.png',
    }), isNull);
  });

  test('非 Android 平台不会尝试调用原生插件通道', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    messenger.setMockMethodCallHandler(channel, (call) async {
      fail('Non-Android should not call ${call.method}');
    });
    final service = ExternalPluginService(channel: channel);
    expect(await service.installedPlugins(), isEmpty);
    expect(await service.launchPlugin(const ExternalPlugin(
      id: 'x/y', packageName: 'x', label: 'x',
    )), isFalse);
  });
}
