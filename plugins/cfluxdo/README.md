# CDK / LD 士多原生 APK 插件

本目录为 [Fluxdo](https://github.com/stevessr/fluxdo) 的两个 **Android 外部插件**提供可重复的打包覆盖层，不把购物或 CDK 业务代码塞进主 APK。

## 来源与构建形式

- 原生页面、表单、请求、OAuth/PKCE、hCaptcha、购买幂等和恢复逻辑均来自 [1molchuan/CFluxDo](https://github.com/1molchuan/CFluxDo)，按固定提交 `e5b8ea9ee43cd64469760fa99b99ed0c4e2f772e` 构建。
- 两个不同 APK 使用独立包名 `com.github.lingyan000.fluxdo.plugin.cdk` 与 `com.github.lingyan000.fluxdo.plugin.ldshop`。
- 两者保留原生 Flutter 页面（`CdkHomePage` / `LdStoreHomePage`），通过专属启动入口替换原 CFluxDo 主界面路由；底层复用原仓库网络与账号运行时，避免删掉 OAuth/支付相关安全行为。
- AndroidManifest 公开 `com.github.lingyan000.fluxdo.action.PLUGIN` / DEFAULT / API_VERSION=1，并只为系统浏览器授权保留精确的 `discourse://auth_redirect` 回调；**无 LAUNCHER、无主站 HTTPS 深链拦截**。安装后从 Fluxdo「设置 → 插件」打开（工具插件不占用编辑器表情分页）。
- 插件进程、Android 沙箱、Cookie 和账号与 Fluxdo **不共享**；第一次使用各自登录 Linux.do。LD 士多的商品浏览无需登录，其余受保护的功能仍走原生 OAuth。
- 本版为了准确保留上游业务行为，两个 APK 构建时仍链接 CFluxDo 通用运行时，**并非精简版独立依赖包**，包体及部分后台初始化有后续缩减空间。

源码受原仓库及本仓库 **GPL-3.0** 约束。上游版本固定以避免未审计的改动自动进入可执行发布产物；升级时单独更新工作流 SHA 并重新验证。

## 构建和更新

在 GitHub Actions 里运行 `.github/workflows/cfluxdo-native-plugins.yml`，分别产出：

- `fluxdo-cdk-plugin-android-arm64.apk`
- `fluxdo-ldshop-plugin-android-arm64.apk`

构建使用 Flutter 3.47.9 和 Android ARM64，上传两个独立 APK 到 Nightly（不套额外 ZIP）。CI 在编译前运行 Android 插件契约回归测试，APK 编译后检查无桌面 Launcher、具有受限 OAuth 回调，且不申请 `QUERY_ALL_PACKAGES` 或 `REQUEST_INSTALL_PACKAGES`。Nightly 发布仅允许 `main` 分支执行。此工作流使用已有的 **公开测试签名证书**保证 Nightly 版本可覆盖安装；请勿将此证书当作生产签名凭据。

本地复现可检出固定提交的 CFluxDo，复制 `entrypoints/*.dart` 到其 `lib/`，用 `prepare_android.py --root <CFluxDo> --plugin cdk|ldshop` 完成包名及入口适配，再用对应的 `--target` 执行 `flutter build apk --release --target-platform android-arm64`。

## 边界

插件不是将主程序的凭据跨沙箱注入第三方 APK；未经显式授权不会共享会话。两者不会拦截 LINUX DO 的通用链接；从帖子内自动路由到对应插件尚需要后续的安全 Intent 数据协议。当前只提供安装后发现及原生页面启动，购买与领取请在真机确认授权回调后再使用。

## 浏览器授权回调注意事项

Discourse User API Key 默认使用固定的 `discourse://auth_redirect` 回调；操作系统会把能够处理该回调的应用放在同一个选择列表。若同时安装 Fluxdo、CDK 与 LD 士多三个 APK，通过系统浏览器授权时需选择**发起本次授权的插件**；选错应用会因各自私钥和随机 nonce 不同而忽略回调，登录不会完成。可回到对应插件重新授权，也可优先在插件内部使用账号密码登录。此限制无法仅靠调整 AndroidManifest 消除，最终解决需要支持独立回调标识的授权流程。

两个插件的授权凭据、Cookie 和密钥仍保存在各自 Android 沙箱；授权回调只接受 `discourse://auth_redirect`，不抢占其他 `discourse://` 或 HTTP(S) 链接。
