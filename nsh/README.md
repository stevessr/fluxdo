# Fluxdo NSH 客户端（渐进迁移工作区）

**状态：P1 只读开发预览。** 尚未完成正式客户端重写，未接入登录、聊天、通知、编辑器或附件上传。它不替代 Flutter 正式构建。

## 已落地的 UI

- 原生 NSH TSX 应用入口 App.tsx，使用 NSH createNavigator、Stack、Screen 和 SafeAreaView；窄屏底部 Tab，宽屏固定侧栏和并排帖子预览。
- 最新话题、本周热门、公开分类列表与分类过滤；论坛真实匿名 GET API、按页加载、列表内搜索、刷新、空态/错误状态。
- 独立的全站匿名搜索：显式提交、匹配帖子摘要、搜索分页、请求门禁和错误重试。
- 原生虚拟列表、话题卡片、按 post_stream.stream 分批（20 帖）加载后续楼层、请求竞态隔离。
- 按服务端 more_topics_url 分页（限制为同站公开信息流路由）、游标去重与重试。
- 跟随系统深浅色，独立数据映射和读请求能力边界，测试不依赖 Flutter。

**已知欠缺**：公开话题虽然已支持按 post_stream.stream 补读后续楼层，但 HTML 仍是纯文本预览，不保证与 Flutter 富文本等价；请求失败需要手动重试。导航返回状态与宽窄屏中途切换仍需真实设备验收。

## 结构

- App.tsx：NSH 原生 UI 壳 / 导航 / 只读业务入口。
- data.ts：API 解析、URL 编码、匿名读取。
- request_gate.ts：旧异步响应作废。
- tests/reader.test.mjs：Node 22 内置测试，不联网也能运行。
- nsh.json：linux.do 匿名 GET 网络白名单。

## 运行与检查

先安装官方 [NSH CLI](https://nsh.dev/docs/installation)。在仓库根目录运行：

    nsh check nsh/App.tsx
    nsh trace nsh/App.tsx
    nsh run nsh --target linux

NSH 具体命令参数应以本机 CLI --help 为准。Linux GTK 4.14+（Wayland 优先）；Android/iOS/macOS/Windows 构建需相应官方工具链。

单元测试（不依赖 NSH CLI，只需 Node.js 22）：

    node --experimental-strip-types --test nsh/tests/*.test.mjs

**验证声明**：本提交环境没有 NSH CLI，尚不能宣称 nsh check、headless trace 或平台打包通过。Node 单测添加到独立 CI，CI 结果以 Actions 实际运行结果为准。正式入口切换之前必须满足完整的功能、平台、安全和性能验收要求。

## 后续工作与规范

迁移总方案见 ../docs/nsh-full-ui-migration.md，逐文件清单见 ../docs/nsh-ui-inventory.md。后续优先建设稳定 Rust/Native Host Service（带账号隔离和显式权限），再将 Flutter 的 Discourse 会话、Rich Composer、Chat/WS/SSE、下载/图片/插件功能逐步交由 Host 驱动新的 NSH 原生 UI，禁止 TSX 保存原始令牌。

旧只读演示 ../experiments/nsh-ui/ 保留作为对照；新开发请落在 nsh/。


## CI 验收记录（2026-10-19）

- [数据层单元测试与 TypeScript 类型检查：通过](https://github.com/stevessr/fluxdo/actions/runs/39201454810)。
- [官方 NSH CLI 类型检查及 390×844 / 1200×800 headless trace：通过](https://github.com/stevessr/fluxdo/actions/runs/39201655673)。

本环境仍未安装 NSH CLI；上述为隔离的 GitHub Actions 验证结果。headless trace 并非 Android/iOS 真机、GTK 窗口或安装包权限沙箱测试，运行时操作体验仍待设备验收。

## 增量：只读阅读分页（2026-10-19）

- 话题信息流使用服务端 `more_topics_url`，补全 `.json`，限制在 linux.do 的 latest/top/category 只读路由，拒绝站外和异常游标。
- 话题详情根据 `post_stream.stream` 与首批帖子的差集获取剩余帖子 ID，每次最多请求 20 帖，按楼层排序合并去重。
- 对话题切换、刷新与分页并发使用 `RequestGate`，避免旧响应覆盖新页面；批次失败保留待加载 ID。
- 测试覆盖游标安全、楼层批次、数据顺序和网络适配器；CI 需复验 TypeScript 与 NSH headless trace。

## 增量：公开搜索（2026-10-19）

- 新增“搜索”Tab，调用 Discourse 官方 `GET /search.json?q=…&page=N`。
- 搜索在用户点击按钮后才发请求，不逐次发送输入中的字符；输入更改会使旧请求及旧结果失效。
- 将搜索返回的 `topics` 与 `posts` 关联为可点击的匹配项，帖子摘要只显示经过纯文本转换的内容；缺少完整话题字段时采用安全默认值。
- 允许在官方返回 `more_full_page_results` 时继续按页读取；同一话题、楼层的重复结果被过滤。
- 搜索仍然仅使用公开 GET，没有认证、搜索历史持久化或跨账号凭据。
- 点击带有匹配楼层号的结果时，会请求 `/t/:slug/:id/:post_number.json` 对应的服务端阅读窗口，并提供回到首帖的入口。NSH 列表尚未实现精确滚动锚定，需在真实设备上验证。

## P0 Host Bridge 契约基线（仅协议，不是已连接的 Native Host）

- 新增 `host_protocol.ts`：固定 v1 协议、只读命令白名单、JSON 帧大小限制、请求 ID 与版本校验、无敏感原生异常传播、页面/账号切换时的待决请求废弃。
- `unavailableHostTransport` 默认拒绝任何请求；**目前没有 Rust/Native Transport 实现**，`App.tsx` 仍沿用限定 linux.do 的匿名 GET 数据层。
- Native Host 必须独立强制验证账号 epoch、鉴权、权限和会话隔离；TSX 的白名单只是防御性输入约束，不能代替 Host 端权限边界。
- `tests/bridge.test.mjs` 使用假 Host 验证错误封装、过期响应、非法字段和帧上限。

## CI 调度

- Reader 与 Native Check 工作流添加按来源分支的并发组和 `cancel-in-progress`。同一 NSH 迁移分支的 push / PR 不再重复占用执行槽，后续提交会取消旧版本的排队或执行；最终验收只看最新提交。
- 搜索翻页最多到第 50 页；Host transport 未安装时报告 `unavailable`，区别于异常传输失败。

## 2026-10-20：分页隔离与公开传输安全回归

- 公共阅读器按信息流类型和选中分类核验服务端分页游标，避免游标跨列表切换；不可信查询仅允许 page / before，热门允许 period=weekly。
- 同站请求显式使用 `credentials: "omit"` 且 `redirect: "error"`，避免环境附带 Cookie 或通过重定向离开公开源站。
- Host Bridge 的 `feed.list` 游标与命令根级字段改为运行时严格校验，拒绝身份字段、重复分页参数和跨信息流游标。
- 回归测试同时覆盖分页上下文、伪造查询、网络 fetch 选项；这是 NSH 匿名数据层加固，不代表真实 Native Host 已接入。
