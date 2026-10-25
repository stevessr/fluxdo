# Fluxdo 可独立发布的静态资源包

本阶段落实资源的构建及发布模块化：每个资产组输出一个可复现的、按 SHA-256 内容寻址的 ZIP，以及汇总 catalog.json。当前 Flutter 主应用仍使用原来的 assets 路径，不改动运行时行为；在加载器和回退机制完成前，不能声称 APK 体积已减少。

## 独立资源包

| 包 ID | 内容 |
| --- | --- |
| font-misans | 20.09 MB MiSans 可变字体 |
| render-cook | Discourse 编辑器 cook JS |
| render-polyfill | Compatibility Polyfill JS |
| ai-brands | AI SVG 品牌素材及授权说明 |
| avatar-touhou | 东方角色资源 |
| avatar-blue-archive | 蔚蓝档案角色资源 |
| avatar-witch-judgment | 魔法少女审判角色资源 |
| avatar-llm | 通过 gen_avatar_deltas 生成的 LLM 主图和差分 |
| avatar-stevessr | 通过 gen_avatar_deltas 生成的 Stevessr 主图和差分 |

生成型角色资源不存在时列在 skippedGenerated 内，不生成空包。所有其他资源不存在即构建失败。

## 构建

在仓库根目录运行：

    python3 -m unittest discover -s scripts/ci/tests -p 'test_asset_packs.py' -v
    python3 scripts/ci/asset_packs.py build --root . --out build/asset-packs
    python3 scripts/ci/asset_packs.py verify --catalog build/asset-packs/catalog.json

若需生成可选角色包，在已安装项目 Dart/Flutter 依赖的环境先运行：

    dart run tool/gen_avatar_deltas.dart

ZIP 内含 manifest.json，为每个资源保留逻辑路径、SHA-256 及字节数；catalog.json 校验整个 ZIP。压缩采用固定时间戳和排序输入，相同资源输出完全相同字节。内容寻址 ZIP 允许独立上传、长期缓存、单资源包升级和复用；catalog 建议短缓存。

这套 hash 校验仅证明完整性，不证明发布者身份。未来资源下载器必须采用可信发布源和签名或应用内置的可信摘要；不要加载任意来源的 JS。校验器拒绝危险路径、符号链接、未知资源类型、重复 ZIP 路径、超大条目和不一致的哈希。

## 下一阶段运行时和打包边界

- 为插件建立统一 AssetProvider：已验证本地包优先，包缺失时 rootBundle 回退。对 Cook JS 强制发布源信任和版本兼容检查。
- 为 20 MB MiSans 提供动态 FontLoader 和平台字体回退，在加载前不得从 pubspec 删除字体。
- 逐步迁移角色素材及 AI 品牌 SVG 的固定资源路径，之后才从 Android Core staging 排除它们；与 Draft PR #131 的独立 APK 安装及生命周期联测。
- 使用真实构建的 APK/AAB 对比 Core 体积、资源解码、离线行为和 Android 安装升级；不能用 ZIP 未压缩大小充当 APK 节约量。


## 运行时验证读取（第二阶段）

StaticAssetPacks.loadBytes/loadString 已提供安装资源优先、校验失败时 rootBundle 回退的统一入口。首个消费者是 DiscourseCookService；原始 JS 资源仍内置，零配置时行为保持不变。Web 平台使用本地资源包的空实现，不接触文件系统。

installTrustedZip 对调用方提供的外部可信 SHA-256、ZIP 内每项散列、大小和资源路径白名单进行验证；只在全部通过后切换激活指针。安装服务不负责下载及发布者身份认证，调用方必须通过可信发布源或签名确定 expectedSha256，不能让 ZIP 自行决定可执行 JS 的信任级别。

尚未实现插件管理页面下载/安装 UI、FontLoader 自动激活、完整角色渲染调用点迁移及 APK 真正减重，因此维持兼容的内置资源。

角色素材加载器 StevessrCharacterAssets 已迁移到统一资源接口，覆盖主图、差分和清单。未安装时继续从内置 rootBundle 读取。角色渲染结果的进程内缓存暂时需要重启以切换新的资源版本；后续应与包更新事件集成缓存失效通知。

