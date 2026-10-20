# Fluxdo → NSH 全量 UI 迁移技术路线

> **状态：计划/基线建立；当前没有完整可运行的 NSH 客户端。**
>
> **分支：** `migration/nsh-full-ui`，从 `main` 分出；不要覆盖 `main` 或直接删除 Flutter。

## 成功标准

最终的正式客户端全部视觉元素、导航与用户交互由 NSH 实现，业务服务和能力由可信 Rust/Native Host 提供；Flutter 的 UI 仅在经过功能、数据、性能、平台兼容和发行验收后退出。过渡期 Flutter 正式版与 NSH 开发版分开构建、保留可回退路径。

## 已有成果和限制

- 只读话题 UI 技术原型见 `experiments/nsh-ui/`（由 PR #138 对应的实验分支复制到当前长期分支）。这是**源代码原型**，并不等于已经完成 NSH 编译与平台验证。
- 依据截至 2026-10-19 `main` 的 `lib/` Git tree 初步生成包含 **467 个源码文件** 的 UI 核销基线，见 [nsh-ui-inventory.md](./nsh-ui-inventory.md)。该基线仅包含 `lib/pages`、`lib/widgets`、`lib/navigation`、`lib/settings`、`lib/theme`、`lib/plugins`；assets、底层服务、各平台原生资源及动态入口仍需补充。
- 注意不能假定 NSH 是 Flutter Widget：它拥有独立 TSX / Rust 运行时。Flutter PlatformView 桥接仅可作过渡方案，终态优先独立 NSH 应用。
- NSH 渲染/网络/本地存储/WS/SSE/富文本/图片/原生 WebView/插件等实际能力必须按官方当前 API逐一在目标平台验证，不使用臆测 API。

## 决定性架构契约

```text
┌────────────────────────────────────────────┐
│ Native Shell (TSX) 全量展示层                │
│   Route / Shell / Design / Accessibility   │
│   Feed / Topic / Composer / Chat / Plugins  │
└──────────────────┬─────────────────────────┘
                   │ versioned typed commands/events
┌──────────────────▼─────────────────────────┐
│ Host Bridge: 最小权限 / 身份与会话隔离      │
│   typed requests, cancellation, backpressure│
│   feature gates, telemetry and errors      │
└──────────────────┬─────────────────────────┘
                   │
┌──────────────────▼─────────────────────────┐
│ Rust / Native Service Core                 │
│   Discourse API / Account / Cookie / Cache │
│   MessageBus / SSE / WS / Upload / Media    │
│   OS Secure Store / Plugin Permission       │
└────────────────────────────────────────────┘
```

**单一事实来源**：迁移后由 Host 层统一管理账号/凭据与 Discourse 会话、实时连接、缓存、下载和持久化。NSH UI 只接收权限过滤后的 ViewModel（不得持有账号原始 Cookie、API Key 或独立的持久化会话），经 Host 命令发起业务变更。替代 Riverpod 时必须维持原有状态生命周期、双栏选择、窗口状态、深链和数据恢复语义。

**契约版本化**：客户端与 UI 插件共享明确定义的 ABI、事件顺序、错误码、取消语义、数据校验、安全授权和账户隔离；动态 UI 更新前做签名/版本检查，保留回滚机制。

## 分阶段实施及验收门槛

| 阶段 | 主要迁移 | 硬性验收门槛 |
| --- | --- | --- |
| P0 | CLI / SDK / Host core / 登录、路由、设计系统与 CI | Linux/Android 至少一条可运行 E2E；平台能力缺口清单；隔离凭据 |
| P1 | Shell、首页、分类、话题、搜索、平行视界 | 真实 API、富文本、持久滚动、导航一致性、性能基线 |
| P2 | Composer、个人页、通知、社区与管理功能 | 写请求/撤销/草稿/上传在弱网和多账号下可靠 |
| P3 | Chat、WebView/OAuth、媒体、插件、复杂工具页 | 实时连接、权限/签名、状态恢复、各平台交互无回退 |
| P4 | 设置、各平台原生系统集成 | 全部正式平台原生输入/导航/通知、Wayland 与 IME 验证 |
| P5 | 逐项核销、发行、退役 Flutter | UI 清单全部结清，测试/性能/安全/数据迁移/发布通过 |

