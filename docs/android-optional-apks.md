# Android 独立插件 APK（实验阶段，协议 v1）

模块清单、独立原生构建、版本与验证入口见 [Android 模块构建](android-module-builds.md)。

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
| `:plugin_cdk` | `com.github.lingyan000.fluxdo.plugin.cdk` | CDK 独立站点 UI（独立登录）与能力协议 | 是 |
| `:plugin_ldc` | `com.github.lingyan000.fluxdo.plugin.ldc` | LDC 独立站点 UI（独立登录）与能力协议 | 是 |
| `android_companions/sticker` | `com.github.lingyan000.fluxdo.plugin.sticker` | **独立 Flutter 引擎**的 StevesSR 生成器；图片经限权 URI 返回主 App | 是 |

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
  CI 测试构建使用调试签名，不能直接装在正式发行版旁边启用；\n  CI 的调试密钥与本机 Android debug keystore 也可能不同，不能混装测试。
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

## 第二阶段：表情包生成器与元宇宙

### 表情包生成器 (StevesSR)

- 与 JNI/Binder 原生诊断插件不同，生成器使用自己的 Flutter Android **应用工程**
  （构建时由 Flutter SDK 生成），具有独立的 `applicationId`、`versionCode`
  和 Flutter Engine。UI 直接复用原来的 `StevessrGeneratorPage`、图片生成和导出逻辑。
- 构建器先运行 `dart tool/project_prep.dart test` 生成 Slang 翻译与角色表情差分，
  然后把角色素材、字体打入独立插件。否则从新检出的源码只看到 `.gitkeep`，
  默认 StevesSR 表情不可用。
- Android 主 App 的编辑器调用 `AndroidStickerCompanionService.generate()`，
  插件生成图后写到它的私有 cache，原生 Activity 使用 FileProvider 生成受限制的
  `content://` URI，通过 Activity Result + 临时读权限交还。主 App 严格校验
  签名、固定包名、URI authority、MIME、非空和 16MiB 上限，之后继续沿用原有
  Discourse 图片上传、保留 alpha 通道和插入 Markdown 逻辑。
- 设置页生成器在检测到同签名 APK 已安装时也调用独立生成器；图片确认后落地
  保存。未安装插件时沿用原生内嵌 Flutter 页面，**不破坏旧安装**。
- 插件升级不需要更新主 APK，但打包构建仍依赖相同源代码版本的 Flutter
  组件。Flutter AOT / Native ABI 不能直接跨 APK 装载成原进程里的 Dart 代码。
- **当前尚未完成减重**：为保护 iOS/Linux/Windows、老 Android 安装和全部
  编辑器入口，原生成器 Dart 代码及角色素材仍被主 App 引用；后续先增加
  Android 专属裁剪/资源 flavor，测量安装总量与更新下载大小，再考虑删除
  主包内对应功能。不要误称本轮已经大幅减小 core.apk。

构建独立 Flutter APK：

```bash
flutter pub get
dart tool/project_prep.dart test
python3 scripts/ci/build_sticker_companion.py --mode debug --abi android-arm64
# build/plugin_sticker/fluxdo-sticker-android-arm64-debug.apk
# Release 必须有 android/key.properties，引用主 App 同一套 release 密钥
python3 scripts/ci/build_sticker_companion.py --mode release --abi android-arm64
```

### CDK / LDC

- 分别新建 `:plugin_cdk` 和 `:plugin_ldc`，各自是独立原生 APK，
  提供签名保护的 `metaverse.capabilities` IPC 与 WebView 站点入口；
  只允许打开对应的官方 HTTPS 服务、linux.do、connect.linux.do；
  其它 URL 转外部浏览器。
- 主应用「元宇宙」与「Android 插件」可打开这些入口。插件独立存放 WebView
  Cookie，**不会读取、复制或自动同步 FluxDO 原登录凭据**；
  用户可能需要在插件单独授权。
