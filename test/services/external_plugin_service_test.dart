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
          'category': 'editor',
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
    expect(plugins.single.appearsInEditor, isTrue);
  });

  test('工具型插件不占用编辑器入口，旧 APK 缺少类型时按工具处理', () {
    final app = ExternalPlugin.fromPlatformValue({
      'id': 'store.plugin/store.plugin.MainActivity',
      'packageName': 'store.plugin',
      'label': 'LD 士多',
      'category': 'app',
    });
    expect(app, isNotNull);
    expect(app!.appearsInEditor, isFalse);
    final legacy = ExternalPlugin.fromPlatformValue({
      'id': 'legacy.plugin/legacy.plugin.MainActivity',
      'packageName': 'legacy.plugin',
      'label': '旧插件',
    });
    expect(legacy!.appearsInEditor, isFalse);
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
