# FluxDO × Discourse / linux.do 功能缺失审计

> 初始审计：2026-09-02  
> Wave 1 校正：2026-09-03  
> 审计分支：`feat/discourse-parity-wave1`  
> 对标目标：当前 Discourse Core + linux.do 日常使用场景
>
> **重要：本文件以当前代码事实为准。** 旧审计中的“缺失”若已在代码中存在，应改成“已实现/部分实现”，禁止后续 Agent 为了完成清单重复造 service、provider 或页面。

## 1. Wave 1 结论

FluxDO 已经覆盖普通用户的大多数主链路。本轮重新核对后，以下内容确认属于**旧审计误报**，不应再当成待实现大模块：

- `discourse-local-date`：`fluxdo_render` 已有原生支持。
- User Activity Replies：现有资料页使用 Discourse `user_actions` filter `5`。
- User Activity Likes Given：现有资料页使用 `user_actions` filter `1`。
- Solved / Accepted Answer：model、Accept/Unaccept API、帖子操作、状态同步、主楼 solution banner、用户 Solved tab 已形成闭环。
- Bookmark Reminder CRUD：name、reminder time、presets、custom time、clear/reset、auto-delete preference 已存在。
- PM Unread、Group PM、Group Membership Request、Posts / Mentions：安全基线中已经实现。
- Chat Direct/Group 二级选择：安全基线已经使用同一个 `TabController` 同时驱动高亮与可见内容，本轮补回归测试而不是重写架构。

本轮真正补齐的普通用户 gap：

1. Personal PM `New` mailbox 正式接入现有分页、选择和批量归档体系。
2. Warnings mailbox 按服务端 capability/response 显示。
3. PM Tags 使用 Discourse 原生服务器路由，不在客户端拉全量 PM 过滤。
4. Group Topics 使用服务端 group-topics 路由，并加入 Activity 的 Topics / Posts / Mentions 三分栏。
5. Tag notification 修正 canonical route，并保留 Category/Tag 的 level `4`（Watching First Post）。
6. Tag 页面增加 0..4 五档 tracking UI；Topic 保持 0..3。
7. Notifications UI 建立 Responses / Likes Received / Mentions / Edits / Links 分类模型。
8. 增加 “Bookmarks with reminders” 用户可见入口，并明确日历型 reminder 的 DST / timezone 语义。
9. `blockedUsernames` 在实际过滤 UI 中明确标识为“仅本机屏蔽过滤”，与服务端 mute / ignore 区分。
10. Direct Messages → Channels → Direct Messages 增加状态一致性 regression test。

本轮**没有**扩展为完整 Staff/Admin/Security/User Preferences 项目；这些仍属于后续范围。

---

## 2. 上游核对原则

所有新增 route 必须参考当前 Discourse 源码，不凭记忆猜测。本轮已核对：

- PM Tags：`/u/:username/messages/tags/:tag_name`。权限由服务端检查当前用户与 `can_tag_pms?`。
- Group Topics：`/topics/groups/:group_name`。服务端执行 group/member 可见性检查，不应由客户端展开成员列表拼 topics。
- Tag notifications：当前 canonical route 为 `/tag/:tag_id/notifications.json`。
- Group Posts / Mentions：使用 `before_post_id` cursor，而不是虚构 `offset` 分页。
- Membership request reject：不能发送非空字符串 `"false"`；拒绝时不传 `accept`。

权限显示原则：优先 serializer / capability / server response，禁止用“是不是 linux.do moderator/admin”硬编码客户端权限。

---

## 3. 状态定义

| 标记 | 含义 |
| --- | --- |
| ✅ | 当前范围已实现；后续以回归/边界维护为主 |
| 🟡 | 主链路已实现，但仍有外围 capability/plugin/真实站点验证项 |
| 🟠 | 有安全 fallback，但未知插件仍需 adapter |
| ❌ | 当前确实未实现 |
| STAFF | 仅 staff/moderator/admin 有意义，必须按服务端 capability 显示 |

---

## 4. 功能矩阵

### 4.1 Content / cooked HTML compatibility