- **功能迁移状态必须准确描述**：目前 CDK/LDC 的既有余额卡片、站内授权、
  账号分区缓存仍在主 App，新增 APK 仅实现独立服务 UI 容器，不具备自动继承
  宿主余额态的能力。
- `lib/modules/ldc_reward` 打赏服务含 Basic Auth 的 Client ID/Secret，
  交易接口 `/epay/pay/distribute` 属资金操作。它**还没有拆成可执行交易的
  独立插件**。后续要实现仅一次有效的授权/交易许可、账户代际校验、幂等号、
  超时后订单状态查询、撤销凭据和签名隔离后再迁移。不允许把密钥通过 JSON
  接口随意发给新插件，也不能用页面壳冒充交易逻辑已完成。

下一阶段正确目标是独立可升级的 **业务逻辑**（而非仅页面）：将宿主授权状态
以最小权限能力委托给 CDK、LDC 插件，由插件执行其业务 API，返回无凭据的结果，
原 App 只负责 UI 组合与会话撤销。必须有黑盒测试证明多账户切换无泄漏。

### 回归重点

1. 构建 debug 主 App + sticker + CDK + LDC，确认签名与安装包名一致；
   `adb install -r` 独立升级任一包不卸载主应用。
2. 插件未安装、签名错误、协议错误、升级中进程死亡、外部回调被取消均能
   安全失败；未安装时原生成器仍可绘制与上传。
3. 生成器逐一验证 PNG/WebP/AVIF/JPEG/SVG，透明 WebP/AVIF、气泡图片、
   不同角色的差分素材及 16MiB 拒绝策略；禁止任意文件 URI、任意 authority。
4. 切换 Discourse 账户后 CDK/LDC 不显示旧账号数据；测试插件独立浏览会话
   与主 App 授权互不污染。
5. 审查独立 Flutter APK 是否无意引入多余插件/系统权限，对比拆分前后的
   **core APK bytes / 总安装 bytes / 单次增量更新 bytes / 冷启动 P95**。

## 第三阶段：Android 实际主包剔除（本 PR 新增）

这不是在 Dart 运行时用 `Platform.isAndroid` 隐藏页面，那样仍可能将图片
和业务逻辑链接到 APK。项目现在维护以下**两套编译入口**：

- **Android 正式 CI**：`python3 scripts/ci/build_android_core_modular.py --mode
  release --abi android-arm64`。脚本复制一份隔离工程，将 `lib/pages/metaverse_page.dart`
  替换成 LDC/CDK 插件启动页；将 `lib/pages/stevessr_generator_page.dart`、
  `lib/services/stevessr_export_service.dart` 换成独立 APK 的薄桥接层；帖子
  打赏菜单不再查询主包凭据；移除相关 OAuth、余额 Provider、打赏交易模型/
  服务和生成器画布实现源码，然后从独立工程的 `pubspec.yaml` 删除五组
  角色素材。**根目录原代码和 pubspec 不被修改**。
- **其他平台**：原来的 `dart tool/flutterw.dart build linux/windows/macos/ios/web`
  等入口完全不变。正常保留内嵌 StevesSR 生成器、全部角色图像、元宇宙
  LDC/CDK 账户功能和原打赏 UI。
- **Android 插件**：`:plugin_deviceinfo`、`:plugin_network`、
  `:plugin_cdk`、`:plugin_ldc` 是单独签名的 Native APK。
  `android_companions/sticker` 独立建 Flutter Application，分别构建
  `android-arm`、`android-arm64`、`android-x64` 与 `universal`
  APK，拥有自己的 Flutter AOT、角色素材和更新 `versionCode`。
  同一次构建生成 Core 和所有插件 APK，用户只安装所需插件即可。

### 构建示例

```bash
# Android: Core APK 不含角色素材及生成器/元宇宙业务实现
python3 scripts/ci/build_android_core_modular.py --mode release --abi android-arm64

# 单独构建并更新 Sticker APK（必须与 Core 同签名）
dart tool/project_prep.dart test
python3 scripts/ci/build_sticker_companion.py --mode release --abi android-arm64 \
  --version-code 200 --version-name 0.2.0

# 可选 Native APK (各自拥有独立包名及 versionCode)
(cd android && ./gradlew -PpluginVersionCode=200 \
  :plugin_ldc:assembleRelease :plugin_cdk:assembleRelease \
  :plugin_network:assembleRelease :plugin_deviceinfo:assembleRelease)
```

