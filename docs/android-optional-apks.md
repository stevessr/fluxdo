# Android 独立插件 APK（实验阶段，协议 v1）

主程序仍是 `com.github.lingyan000.fluxdo`，不更换 applicationId，
保留账户、登录和 OTA 升级数据。插件是**独立安装的软件包**，不是
`--split-per-abi` 生成的多个互斥 CPU 架构 APK，也不是 Play Dynamic
Feature 的同一应用 split。它们可以独立提高 `versionCode` 并更新。

## 第一阶段范围

| Gradle module | applicationId | 功能 | 是否可缺省 |
| --- | --- | --- | --- |
| `:app` | `com.github.lingyan000.fluxdo` | 现有 Flutter 主程序 | 否 |
| `:plugin_api` | Android library（无 APK） | IPC 消息协议 v1 | 由其他模块编译进各 APK |
| `:plugin_deviceinfo` | `com.github.lingyan000.fluxdo.plugin.deviceinfo` | 设备信息和内存诊断 | 是 |
| `:plugin_network` | `com.github.lingyan000.fluxdo.plugin.network` | 网络状态、DNS 解析诊断 | 是 |

第一阶段交付的是可独立部署的插件接口与两个可操作的原生诊断插件。
**媒体转码、WebView、Flutter UI 等现有功能仍打包在主 APK 内**；
因此这一阶段不能承诺主 APK 体积减小或媒体转码模块可热更新。
这比直接迁走 `MediaTranscodeChannel` 更安全：目前它操作宿主应用的
私有文件路径，独立 APK 无法直接读写这些路径，后续需要定义基于
`content://` URI + `FileProvider` 权限授予的零拷贝输入输出协议。

## 安全边界

- 主程序仅允许固定 allowlist 的包名、显式 `ComponentName` 和方法；
  不扫描/执行未知第三方 APK 的 DEX 或 Flutter AOT 代码。
- 插件 Service 必须使用主 APK 定义的 `signature` 保护权限；
  主程序还调用 `PackageManager.checkSignatures` 验证签名一致。
- 插件声明协议版本 meta-data；当前只接受 v1，未来不兼容协议必须
  升级版本号。15 秒 IPC 超时，进程断开/插件安装替换将返回失败，
  不影响主程序基本功能。
- 消息传输仅限短 JSON，不传账户凭据、cookie、token 或明文私有文件路径。
  DNS 查询会向设备系统解析器发送用户输入的域名。
- **只有使用与主 APK 相同的发布密钥签名的插件才会识别为可用。**
  CI 测试构建使用调试签名，不能直接装在正式发行版旁边启用。
- Android 包安装仍由系统 Package Installer 处理；不尝试绕过安装授权。

## 构建与测试

```bash
flutter pub get
cd android
./gradlew :plugin_deviceinfo:assembleDebug :plugin_network:assembleDebug
# APK: ../build/plugin_deviceinfo/outputs/apk/debug/plugin_deviceinfo-debug.apk
# APK: ../build/plugin_network/outputs/apk/debug/plugin_network-debug.apk

# 需要用与主 app 相同的签名构建；key.properties 内容与主 app 共享，
# 配置 keyAlias/keyPassword/storePassword/storeFile，但不要提交真实密钥。
./gradlew :plugin_deviceinfo:assembleRelease -PpluginVersionCode=2 -PpluginVersionName=0.1.1
./gradlew :plugin_network:assembleRelease -PpluginVersionCode=3 -PpluginVersionName=0.1.2
```

验证步骤：

1. 安装相同签名的主 APK，打开「设置 → Android 插件」，看到两个插件
   状态均为 `not_installed`；主程序其他功能应正常。
2. `adb install` 两个插件 APK，返回设置页刷新，状态变成 `ready`。
3. 点击设备诊断和网络诊断，确认可以收到结构化 JSON；DNS 查询用
   `example.com`；禁止把主程序凭据透传给插件。
4. 只升级网络插件为同签名、更高 `versionCode` 的 APK：
   `adb install -r <network-plugin.apk>`。主程序和设备插件版本、账户状态
   不应发生变化。正在进行的 IPC 可能因包替换中断，须允许重试。
5. 用不一致的签名安装插件（需先卸载旧插件），预期状态为
   `signature_mismatch` 且不能执行。把协议 meta-data 改为 2，
   预期 `incompatible_protocol`。
6. 卸载任意插件，主程序应正常启动、功能不受影响。还需检查 Android
   版本 7/10/13/15 的安装、包可见性和进程重建表现。

构建工作流 `android-plugin-apks.yml` 单独上传两个**调试 APK**。
正式 Release 上传需先接入既有安全签名和发布流水线；未通过实体设备
与 CI 验证前不要自动合并，亦不可把 debug APK 当作签名发布件。

## 后续真正减小主 APK 的迁移顺序

先迁移明确跨进程资源边界的纯原生诊断/工具能力，验证包安装生命周期。
随后迁移媒体转码：用 URI 授权 + 独立进程的 Media3，提供探测/压缩/进度/
取消、异常断线与同签名无损升级路径，确认退化行为后才能从 `:app`
移除 Media3 依赖。Flutter 层业务功能仍需主应用升级，不能假装 Dart
代码可以通过独立 APK 热替换。