| 功能 | 状态 | 当前事实 |
| --- | --- | --- |
| Topic 基础阅读 / 媒体 | ✅ | 成熟主链路 |
| `discourse-local-date` | ✅ | renderer 已有原生 builder；旧审计误报 |
| Core interactive cooked roots | ✅ | registry 已登记 poll、policy、chat transcript、details、iframe、video/audio、onebox、image grid、spoiler、math 等 |
| Unknown interactive HTML | ✅/🟠 | `button/form/input/select/textarea`、`onclick`、`data-action`、`data-controller` 等不会静默变纯文本，会进入明确 warning/web fallback |
| Runtime transform adapters | ✅ | 支持 register / unregister，core id 不允许覆盖 |
| Parse cache correctness | ✅ | registry revision 已进入 `RenderParseCache.signatureOf(...)`；短帖和长帖 chunks 均接入 |
| Registry regression tests | ✅ | 覆盖 known poll、unknown interactive fallback、runtime transform、core id overwrite |
| linux.do 专属插件 fixtures/adapters | 🟡 | 应继续按实际插件增加，不污染 renderer ABI |
| 无直接 URL 的未知插件“打开当前帖子网页版” | 🟡 | 可作为后续 fallback 增强，不是本轮 registry v1 阻塞 |

结论：**4.1 v1 已完成，不要重新实现 local-date 或改 `fluxdo_render` sealed Node ABI 来硬塞插件。**

### 4.2 Composer

| 功能 | 状态 | 备注 |
| --- | --- | --- |
| 新建主题 / 回复 / 编辑 | ✅ | 主链路完整 |
| Draft | ✅ | 已有本地/服务端草稿体系 |
| 上传 | ✅ | 已有 upload service |
| Rich composer | ✅/🟡 | 继续关注插件 composer 扩展即可 |

### 4.3 Bookmark Reminder

| 功能 | 状态 | 当前事实 |
| --- | --- | --- |
| Bookmark / Unbookmark | ✅ | 已有 |
| Bookmark list | ✅ | 已有成熟书签 workspace/cache |
| Bookmark name | ✅ | model + edit UI 已支持 |
| Reminder timestamp | ✅ | create/update 已支持 |
| Reminder presets | ✅ | 现有 `BookmarkEditSheet` |
| Custom reminder | ✅ | 日期/时间选择已存在 |
| Clear/reset reminder | ✅ | 已存在 |
| Auto-delete preference | ✅ | 已存在 |
| Bookmarks with reminders | ✅ | 本轮增加用户可见页面；复用现有账号隔离 bookmark provider，不建第二套 service |
| 本地分页完整性 | ✅ | reminders 页进入时 hydrate 剩余缓存页，避免 reminder 在第 2 页以后却错误空态 |
| 点击定位 | ✅ | topic bookmark 复用 `resolveBookmarkScrollToPostNumber` 精确定位；Chat bookmark 走统一内容链接分发 |
| Notification deep-link | ✅/🟡 | bookmark reminder 继续走统一 notification topic/post deep-link；可继续增加真实服务器 payload fixture |
| Timezone / DST | ✅ | `Tomorrow / 3 days / Next week` 按本地日历 08:00 构造，service 发送前转 UTC；已有回归测试 |

结论：旧报告“Bookmark Reminder 缺失”错误。真正缺口只是外围真实站点 payload/smoke，不是重写 bookmark service。

### 4.4 Private Messages

| 功能 | 状态 | 当前事实 |
| --- | --- | --- |
| Inbox | ✅ | 已有 |
| Unread | ✅ | 已接现有分页体系 |
| New mailbox | ✅ | 本轮把已有 service API 正式接入分页/选择/批量归档 UI |
| Sent | ✅ | 已有 |
| Archive | ✅ | 已有 |
| Composer / New PM | ✅ | 已有 |
| 多选批量归档 | ✅ | Inbox / Unread / New / Sent 可复用；成功后刷新全部 mailbox |
| Warnings | ✅ | capability/response 驱动，不用 staff/admin 硬编码 |
| PM Tags | ✅ | 原生服务器 route；服务端负责权限和过滤 |
| Group PM Inbox / Unread / New / Archive | ✅ | 已有并挂到 Group detail |
| PM 搜索的网页细粒度 parity | 🟡 | 可后续专项核对，不影响本轮 mailbox 闭环 |