Android CI 使用上述独立构建器，严格检查编译出的 Core APK 不再包含
`flutter_assets/assets/images/avater/` 的角色素材。打包器绝不静默回退
到旧版 monolith；若仍有对已迁走 Dart 实现的 import，Flutter 编译会失败。
CI 另外产生 `build/android_modular_sizes.md`，列出 **Core 独立安装体积、
每个可选插件安装体积、全部安装总量**；有旧版 APK 时可运行
`scripts/ci/report_android_modular_size.py --baseline old.apk` 做准确对比。

### 兼容性与未完成部分

- **只有使用独立构建脚本/更新后的官方 Android CI 才能得到瘦身主包。**
  开发时直接执行普通 `flutter build apk` 仍是全功能单 APK，以保留现有
  开发调试流；正式 Android 发布必须使用独立入口。
- Android Core 仍保留 `StevessrExportedImage` 简单传输类型、
  图片上传/透明度检查、插件发现/进程安全桥接和必要的菜单入口。独立
  图片的编辑与编码、角色素材及 LDC/CDK 原登录实现不再包含于该构建入口。
- **LDC/CDK 独立插件尚未实现和旧版等价的余额/授权 UI。** 目前以隔离
  WebView 访问相应服务页面，用户在插件里单独登录。旧账户 Cookie 不会跨 APK
  复制。独立插件不能冒充原有 Flutter 页面已经迁移完毕。
- **打赏暂不具备旧版一键操作的功能等价性**：独立 LDC 插件承载站点
  交易页面，但自动预填用户/额度、客户端 ID/Secret 管理、确认、
  幂等对账和失败恢复还未实现。Android Core 的打赏入口只提示使用独立
  LDC 插件，不再从主包取 Basic Auth 凭据。旧凭据不会被自动迁移、
  复制或删除；待安全迁移方案验证后才可正式替换。
- 当前没有已完成的设备实测或 CI 成功证据。本 PR 在签名、资源、
  Flutter 构建、插件安装/更新和业务流程均验证前必须保持 Draft，
  不能宣称已生产可用。

本次采用隔离构建副本而非删除多平台共用源码，主要是保证非 Android 平台
完整保留原功能且不会产生源代码和 `pubspec.yaml` 临时覆盖/恢复的竞态。

## 第四阶段：独立打赏模块、源码依赖及 APK 签名校验

- 增加第五个原生插件 `:plugin_ldc_reward`（包名
  `com.github.lingyan000.fluxdo.plugin.ldc_reward`）。与 `plugin_ldc`
  完全不同的安装和版本生命周期。主应用帖子菜单只经
  `AndroidOptionalPluginService.launch('ldc_reward', payload: ...)`
  传递收款人公开 ID/用户名；原有 Basic Auth 凭据、Cookie、支付金额
  和支付指令都**不会**送到这个独立 APK。
- 打赏插件当前是**显式的人工交易交接**：显示目标用户和风险说明，
  由用户手动打开 LDC 官方站点，自己确认收款人、金额和交易结果。
  **没有**假定已完成原一键打赏功能，也不会自动请求
  `/epay/pay/distribute`。补齐账户隔离、Keystore 存储、不可重复
  提交和服务器侧交易对账前，仍不可标为功能等价。
- CDK、LDC 独立 APK 新增站点主页、我的信息 API 页面、刷新入口；
  顶层导航保持 HTTPS 官方域名白名单，iframe/子资源不误开外部浏览器。
  不复用 Core 的 Session，独立站点登录仍需测试。
