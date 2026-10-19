# Fluxdo NSH 客户端（渐进迁移工作区）

**状态：P1 只读开发预览。** 尚未完成正式客户端重写，未接入登录、聊天、通知、编辑器或附件上传。它不替代 Flutter 正式构建。

## 已落地的 UI

- 原生 NSH TSX 应用入口 App.tsx，使用 NSH createNavigator、Stack、Screen 和 SafeAreaView；窄屏底部 Tab，宽屏固定侧栏和并排帖子预览。
- 最新话题、本周热门、公开分类列表与分类过滤；论坛真实匿名 GET API、按页加载、列表内搜索、刷新、空态/错误状态。
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