### 4.5 Chat 状态一致性 / 已读

| 功能 | 状态 | 当前事实 |
| --- | --- | --- |
| Channels / Direct Messages | ✅ | 主架构成熟 |
| MessageBus / presence | ✅/🟡 | 现有实现保留 |
| Read cursor / read-time synchronization | ✅ | 已在近期主架构中存在，不重写 |
| Direct / Group 二级 tab 单一状态源 | ✅ | 同一个 `TabController` 同时驱动 TabBar 与 `IndexedStack` |
| DM → Channels → DM regression | ✅ | 本轮新增 widget test，验证可见内容与 controller index 同步 |
| Plugin-specific chat extensions | 🟠 | 继续走 adapter/capability |

### 4.6 Notifications UI parity

API 主架构无需重写：recent、history pagination、read/unread、mark one/all read 均已成熟。

| 分类 | 状态 | Notification types |
| --- | --- | --- |
| Responses | ✅ | replied `2`, quoted `3` |
| Likes Received | ✅ | liked `5`, liked consolidated `19`, reaction `25` |
| Mentions | ✅ | mentioned `1`, group mentioned `15` |
| Edits | ✅ | edited `4` |
| Links | ✅ | linked `11`, linked consolidated `39` |
| Messages | ✅ | private message / group message summary |
| Bookmarks | ✅ | 进入真实 bookmarks，而不是把 reminder notification 冒充完整书签列表 |
| Other/plugin notifications | ✅/🟠 | complement 保留 custom/plugin types，不因没有专用 icon 而丢失通知 |

`NotificationCategory` 是分类与 `filter_by_types` 的单一来源，Widget 不再散落 magic numbers。Solved accepted notification 作为 custom/plugin notification 被保留，并继续使用统一 action/deep-link。

### 4.7 User Activity

| 功能 | 状态 | 当前事实 |
| --- | --- | --- |
| Topics | ✅ | 已有 |
| Replies | ✅ | `user_actions` filter `5`；旧审计误报 |
| Likes Given | ✅ | `user_actions` filter `1`；旧审计误报 |
| Bookmarks | ✅ | 已有 |
| Bookmarks with reminders | ✅ | 本轮补用户可见入口 |
| Drafts | ✅ | 已有 |
| Pending | ✅ | 自己的待审核内容 |
| Read | ✅/🟡 | 仍可专项核对 `/activity/read` 语义 |
| Deleted Posts | ❌/STAFF | 按上游 capability 后续处理 |
| Badges | ✅ | 已有 |

### 4.8 服务端社区账户设置

这仍是后续较大的普通用户 gap，但**不属于 Wave 1 原始 4.x 核心任务**。安全基线中的 `community_user_preferences.dart` model 不等价于完整 Account/Security/Profile/Emails/Notifications/Interface 页面。

本轮不继续扩展：

- Change Email / Password
- TOTP / WebAuthn
- Sessions / Revoke Session
- Associated Accounts / Authorized Apps
- 完整邮件设置
- 完整 Interface / Navigation preferences

后续实现时应保持“FluxDO 本地设置”和“社区服务端设置”两个概念明确分离。

### 4.9 Groups

| 功能 | 状态 | 当前事实 |
| --- | --- | --- |
| Directory / Detail / Members | ✅ | 已有 |
| Join / Leave | ✅ | capability 驱动 |
| Membership Request | ✅ | `allow_membership_requests` + 非成员 + 不能直接 Join 时显示，可填 reason |
| Membership Request moderation | ✅ | requester list / reason / requested_at / approve / reject |
| Activity: Topics | ✅ | 本轮使用 `/topics/groups/:group_name`；服务端负责 group/member 权限 |
| Activity: Posts | ✅ | `before_post_id` cursor |
| Activity: Mentions | ✅ | `before_post_id` cursor |
| Group Messages | ✅ | Inbox / Unread / New / Archive |
| Owner/Admin full Manage pages | 🟡/STAFF | profile/membership/interaction/email/categories/tags/logs 不在 Wave 1 范围 |
| Permissions view | 🟡/STAFF | 后续按 serializer/guardian capability |