- `scripts/ci/build_android_core_modular.py` 的预构建检查现在会扫描
  Dart 直接 import/export/part，发现引用已剔除的文件就终止构建；
  对预生成的 Slang 翻译文件只豁免两个明确路径。
  `scripts/ci/test_android_modular_contract.py` 对旧模型导入、
  多平台 API 兼容层、角色目录、打赏服务残留及翻译生成时序添加了回归用例。
- `scripts/ci/check_android_apk_contract.py` 在真正生成 APK 后使用 Android
  SDK 的 `aapt` / `apksigner` 检查 **Core + 六个独立 APK**
  的 packageName、versionCode 和签名 SHA-256 摘要。
  如果签名不同或错误地使用了 debug 签名，CI 不再上传标记为有效的产物。
  表情包 APK 的签名解析顺序已与 Android 主项目一致，调试版
  在有主发布密钥时也使用同一身份。
- 原来的 `.github/workflows/build-apk.yaml` 现在可以作为 PR 检查入口；
  `.github/workflows/android-plugin-apks.yml` 明确安装 Rust target、
  cargo-ndk、Android NDK，检出 Git 子模块后再执行完整 Flutter / Kotlin 编译。

### 仍需通过的真实性门禁

1. 一次真实、成功的 CI 构建与 Android 模拟器/真机安装验证；
   每次更新只替换选中的 `applicationId` 且不破坏宿主会话。
2. 将原 `StevessrGeneratorPage` 的跨平台依赖从根 `fluxdo`
   进一步提取为**小型纯生成器 Package**。当前独立 Flutter APK 仍依赖
   根包的代码和依赖解析，虽然 Core 的渲染实现已从独立编译副本剔除，
   但 Sticker APK 的传递依赖与 Flutter 插件注册仍偏重，不能宣称整体安装
   或更新流量最优。
3. CDK/LDC 旧余额卡片的功能等价迁移以及 LDC Reward 的支付功能迁移。
4. 以上任一门禁未完成：PR 必须维持 Draft，不进入正式发布。

## 第五阶段：Sticker 移除根包依赖（本轮）

**已经不再使用** `flutter: fluxdo: path: ../..` 这种整个应用的
path dependency。Sticker 现在有 Android-only 的极简 Flutter pubspec，
见 `android_companions/sticker/pubspec.yaml`。

- 根项目的生成器代码**仍是跨平台唯一的源文件**；编译独立 Sticker 时，
  `scripts/ci/build_sticker_companion.py` 根据固定的
  `DRAWING_SOURCES` / `DRAWING_TREES` 清单，只复制
  StevessrGeneratorPage、RenderParams、画布、绘制/导出引擎、角色 delta
  还原、分块截图、生成的 Slang 翻译文件等必要源码。
  这样不必维护两份绘图算法，也不会通过 Dart package 导入主程序的
  Discourse / Dio / Riverpod / 聊天 / 系统通知模块。
- 生成器原有 `ShareUtils`、`ImageSaveUtils`、
  `ToastService`、`navigatorKey` 使用
  `android_companions/sticker/shims/lib` 的独立小型 Android 适配器。
  文件保存走系统 SAF 或相册插件；分享走 share_plus。
  导出质量和格式仍由原绘制引擎决定。
- Android/Flutter 插件依赖严格限制在
  Flutter、flutter_localizations、slang、intl、file_picker、
  flutter_avif、image、cross_file、path_provider、share_plus、gal。
  与主项目不同的是：构建脚本不再从应用依赖解析大批 Android 插件。
- `python3 scripts/ci/check_sticker_isolation.py` 会在 Flutter
  编译前检查源码完整性、所有相对 import/export/part、第三方依赖白名单
  和无 `fluxdo` package import。
  构建后还检查 `pubspec.lock` 没有 `fluxdo`，Flutter 自动生成的
  Android plugin registry 只包含绘图所需原生插件，且 APK 未混入主站证书、
  cook、polyfill、AI 资源。
- 生成与主 App 完全相同的签名；FlutterAVIF 重复 Java/Kotlin 类、
  JDK17 编译目标这两项 Android 原生插件兼容补丁在独立工程中独立处理。
  移除插件专有 Activity 的系统 LAUNCHER 图标，仅接受同签名宿主启动。