## 关键模块验收清单

1. **身份与会话**：密码/OAuth/2FA/API Key/扫码登录、登出、账户快速切换、cookie 服务端分叉的修复、防止旧账户请求串流。
2. **阅读与导航**：分页和无限滚动、分类/标签/看板、帖内回复、楼层跳转、悬浮/双栏/窄屏状态保留。
3. **内容与编辑**：Markdown、Discourse cooked HTML、安全解析、代码高亮、附件/长图、图片预览、草稿、引用/提及、投票。
4. **Chat**：频道、实时已读/静音、群组、私信、头像粘滞、增量消息、系统返回手势和重连。
5. **平台与窗口**：Android / iOS / Linux Wayland 优先 / Windows / macOS 与必要的 Web 支持；输入法、窗口管理、深链、WebView 和分享。
6. **插件与扩展**：站点插件钩子完整保留，独立 UI 插件生命周期、能力授权、签名校验、更新与撤销。
7. **设置与隐藏入口**：设置定义驱动页、工具箱、日志/诊断、浏览历史、通知策略、登录回调、辅助弹窗，均纳入 inventory 及功能矩阵。

## 代码与工作流约束

- `main`、Flutter 正式构建/发布链路不被中断；NSH 产物须单独命名和隔离。
- 每个可交付单元应拆分独立 PR，记录旧路径与新路径映射、UI 截图/操作 trace、API 契约、性能回归、平台覆盖和回退方案。
- 迁移期修复若同时影响 Flutter 与 NSH 的业务逻辑，应优先修改共同的 Host 服务/协议，避免双端重复分叉。
- 使用 feature parity 而非代码逐字重写：UI 文件可以合并或拆分，但原功能必须在 inventory 中核销并链接证据。
- 迁移完成并通过端到端、回归、安全和多平台验收后，才可将 NSH 作为默认发行产品并删除已弃用的 Flutter UI。

## 追踪