### 4.10 Tracking / Mute / Ignore

Discourse 的 Topic 与 Category/Tag notification level 数量不同：

- Topic：0 muted / 1 regular / 2 tracking / 3 watching
- Category / Tag：额外包含 4 watching first post

因此不能继续让 Category / Tag 使用只有 0..3 的 `TopicNotificationLevel`。

| 对象 | 状态 | 当前事实 |
| --- | --- | --- |
| Topic | ✅ | 现有 0..3 API/UI 保持 |
| Category | ✅ | 现有 `CategoryNotificationLevel` 与五档 UI 已存在；旧审计低估 |
| Tag service | ✅ | 本轮改成 `DiscourseTrackingLevel` 并修正 `/tag/:tag/notifications.json`，level 4 不再丢失 |
| Tag UI | ✅ | 本轮增加五档通知按钮；GET 成功才显示，不猜 staff/admin 权限 |
| Server muted users | ✅ | 用户资料已有服务端状态/操作 |
| Server ignored users | ✅ | 用户资料已有服务端状态/操作 |
| Local `blockedUsernames` | ✅ | 保留本地过滤，但实际过滤提示明确标记“仅本机屏蔽过滤” |

结论：本地 block 与服务端 mute/ignore 是两套语义，后续不得混为同一状态。

### 4.11 Solved / Accepted Answer

旧报告“当前主分支未发现完整 Accepted Answer 链路”是误报。当前已有：

- Topic / Post：`hasAcceptedAnswer`、`canHaveAnswer`、`acceptedAnswer`、`canAcceptAnswer`、`canUnacceptAnswer` 等字段。
- API：`acceptAnswer(postId)` → `/solution/accept`；`unacceptAnswer(postId)` → `/solution/unaccept`。
- UI：帖子菜单按 capability 显示 Accept / Unaccept。
- Action：API、local accepted state、callback、toast 已处理。
- `PostSolutionBanner`：主楼显示 solution 摘要并精确跳楼。
- Profile Solved tab：`/solution/by_user.json`。
- Solved accepted notification：custom/plugin notification 不会被分类系统吞掉，并可使用统一 topic/post deep-link。

仍可后续核对 Solved/Unsolved topic discovery filters，但**核心闭环已经完成，不得再重复添加 accept/unaccept wrapper。**

### 4.12 Topic moderation / 高级动作

普通用户不需要默认看到；不属于 Wave 1 扩展范围。后续按 serializer / guardian capability 核对：Close/Reopen、Pin/Unpin、Global pin、Topic timer、Slow Mode、Banner、Move/Split/Merge、Change Owner 等。

### 4.13 Staff Review Queue

当前“我的待审核内容”不等于 STAFF Review Queue。Flags、Queued Posts、Users needing review、reviewable filters/actions 仍属于独立 STAFF 项目，不应为了普通用户 parity 混进本轮。

### 4.14 Security / Account lifecycle

2FA、security keys、sessions、associated accounts、authorized apps、deactivate/delete 等仍是后续高风险/高权限范围。

---

## 5. Content Extension 维护原则

`DiscourseContentExtensionRegistry` 已成为 cooked HTML → parser 前的兼容层：

```text
cooked HTML
  ↓
DiscourseContentExtensionRegistry
  ├─ native core nodes
  ├─ runtime transforms / plugin adapters
  └─ unknown interactive warning + web fallback
  ↓
existing parser / fluxdo_render ABI
```

后续必须遵守：

1. 已知 Core 能力优先原生。
2. linux.do / plugin 特性通过 adapter 注册，不污染通用 renderer。
3. 未知明显交互节点不能静默变纯文本。
4. registry 改变必须使 parse cache 失效。
5. 不为了支持一个插件轻易修改 `fluxdo_render` sealed Node ABI。

---

## 6. 不应重复投入的大模块

以下能力已经跨过“功能缺失”阶段，后续应以 bugfix、边界、一致性和真实站点 smoke 为主：

