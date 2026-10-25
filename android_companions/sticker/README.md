# StevesSR 独立 Android APK

本目录专门用于编译独立的 `com.github.lingyan000.fluxdo.plugin.sticker` APK。
**不能把完整 `fluxdo` Flutter Application 作为 path dependency。**

## 依赖边界

- `pubspec.yaml` 只声明绘图真正需要的 Flutter、Slang、image、
  flutter_avif、file_picker、Gal、share_plus、cross_file 和 path_provider。
- `scripts/ci/build_sticker_companion.py` 在系统临时目录 `flutter create`
  生成独立的 Flutter App，复制根项目原始 `StevessrGeneratorPage`、
  `StevessrRenderParams`、渲染/导出服务、画布小组件、delta 解码器、
  滚动/分块截图库以及自动生成的本地化代码。**复制仅限明示的文件清单。**
- `shims/lib/` 是这些代码在独立 APK 中的轻量平台适配层：
  `ShareUtils`、`ImageSaveUtils`、`ToastService`、`navigatorKey`。
  适配层独立于主程序用户认证、Dio、Discourse、账户管理和通知服务。
- 角色图像/差分素材、MiSans 字体只打入 Sticker APK，
  正式 Android Core APK 不包含这些资源。
- Source import 闭包检查、pubspec.lock 检查、Flutter Android 原生插件
  注册表精确白名单、APK 素材污染检查和同签名检查均为 CI 门禁。
  白名单包括 Flutter 依赖间接引入的 `flutter_plugin_android_lifecycle`、
  `jni`、`jni_flutter`、`sqflite_android`；全部注册项必须存在于独立
  Sticker 的 pubspec.lock 中。不会因主 APK 已安装某插件而自动放行。

### 执行命令

```sh
dart tool/project_prep.dart test
python3 scripts/ci/check_sticker_isolation.py
python3 scripts/ci/build_sticker_companion.py --mode debug --abi android-arm64
```

发布 Release 需要宿主 `android/key.properties` 和它引用的 keystore：

```sh
python3 scripts/ci/build_sticker_companion.py --mode release \
  --abi android-arm64 --version-code 200 --version-name 0.2.0
```

生成产物保存至 `build/plugin_sticker/`，签名必须与宿主 Core 保持一致。
其他平台**不使用这个独立 APK，也不使用此复制过程**，继续使用原代码内置
StevesSR。

### 当前限制

这解决的是“Sticker 依赖完整 Flutter 主程序”的问题，不是把 Flutter 引擎
替换成动态共享库。两个 APK 仍各自打包 Flutter 引擎与所需本机插件。

此外保存/分享改用独立 App 内的原生插件（Android 图库与 SAF），
需要实机回归 PNG、WebP、AVIF、SVG 导出及透明像素、FileProvider URI 回传、
前后台切换和 Android 版本兼容性。未跑过 CI/设备前不能称为生产可用。