- GitHub Issue 在创建此文档时被仓库禁用（API 410）。预填表单位于 `.github/ISSUE_TEMPLATE/nsh-full-ui-migration.md`，开启 Issues 后可从本分支复制模板正文创建 Epic（模板目前不在默认分支中，未必自动显示在 Issue 模板选择器中）。
- 原型：[#138](https://github.com/stevessr/fluxdo/pull/138)。现存只读预览不等同真实业务迁移。
- 目录清单：[nsh-ui-inventory.md](./nsh-ui-inventory.md)。勾选必须同时更新迁移 PR/测试链接；不要批量勾选未验收项。


## 2026-10-19：新增独立 NSH 应用壳（P0/P1 迭代）

- 新增 nsh/App.tsx：官方 createNavigator + Stack/Screen，手机底部导航、桌面侧栏和双栏话题预览、跟随系统深浅色。
- 新增 nsh/data.ts：公开话题、分类、帖子只读 API，输入验证、纯文本渲染、页码及路径校验；nsh/request_gate.ts 隔离过期响应。
- 分类列表/分类筛选、最新/热门列表、刷新、分页按钮、本地过滤、空态与错误态已有源代码。
- [数据层单元测试及类型检查已通过](https://github.com/stevessr/fluxdo/actions/runs/39201454810)。
- [官方 nsh check 与手机/桌面双视口 nsh trace 已通过](https://github.com/stevessr/fluxdo/actions/runs/39201655673)。
- **验收范围**：仅验证匿名只读数据层、TSX 编译和 headless 首帧，不等于设备实测、已登录读写、完整富文本或多平台发布。467 项 Flutter UI 资产仍待逐一核销。

## 2026-10-20：Boards 只读界面迁移（P1 扩展）

- 官方 Boards `GET /boards/api/boards.json` / `GET /boards/api/boards/:id.json` 接入匿名 PublicReader；依据上游 Boards Serializer 解析看板、栏目、Topic/Floater 卡片。
- NSH 独立「看板」Tab，公开权限标识、栏目和卡片展示、话题卡片直接进入既有话题阅读导航。针对手机七入口改用紧凑原生导航控件。
- 服务端 `anonymous_can_read` 必须允许公开阅读，否则拒绝详情；详情 ID 绑定用户选中看板，数据最小化投影、竞态作废、条目限制和失败重试。
- Mock 测试涵盖目录去重/归档过滤、私有看板拒绝、非法 ID、卡片投影、渲染预算。
- [Reader 单测通过](https://github.com/stevessr/fluxdo/actions/runs/39358465421)；[Native NSH check/双视口 headless trace 通过](https://github.com/stevessr/fluxdo/actions/runs/39358461911)。
- **不代表 Boards 功能等价**：目前不支持登录后受保护看板、卡片写入与移动、实时更新、栏目拖拽、权限编辑或真实设备 E2E；不得在清单中核销 Flutter 的完整 Boards UI。


## 2026-10-20：标签目录与话题阅读（P1）

- 已核对上游 Discourse `tags#index` 返回的 `/tags.json` 元数据及 `/tag/:tag_slug/:tag_id.json` 标签话题路由。
- NSH 「分类」内提供标签目录、名称筛选、话题计数和描述文本；标签列表保留本地分页边界并过滤重复 ID/同义词。
- 标签页使用服务端提供的 `more_topics_url` 进行连续读取，但只接受与当前 slug/ID 相同、合法的同源分页游标；禁止动态执行站外链接或混用其他标签响应。
- 顶层最新/热门导航可清除标签上下文；从分类和标签选项进入同一只读阅读组件。无独立新底栏标签，避免移动端拥挤。
- [Reader 单元测试通过](https://github.com/stevessr/fluxdo/actions/runs/39359380358)；[NSH Typecheck + 390×844 / 1200×800 headless trace 通过](https://github.com/stevessr/fluxdo/actions/runs/39359376416)。
- 尚未完成：tag intersection、分类+标签交叉筛选、登录后私人标签、服务端变更、真机返回/滚动状态和逐项 Flutter 功能核销。

## 2026-10-20：组合筛选与匿名 Cloudflare 失败状态（P1 扩展）

- [x] 原生话题页允许在分类目录、标签目录之间往返并保留已有过滤条件；请求由 Discourse 服务端分类 + 标签交集接口处理，支持同上下文游标分页。
- [x] 公开列表和服务器分页校验扩展至 `/tags/c/:category_slug/:category_id/:tag_slug/:tag_id.json`。使用不泄露凭据的 Node Mock 证明：跨分类/标签、额外参数/重定向/外域游标均不会发送请求。
- [x] 公共传输独立错误分类：Cloudflare 验证、权限拒绝、内容缺失、无效 JSON、网络失败。匿名 403 不会触发账户注销或失效标记。
- [x] Reader test / TS typecheck：[39362677743 成功](https://github.com/stevessr/fluxdo/actions/runs/39362677743)；官方 NSH check + headless trace：[39362673044 成功](https://github.com/stevessr/fluxdo/actions/runs/39362673044)。
- [ ] 将单层分类 slug 升级为经过父分类链校验的完整 category slug path；独立覆盖嵌套分类组合筛选。
- [ ] 实机验证过滤导航、返回历史、输入法/无障碍、站点真实数据与 CF 网页验证交互（headless trace 只验证初始屏）。
- [ ] Native/Rust Host 会话隔离及 read/write、Rich Composer、Chat、Boards、插件与完整 Flutter 对照验收，均未完成。

保持本分支为 Draft，保留 Flutter 正式客户端与现有发布路径。
