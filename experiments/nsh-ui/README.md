# Fluxdo × Native Shell (NSH) 界面迁移实验

> **状态：实验性只读原型，不是 Fluxdo 正式 UI 的替代品。**
>
> 不修改 `pubspec.yaml`、Flutter 原有导航、Riverpod 状态和登录会话；此目录可以独立删除。

## 为什么先从信息流试验

当前 Fluxdo 的 `TopicsScreen` / `TopicsPage` 已经与 Flutter 的平行双栏导航、Riverpod、Flutter 动画和 Discourse 服务层深度耦合。NSH 使用独立的 QuickJS + Rust 运行时、TSX 和平台原生视图，**不是一个可直接 import 的 Flutter Widget 包**。因此先做一个完全隔离、可运行、能读取真实公开数据的技术验证，再决定是否值得开发 Flutter 桥接层。

本原型已经实现：

- 最新话题、本周热门话题切换（匿名 GET `/latest.json` / `/top.json?period=weekly`）。
- NSH `List` 原生虚拟列表、下拉刷新、客户端即时过滤、主题卡片、回复/浏览/赞数。
- 点进话题读取 `/t/{slug}/{id}.json`，展示最多 12 帖的**纯文本预览**、返回列表。
- 加载/失败/重试状态；通过请求代数避免旧请求覆盖最新选中页面。
- `nsh.json` 网络能力白名单：仅允许对 `linux.do` 进行 HTTPS GET；不接受用户 Cookie、API Key 或密码。

**未实现且不得暗示已实现：** 登录、发帖、回复、Chat/WS、富文本、图片、多账号、通知、用户设置、双栏导航、插件动态加载及与 Flutter 的混合渲染。

## 运行

先按 [NSH 官方指南](https://nsh.dev/docs/installation/) 安装 `nsh`。从仓库根目录执行：

```sh
nsh check experiments/nsh-ui/App.tsx
nsh trace experiments/nsh-ui/App.tsx
nsh run experiments/nsh-ui/App.tsx --target linux
# 或：--target android / ios / macos / windows / web
```

NSH 的 `nsh check` 会生成相应声明文件并执行类型检查；`nsh trace` 可在没有桌面/手机模拟器时检查初始渲染和按钮操作。目标平台的 SDK / GTK / 原生工具链要求见 NSH 平台文档。

本次代码提交环境未安装 NSH，也无法联网下载 CLI，**未完成真实 `nsh check` / `nsh trace` / 运行时测试**。这些命令是待执行的验收项，不代表已通过。

建议验收步骤：

1. `nsh check` 和 `nsh trace` 无编译/运行时异常。
2. 最新/热门切换后显示实时公开数据，快速来回切换不会乱序覆盖。
3. 进入话题查看正文、返回列表并验证搜索与刷新。
4. 断网、403、超时、无数据时显示错误或空态；不会暴露任何登录数据。
5. 在目标平台测试键盘、滚动、触摸、无障碍和内存占用，并与 Flutter 原生界面比较。

## 集成正式 Fluxdo 之前必须解决

| 平台 | 集成路径 | 关键问题 |
| --- | --- | --- |
| Android | 将官方 `NshView`（AAR）包裹为 Flutter `AndroidView` / PlatformView | 视图生命周期、手势竞争、键盘、返回手势、画面合成、AAR 体积 |
| iOS | 将 `NshAppView`（XCFramework）封装成 Flutter `UiKitView` | Swift 嵌入、焦点、文本输入、生命周期、签名 |
| Linux | 独立 NSH GTK4 页面/进程或研究 GPUI 桥接 | NSH GTK 4.14+ 与现有 Flutter Linux GTK 嵌入技术栈不同；不要直接假设可混用同进程 GTK3/GTK4 |
| Windows | 官方 NSH Win32 `AppView` 与 Flutter 原生窗口 API 对接 | HWND 嵌入、大小同步、焦点、透明度及 GPU/Direct2D 合成 |
| macOS | AppKit `AppView` + Flutter 平台视图 | NSView 生命周期、输入事件及窗口栈 |
| Web | `createPlayer` 或独立 Web 运行时 | CORS、Cookie 隔离与宿主消息桥 |

接下来建议开发**严格受控的 Host Bridge**，而不是让 JS 直接管理 Fluxdo 的 Cookie：

```text
Flutter/Riverpod 与 DiscourseService（认证状态的唯一真相）
  └── 经明确授权的 Host Bridge（请求校验、能力限制、取消与错误映射）
      └── NSH TSX 原生 UI 组件（仅接收必要数据与命令）
```

Bridge 第一阶段只暴露 `listTopics` / `readTopic` / `openTopic`，第二阶段再视成熟度扩展草稿、附件及聊天能力。任何动态下载的 `.nshpkg` 必须通过签名校验，按站点及账户授予最小权限，禁止任意访问账户凭据。聊天需要宿主管理 WebSocket/SSE：NSH 目前提供 `fetch`，但其文档明确不提供 WebSocket API。

插件架构需与现有 Dart `SitePlugin` 区分：前者是可加载的 UI 模块，后者仍负责业务钩子；不能因为名称相同就混用信任权限。

## 参考

- [NSH 官方文档](https://nsh.dev/docs/)
- [NSH 网络能力与沙箱](https://nsh.dev/docs/networking/)
- [NSH 原生虚拟列表](https://nsh.dev/docs/lists/)
- [NSH 测试与 trace](https://nsh.dev/docs/testing-and-trace/)
- [NSH 嵌入平台概览](https://nsh.dev/docs/platforms/)
