# Android 模块清单与独立构建

`android_modular/plugins.json` 是六个独立插件的构建期清单，描述稳定 ID、
包名、IPC 服务、Activity、操作白名单、共享库和各自的版本。
它不是远程插件发现或自动安装接口。

## 模块边界

| 模块 | 构建入口 | 编译依赖 | 资源与账号归属 |
|---|---|---|---|
| Dart 协议 | `packages/fluxdo_plugin_contract` | 仅 Dart SDK | 无平台状态、资源或凭据 |
| Core | `build_android_core_modular.py` | 宿主 Flutter + `plugin_api` | 论坛会话；不携带角色素材 |
| Deviceinfo / Network | `build_native_plugins.py` | `plugin_api` | 独立 Android 进程 |
| CDK / LDC | `build_native_plugins.py` | `plugin_api` + `plugin_web_session` | 各 APK 的 WebView 会话 |
| LDC Reward | `build_native_plugins.py` | `plugin_api` | 公开收款人信息；人工站点交接 |
| Sticker | `build_sticker_companion.py` | 独立 Flutter pubspec + 绘图源码闭包 | 自身 APK 中的字体和角色素材 |

五个原生插件使用 `android/native_plugins/` 作为 Gradle 根工程。
该根工程仅包含清单声明的原生模块及共享库，不加载 Flutter plugin loader，
也不评估宿主 `:app`、Rust、CA 生成或绘图素材预处理。
原生输出先写入 `build/native_plugins/`；检查 APK 不含 Flutter/宿主载荷后，
复制到原有的 `build/plugin_*/outputs/apk/` 交付路径。

## 修改清单

```sh
python3 scripts/ci/generate_android_plugin_catalog.py
python3 scripts/ci/generate_android_plugin_catalog.py --check
python3 scripts/ci/check_android_plugin_contract.py
```

生成物包括宿主 `OptionalPluginCatalog.kt`、独立工程的
`settings.gradle.kts`、`android/plugin-versions.properties`、Dart 的
`catalog.g.dart` 和原生 `PluginProtocol.kt`。
宿主 Messenger 白名单、Sticker Activity 身份、原生构建计划和 APK 身份校验
消费同一清单。Android Manifest 仍在模块内维护；契约检查保证包可见性、
组件名称、签名权限、协议版本及项目依赖与清单一致。

重复 ID/JSON 键、未知字段、越界包名/组件、动态 Gradle 项目依赖、
宿主或其他 APK 依赖、非法版本和过期生成物都会终止检查。
新增功能模块时仍须实现 Kotlin 服务、Manifest 和必要的宿主调用入口。

## 可独立验证的调用协议

`packages/fluxdo_plugin_contract` 不加入根 Pub workspace，宿主以 path 依赖
消费它。该包只依赖 Dart SDK，可以在没有 Flutter、Android SDK、网络依赖或
子模块的环境独立执行。它集中定义模块身份、状态解析、操作参数与响应约束，
Flutter 服务只负责平台传输和账号分区的哈希。

```sh
cd packages/fluxdo_plugin_contract
dart pub get --offline
dart analyze --fatal-infos
dart run test/contract_test.dart
```

未声明操作或字段在调用平台前被拒绝；状态中的包名必须匹配清单，重复模块、
错误类型和矛盾的就绪状态会报协议错误。JSON 以 UTF-8 字节计限，缺失、非对象
或超过 8192 字节的响应不被接受。原生绑定最多同时运行 8 个请求，15 秒超时后
解绑；Dart 另设 20 秒上限，处理平台未完成回调的情况。参数与响应校验不替代
原生签名、权限或 Binder 校验；耗时操作仍在插件进程内执行。

账号 Activity 仅接受 `guest` 或 64 位十六进制分区；Reward 仅接受有界的公开
用户名和正整数用户 ID。原生桥也检查这些启动字段，拒绝传递凭据和任意参数。

## 独立版本与构建

原生构建需要 JDK 17、Gradle 8.14、Android SDK 36，并设置
`ANDROID_HOME` 或 `ANDROID_SDK_ROOT`。无需 Flutter 或 `flutter pub get`。

