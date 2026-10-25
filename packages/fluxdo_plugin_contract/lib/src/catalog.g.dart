// Generated from android_modular/plugins.json. Do not edit by hand.
import 'plugin_definition.dart';

const pluginProtocolVersion = 1;
const pluginMaxJsonBytes = 8192;
const pluginMaxConcurrentCalls = 8;
const pluginTransportTimeout = Duration(milliseconds: 20000);

const androidPluginCatalog = <String, PluginDefinition>{
  "deviceinfo": PluginDefinition(
    id: "deviceinfo",
    name: "设备诊断",
    packageName: "com.github.lingyan000.fluxdo.plugin.deviceinfo",
    runtime: PluginRuntime.native,
    operations: {"device.snapshot"},
  ),
  "network": PluginDefinition(
    id: "network",
    name: "网络诊断",
    packageName: "com.github.lingyan000.fluxdo.plugin.network",
    runtime: PluginRuntime.native,
    operations: {"network.state", "network.lookup"},
  ),
  "cdk": PluginDefinition(
    id: "cdk",
    name: "CDK 元宇宙",
    packageName: "com.github.lingyan000.fluxdo.plugin.cdk",
    runtime: PluginRuntime.native,
    operations: {"metaverse.capabilities"},
    activityClass: "com.github.lingyan000.fluxdo.plugin.cdk.CdkActivity",
  ),
  "ldc": PluginDefinition(
    id: "ldc",
    name: "LDC 元宇宙",
    packageName: "com.github.lingyan000.fluxdo.plugin.ldc",
    runtime: PluginRuntime.native,
    operations: {"metaverse.capabilities"},
    activityClass: "com.github.lingyan000.fluxdo.plugin.ldc.LdcActivity",
  ),
  "ldc_reward": PluginDefinition(
    id: "ldc_reward",
    name: "LDC 打赏",
    packageName: "com.github.lingyan000.fluxdo.plugin.ldc_reward",
    runtime: PluginRuntime.native,
    operations: {"reward.capabilities"},
    activityClass: "com.github.lingyan000.fluxdo.plugin.ldc_reward.LdcRewardActivity",
  ),
  "sticker": PluginDefinition(
    id: "sticker",
    name: "表情包生成器",
    packageName: "com.github.lingyan000.fluxdo.plugin.sticker",
    runtime: PluginRuntime.flutter,
    operations: {},
    activityClass: "com.github.lingyan000.fluxdo.plugin.sticker.StickerActivity",
  ),
};
