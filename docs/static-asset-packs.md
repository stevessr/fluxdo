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