```sh
# 不执行构建，可在没有 Android SDK 的环境检查依赖和参数。
python3 scripts/ci/build_native_plugins.py --plan --plugin network

# 仅构建 Network；使用清单内该模块的版本。
python3 scripts/ci/build_native_plugins.py --mode debug --plugin network

# 仅发布 Network，显式覆盖其版本；不会构建或改变其他 APK。
python3 scripts/ci/build_native_plugins.py --mode release --plugin network \
  --version-code 2 --version-name 0.2.0

# 不指定 --plugin 时构建五个原生插件。
python3 scripts/ci/build_native_plugins.py --mode debug
```

持久版本修改应更新清单中对应模块的 `versionCode` / `versionName`，
再运行生成器。构建参数覆盖仅影响本次产物。
既有整套 Release 工作流仍显式传入流水号，保持原发布版本约定。
单独更新插件时必须使用大于设备已安装版本的 `versionCode`，不能只依据
清单中的初始版本推断设备状态。

Release 使用宿主 `android/key.properties`。相对 keystore 路径依次基于
`android/app/` 和 `android/` 解析，与宿主一致。没有有效签名配置时，
实际 `preReleaseBuild` 任务拒绝执行，包括直接调用无模块前缀的
`assembleRelease` / `bundleRelease`；不回退到 debug 签名。

## Core、Sticker 与资源包分支

Core 和 Sticker 使用共同的 `dart_source_boundary.py` 检查器。它读取完整
import/export/part 指令，检查每个条件分支、包内路径、百分号编码和
符号链接；源码中的注释、业务字符串和注解不会制造伪依赖。
Core 只允许两个明确的待生成本地化文件暂时缺失；正式编译前仍生成它们。
Sticker 限制外部包集合，并在生成本地化之后检查完整闭包。

Sticker 的 `shims/lib/services/assets/static_asset_packs.dart` 为版本化
角色加载器提供 APK 内置资源适配。它不读取宿主资源安装目录、签名状态或
账号数据；资源变化流为空，素材随 Sticker APK 更新。
这使资源包分支的角色读取代码可以进入独立 Sticker 源码树，而无需带入
Core 的资源安装器。它不代表 Sticker 已支持独立 ZIP 的下载、升级或回滚。

## 验证和产物

```sh
python3 -m unittest discover -s scripts/ci -p 'test_android*.py' -v
python3 -m unittest discover -s scripts/ci -p 'test_sticker*.py' -v
python3 -m unittest discover -s scripts/ci -p 'test_dart_source_boundary.py' -v
python3 scripts/ci/build_android_core_modular.py --prepare-only
```

Android 插件 CI 将 Python 契约、独立 Dart 协议和 Flutter 桥接回归拆成三个门禁。
三者通过后，APK 任务在安装 Flutter 之前先编译原生插件，之后构建 Sticker 与
隔离 Core。Core 构建已经包含宿主 Kotlin 编译，
不得再次用未准备的根工程编译 `:app`，以免缺少 CA 或覆盖隔离产物。
Sticker 的独立 Gradle 工程自行对齐 Android SDK 36 和 JVM 17，满足 AVIF
插件所引用 AndroidX 的编译要求。

`check_android_apk_contract.py --build-mode debug|release` 使用真实
`aapt` / `apksigner` 检查 Core 与六个 APK 的包名、版本、可调试标志和同签名
身份。配合 `--report PATH`，只在全部检查通过后输出每个 APK 的字节数、
文件 SHA-256、签名 SHA-256 和实际 `versionCode`。报告是构建证据，
不是经认证的在线更新目录，不能作为自动安装的信任根。

Python 测试与源码闭包检查不能替代完整 Gradle/Flutter 构建。正式合并前
仍须取得当前提交整套 APK 的成功构建，并验证 Android 安装升级、
同签名 IPC、导出 URI、账号隔离和离线使用。APK 总体积比较应使用相同 ABI、
构建模式和签名条件，不能把 debug 包大小或资源原始字节数当作 release 减重。