- `build/plugin_sticker/sticker-dependencies-<ABI>-<mode>.md` 自动记录
  **实际解析的 Dart package 数、注册的 Android native plugin 数和
  Sticker APK 体积**，并追加到 Android release CI 的运行摘要。
  不能在 CI 未运行的情况下伪称节省了具体多少 MB。
- `android/build.gradle.kts` 允许原生 `:plugin_*`
  Gradle 工程不再强制 `evaluationDependsOn(":app")`，单独构建 APK
  时不必等待完整 Flutter Core 项目评估。

详见 `android_companions/sticker/README.md`。

### 待确认

Android 调试/发布 APK 仍需运行 Flutter/Gradle 构建与真机验证。
新的 Android-only 的保存/分享适配器需要重点检查 WebP/AVIF/SVG 保存、
透明 PNG、文件类型、权限及 SAF 返回状态是否与旧内嵌版一致。

此阶段只精简**独立 Sticker**的依赖树。Core 使用的 AVIF、图片解码和
文件处理依赖在其他功能仍可能需要，不能为了减少声明行数随意删除。

## 第六阶段：构建闭包修复、账户隔离与 Core 依赖边界

### 核心构建前处理顺序修复

精简 Core **不能**在最后再次调用 `dart tool/flutterw.dart build apk`：
该 wrapper 固定执行 `project_prep.dart app`，会重建应当只存在于
Sticker APK 中的整组头像差分素材。现在 CI 的 Core 构建器改为：

```text
复制隔离工程（跳过 avatar）
  → flutter pub get
  → dart tool/gen_l10n.dart
  → dart tool/project_tasks.dart native:prepare android <mode> --target-platform=<ABIs>
  → verify_sources（禁止 avatar 与旧插件 Dart 重新出现）
  → flutter build apk <mode> --target-platform=<ABIs>
  → verify_sources + APK Zip 检查
```

这种做法仍使用原项目的证书准备及 DOH Rust 本机编译流程，
但**不触发多余的表情包图像生成**，也不会修改 Linux/Windows/macOS/iOS
原构建入口。

### LDC/CDK 独立 WebView 的账户状态边界

- Core 将当前用户的规范化用户名哈希为本机账号分区标识（SHA-256）；
  发给 LDC/CDK 的仅是 `accountSlot`，不携带凭据、邮箱、
  密码、Cookie 或登录 Token。
- 宿主在 Kotlin 端只接受 `guest` 或 64 位小写十六进制标识；
  重新打开插件时执行 `FLAG_ACTIVITY_CLEAR_TASK`，避免旧会话
  WebView 停留在 Android 返回栈。
- 独立 Native 模块 `:plugin_web_session` **仅编入**
  `:plugin_ldc` 与 `:plugin_cdk`。通用 `:plugin_api` 仍保持
  轻量协议定义；宿主 Core 不依赖这个 WebView 实现。
- 每个 APK 独立保存自己的上次账号分区标识。检测到变化，或访客
  `guest` 模式时，先隐藏 WebView，异步清空当前插件私有
  `CookieManager`、`WebStorage`、WebView 缓存和历史，
  再重新访问该插件官方 HTTPS 页面。
- 两个插件均增加“清除插件登录状态”菜单项，它只清理该插件的
  会话，不修改主程序账号或另一插件的 Cookie。
- Android Core 的元宇宙页面和插件管理页同时传递账号分区标识；
  Kotlin 和 Dart 均增加防回归检查。

**安全边界**：账号分区哈希是区分本机登录身份的普通索引，并非密码、
加密密钥或用户身份凭据。若网站自身的 OAuth 流程使用系统外部浏览器，
仍需实机检查返回登录、切换账号及会话恢复行为。本模块不能替代服务器
端会话撤销，也不能保证用户在独立 WebView 中手动登录的账号一定与
FluxDO 主应用账号相同。