- 话题基础浏览、分类、标签、搜索
- 发帖 / 回复 / 编辑 / Draft / Upload
- Chat 主架构、read cursor、Direct/Group 二级 tab 状态源
- Notifications API 主架构
- Bookmark Reminder CRUD + reminders view
- PM Inbox / Unread / New / Sent / Archive + bulk archive + Warnings + PM Tags
- Group directory/detail/members/join/leave/request moderation/activity/group messages
- User Activity Replies / Likes Given
- Topic Voting
- Solved / Accepted Answer 核心闭环
- `discourse-local-date`
- Badges

---

## 7. Wave 1 之后的真实剩余项

### 普通用户

1. 完整的服务端 Community Preferences（独立于 App 本地设置）。
2. User Activity Read 的精确语义与 Deleted Posts capability。
3. PM search/filter 的长尾网页 parity。
4. Content registry 的更多真实 linux.do plugin fixtures 与无 URL fallback。
5. Plugin notification 专用 icon/action adapters（generic action 已保留）。
6. 标准 Discourse + linux.do 多账号 smoke / Web parity 验证。

### Staff / Advanced

7. Topic moderation 高级动作。
8. Staff Review Queue。
9. Security / 2FA / sessions / apps。
10. Group owner/admin 全管理页。

---

## 8. Definition of Done

一个 parity 项不能因为“页面能打开”就算完成：

- [ ] API route 与当前 Discourse 源码一致
- [ ] Read / Write model 不静默丢关键状态
- [ ] UI 按 server capability 显示
- [ ] mutation 后 cache/realtime 一致
- [ ] 401 / 403 / 404 / 409 等错误合理处理
- [ ] 多账号 provider/cache 不串状态
- [ ] `dart format` / `flutter analyze` / 相关 `flutter test` / `git diff --check` 通过
- [ ] 标准 Discourse 实例 smoke
- [ ] linux.do 真实账号 smoke
- [ ] 对服务端设置类功能完成 Web ↔ FluxDO 双向可见性验证

---

## 9. Capability matrix（Wave 1 校正版）

| Feature | Core/Plugin | API | Model | Read UI | Write UI | Regression | 备注 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Content registry v1 | Core/Plugin | — | ✅ | ✅ | adapter | ✅ | local-date 已原生 |
| Bookmark Reminder | Core | ✅ | ✅ | ✅ | ✅ | ✅ | 日历 preset 有 timezone/DST test |
| PM Unread/New/Warnings | Core | ✅ | ✅ | ✅ | archive ✅ | CI | Warnings capability 驱动 |
| PM Tags | Core | ✅ | ✅ | ✅ | — | CI | server-side filtering |
| Group Topics | Core | ✅ | ✅ | ✅ | — | CI | server-side group visibility |
| Group Posts/Mentions | Core | ✅ | ✅ | ✅ | — | ✅ | `before_post_id` |
| Chat subtab consistency | Core | ✅ | ✅ | ✅ | ✅ | ✅ | single TabController |
| Notification categories | Core/Plugin | ✅ | ✅ | ✅ | — | ✅ | custom/plugin preserved in Other |
| Topic tracking | Core | ✅ | ✅ | ✅ | ✅ | existing | 0..3 |
| Category tracking | Core | ✅ | ✅ | ✅ | ✅ | existing | 0..4 |
| Tag tracking | Core | ✅ | ✅ | ✅ | ✅ | ✅ | canonical `/tag/...` + level 4 |
| Server mute / ignore | Core | ✅ | ✅ | ✅ | ✅ | existing | 与 local block 分离 |
| Solved | Plugin | ✅ | ✅ | ✅ | ✅ | existing | 核心闭环已有 |
| Topic Voting | Plugin | ✅ | ✅ | ✅ | ✅ | existing | 不重做 |
| Review Queue | Core/STAFF | ❌ | ❌ | ❌ | ❌ | ❌ | 后续独立任务 |

本报告解释“为什么做”和“真正还缺什么”；具体执行状态见仓库根目录 [`TODO.md`](../TODO.md)。