手动触发 Actions 导出时会先运行生成型角色资源的 Dart 构建脚本，再打包；若缺少任一角色包则失败，避免发布缺失资源的‘完整’版本。PR/push 快速验证仍允许未生成目录被显式跳过。

通过可选编译常量 `--dart-define=FLUXDO_EXTERNAL_MISANS=true` 启用外置 MiSans 预加载；只有用户此前选择 MiSans 且已验证资源包可用，才会在启动时注册字体。切换到 MiSans 时也会尝试加载，缺失时保留系统字体。**该选项不自动删除 Flutter pubspec 的内置字体定义**，真正瘦身需要 Android staging 单独改写声明并完成回归。Polyfill 初次预加载以及包切换后重新加载均经过统一资源接口，旧异步结果不得覆盖新版本；现存 WebView 页面不能热替换已注入脚本，新 WebView 才能获得更新。


## 第四阶段：应用内资源包管理

新增「设置 → 静态资源包」页面，列出 9 个资源包的外置激活状态及完整 SHA-256；支持手动导入 ZIP、禁用、回滚并刷新状态。导入严格要求用户**先独立从可信发行渠道取得完整 ZIP SHA-256**，再选择本地 ZIP（不能从 ZIP 自身或不可信 catalog 取得信任依据）。文件大小限定 128 MiB，后台安装仍强制对完整 ZIP 与每个条目验证、限制展开大小。Web 不支持安装；内置资源保持可用。对外置字体与 WebView 已创建实例，仍可能需要重启或新开页面生效。

现阶段不提供任意 URL 自动下载或自动执行更新，因为 SHA256 仅提供完整性，没有可信发行者身份。后续应在发行管道签名 catalog、在客户端内置可信公钥并验证签名，才开放联网发现和下载。不能将无签名的 catalog.json 自己声称的哈希当作安全锚点。

应用内可手动清理旧包：仅匹配合法包 ID 与 64 位摘要命名目录、当前与 previous 一律保护、未知指针或目录内出现符号链接时拒绝清理。默认目录至少保留一天，读取/安装/清理由同一包锁串行化，不会删除并发读取内容。这个回收过程不会触及 Core 内置资源。


## Ed25519 签名目录

发布目录 catalog.json 的原始字节需使用仓库之外的 Ed25519 PEM 私钥签名，产生 catalog.sig。签名覆盖原始字节，不是对 ZIP 自带哈希的自我认证。使用 scripts/ci/sign_asset_catalog.py sign/verify。手动导出 Actions 要求 Secret FLUXDO_ASSET_CATALOG_ED25519_PRIVATE_KEY_PEM；无密钥则拒绝将目录发布为可信版本。客户端仅在构建时通过 --dart-define=FLUXDO_ASSET_CATALOG_ED25519_PUBKEY_B64=<独立核验的32字节公钥Base64> 提供发行公钥，未配置则拒绝签名目录安装。禁止将私钥提交到仓库。

本阶段尚未配置正式发布公钥、目录抗回滚计数或自动下载策略；普通手动导入仍要求用户独立核验 SHA-256。


DiscourseCookService 订阅 render-cook 包切换通知：安装、禁用和回滚都会丢弃旧的 JS runtime、清理 onebox 缓存并重新初始化；如果更新发生在一次异步初始化或 onebox 网络查询中，会阻止旧版结果覆盖新引擎。原始根内置 Cook 保留作为回退资源。


## Android MiSans 独立资源试验

可在已经复制的临时 Android Core Flutter 工程里运行 scripts/ci/prepare_android_static_resources.py --stage /tmp/fluxdo-core-stage，删除临时工程 pubspec.yaml 的唯一 MiSans 字体声明和字体文件；随后必须使用 --dart-define=FLUXDO_EXTERNAL_MISANS=true 构建。脚本拒绝修改源仓库、缺失系统字体回退、额外字体声明或路径变更。Android Core 的真实 APK 体积对比与离线测试仍需在 PR #131 整合后完成，不得把此脚本的字节数视作实测 APK 缩减。
