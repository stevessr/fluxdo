# FluxDO × Discourse / linux.do 功能缺失审计

> 审计日期：2026-09-02  
> 对标目标：Discourse 当前主干能力 + linux.do 实际使用场景  
> 审计分支：`main`  
> 目标：让 FluxDO 从“可用的第三方客户端”逐步达到“可以长期替代 linux.do 网页版进行日常使用”的完整度。

## 1. 结论摘要

FluxDO 当前已经完成了绝大多数普通用户的主链路：话题浏览、分类/标签、搜索、发帖/回复/编辑、草稿、上传、通知、书签基础能力、私信基础能力、Chat、群组基础能力、徽章、投票、AI Bot 等。因此下一阶段不应继续以“新增大入口”为主要目标，而应该集中处理 Discourse 的深层状态机、账号级偏好、插件交互和 staff/moderation 能力。

当前最重要的结构性缺口：

1. **Discourse 服务端个人设置不完整**：FluxDO 现有设置主要是 App 本地偏好，尚不能替代 Discourse 的 Account / Security / Profile / Emails / Notifications / Tracking / Users / Tags / Interface / Apps / Navigation / Calendar 等服务端设置。
2. **Tracking / Ignore / Mute 等账号级状态不完整**：目前部分过滤仍是 FluxDO 本地行为，无法与网页和其他客户端共享。
3. **Bookmark Reminder 缺失**：已有基础书签，但没有 Discourse 原生提醒生命周期。
4. **Cooked HTML / 插件交互兼容缺少统一扩展机制**：未知插件节点容易退化成“能显示但不能操作”。
5. **Solved 缺失**：Accepted Answer 的状态、动作、过滤和通知未形成完整链路。
6. **私信长尾状态未完成**：Unread、Warnings、Group inbox/archive、PM Tags。
7. **群组管理与群组活动不完整**：requests、mentions、group messages、owner/admin 管理页缺失。
8. **Staff Review Queue 未实现**：当前 reviewable 仅覆盖“自己的待审核内容”，不等于 Discourse staff 审核队列。
9. **Topic moderation 高级动作缺失**：topic timer、slow mode、split/merge/change owner 等。
10. **Security / Account lifecycle 不完整**：2FA、会话、授权应用、关联账号、导出等。

---

## 2. 审计基准

### 2.1 Discourse 上游

主要以 Discourse 当前主干路由和相关模型/API 为基准：

- `frontend/discourse/app/routes/app-route-map.js`
- `config/routes.rb`
- User Preferences 子路由
- Group 子路由
- Private Messages 子路由
- Review Queue / Reviewables
- Bookmark / notification / tracking 等核心能力

上游仓库：<https://github.com/discourse/discourse>

### 2.2 linux.do

linux.do 并不只是“原版 Discourse”。它还包含主题组件、插件和站点定制行为，因此 FluxDO 的最终兼容目标必须同时覆盖：

- Discourse Core
- 官方插件/常见插件
- linux.do 定制插件和主题交互
- 未知插件的安全 fallback

站点：<https://linux.do/>

### 2.3 FluxDO 当前实现证据

当前主分支已经将 Discourse API 拆分为多个 mixin，例如：

- `lib/services/discourse/_chat.dart`
- `lib/services/discourse/_drafts.dart`
- `lib/services/discourse/_groups.dart`
- `lib/services/discourse/_notifications.dart`
- `lib/services/discourse/_reviewables.dart`
- `lib/services/discourse/_revisions.dart`
- `lib/services/discourse/_search.dart`
- `lib/services/discourse/_topics.dart`
- `lib/services/discourse/_users.dart`
- `lib/services/discourse/_voting.dart`

这套结构已经足够支持继续做 capability parity，不建议推翻重写。

---

## 3. 状态定义

| 标记 | 含义 |
| --- | --- |
| ✅ | 已有完整或接近日常完整的原生实现 |
| 🟡 | 已实现主要路径，但缺少 Discourse 子状态、动作或边界行为 |
| 🟠 | 能显示/部分适配，但架构仍容易被插件或站点定制击穿 |
| ❌ | 当前未发现对应完整实现 |
| STAFF | 仅对 staff/moderator/admin 有意义，应按 capability 动态显示 |

---

## 4. 功能矩阵

### 4.1 浏览 / 内容消费

| 功能 | 状态 | 备注 |
| --- | --- | --- |
| Latest / Top / Categories / Tags | ✅ | 已是成熟主链路 |
| Topic 阅读 | ✅ | 已支持复杂渲染与多种媒体 |
| 搜索 | ✅ | 已有独立 Discourse service |
| 浏览历史 / Read | ✅/🟡 | 已有用户侧入口；需继续核对与上游 Read activity 的语义一致性 |
| Onebox | ✅/🟠 | 已有专用实现，但第三方插件 onebox 仍需 fallback |
| `discourse-local-date` 动态交互 | 🟠 | 静态渲染不能等价于网页中的时区交互 |
| 未知 Cooked HTML 插件节点 | 🟠 | 需要统一 extension registry + Web fallback |

### 4.2 发帖 / Composer

| 功能 | 状态 | 备注 |
| --- | --- | --- |
| 新建主题 / 回复 / 编辑 | ✅ | 主链路完整 |
| Draft | ✅ | 已有本地/服务端草稿体系 |
| 上传 | ✅ | 已有独立 upload service |
| Rich composer | ✅/🟡 | 已支持，继续关注与 Discourse markdown/cooked 行为差异 |
| Composer 实时渲染设置 | ✅ | 2026-09-02 已清除重复设置项 |
| 插件提供的 composer 扩展 | 🟠 | 目前仍依赖专项适配 |

### 4.3 书签

| 功能 | 状态 | 备注 |
| --- | --- | --- |
| Bookmark / Unbookmark | ✅ | 基础已完成 |
| Bookmark list | ✅ | 已有书签页 |
| Bookmark name | ❌/待核对 | 应跟上游模型统一 |
| Reminder time | ❌ | Discourse 原生重要能力 |
| Reminder presets | ❌ | later today / tomorrow / next week / custom |
| Reminder notification | ❌ | 需要接通知链路 |
| Bookmark reminders activity | ❌ | 上游有独立用户活动入口 |

### 4.4 私信 PM

FluxDO 当前 `PrivateMessagesPage` 已实现 Inbox / Sent / Archive、新建私信、多选和批量归档，因此“私信功能缺失”不能再作为大类描述。

| 功能 | 状态 | 备注 |
| --- | --- | --- |
| Inbox | ✅ | 已完成 |
| Sent | ✅ | 已完成 |
| Archive | ✅ | 已完成 |
| New PM | ✅ | 已完成 |
| 批量归档 | ✅ | 2026-09-02 已完成 |
| Unread mailbox | ❌ | Discourse 有独立路由 |
| Warnings | ❌ | 按服务端 capability/用户状态展示 |
| Group PM inbox | ❌ | 应进入群组/私信统一模型 |
| Group PM archive | ❌ | 同上 |
| PM Tags | ❌ | Discourse 支持 message tags |

### 4.5 Chat

| 功能 | 状态 | 备注 |
| --- | --- | --- |
| 频道 / 直接消息 | ✅ | 已有完整专用 service 和 UI |
| Realtime | ✅/🟡 | 已有 MessageBus / presence；继续修状态一致性 |
| Read state | 🟡 | 仍应持续对标 Discourse 的已读语义和批量 timing 行为 |
| Plugin-specific chat extensions | 🟠 | 使用 capability / adapter 扩展 |

### 4.6 Notifications

`_notifications.dart` 已经正确区分 recent 与历史分页，并处理 `filter_by_types`、read/unread、单条/全部标记已读。这里不建议重写 API 层。

| 功能 | 状态 | 备注 |
| --- | --- | --- |
| Recent notifications | ✅ | 已完成 |
| History pagination | ✅ | 已完成 |
| Read / unread | ✅ | 已完成 |
| Mark one/all read | ✅ | 已完成 |
| Responses / Likes / Mentions / Edits / Links UI parity | 🟡 | 重点是 UI / filter 对齐 |
| Plugin notification actions/icons | 🟠 | 需要 adapter registry |

### 4.7 User Activity

| 功能 | 状态 | 备注 |
| --- | --- | --- |
| Topics | ✅ | 已有 |
| Replies | 🟡 | 核对是否作为完整独立 activity 入口 |
| Likes Given | ❌ | 上游独立 activity |
| Bookmarks | ✅ | 已有 |
| Bookmarks with reminders | ❌ | 依赖 Bookmark Reminder |
| Drafts | ✅ | 已有 |
| Pending | ✅ | 已有“自己的待审核内容” |
| Read | ✅/🟡 | 需与上游 activity 语义核对 |
| Deleted Posts | ❌ | 按权限显示 |
| Badges | ✅ | 已有 |

### 4.8 服务端个人设置

这是目前最大的普通用户功能缺口。

FluxDO 现有 `lib/settings/definitions/*` 主要是 App 本地设置；不能把它等价为 Discourse Preferences。

建议新增独立的“社区账户设置”，并明确与“FluxDO 设置”分开。

| Discourse Preferences | 状态 | 目标 |
| --- | --- | --- |
| Account | ❌/🟡 | 邮箱、姓名、title、primary group、flair 等 |
| Security | ❌ | 密码、2FA、security key、sessions |
| Profile | 🟡 | about/location/site/timezone/background/featured topic 等 |
| Emails | ❌ | 邮件摘要、mailing list mode 等 |
| Notifications | 🟡 | 服务端通知偏好，不等于本地通知开关 |
| Tracking | ❌ | watching/tracking/muted topics/categories/tags |
| Users | ❌ | ignored / muted users |
| Tags | ❌ | watched/tracked/muted tags |
| Interface | 🟡 | 服务端 theme/language/default homepage 等 |
| Apps | ❌ | 已授权应用 |
| Navigation menu | ❌ | sidebar sections/categories/tags preferences |
| Calendar subscriptions | ❌ | 如站点启用则展示 |
| Second factor | ❌ | TOTP / security keys 等 |

#### 关键原则

- `blockedUsernames` 等本地功能可以保留，但必须明确标记为“仅 FluxDO 本地过滤”。
- Discourse Ignore/Mute 必须实现为服务端设置，保证与网页和其他客户端同步。
- App 设置与社区账户设置不得继续混成一个概念。

### 4.9 Tracking / Notification Level

应建立统一 notification level 模型，而不是在不同页面重复实现。

需要覆盖：

- Topic: regular / tracking / watching / muted
- Category: regular / tracking / watching / watching first post / muted
- Tag: regular / tracking / watching / watching first post / muted
- User: muted / ignored

验收要求：网页修改后 FluxDO 能读到；FluxDO 修改后网页能立即反映。

### 4.10 Groups

当前 `_groups.dart` 已实现目录、详情、成员、自助 join/leave、手工加成员。基础方向正确。

| 功能 | 状态 | 备注 |
| --- | --- | --- |
| Directory | ✅ | 已完成 |
| Detail | ✅ | 已完成 |
| Members | ✅ | 已完成 |
| Join / Leave | ✅ | 已按 serializer capability |
| Add member | ✅ | 已完成 |
| Membership requests | ❌ | 高优先级 |
| Activity: topics | 🟡 | 补独立完整入口 |
| Activity: posts | 🟡 | 补独立完整入口 |
| Activity: mentions | ❌ | 上游有独立入口 |
| Group messages inbox/archive | ❌ | 高优先级 |
| Manage profile | ❌ | owner/admin |
| Manage membership | ❌ | owner/admin |
| Manage interaction | ❌ | owner/admin |
| Manage email | ❌ | owner/admin |
| Manage categories/tags | ❌ | owner/admin |
| Group logs | ❌ | owner/admin |
| Permissions | ❌/🟡 | 根据 serializer/guardian 展示 |

### 4.11 Solved

当前主分支未发现完整 Accepted Answer 链路。

需要覆盖：

- `topic.has_accepted_answer`
- `post.accepted_answer`
- `can_accept_answer`
- Accept / Unaccept
- Accepted answer jump
- Solved filter
- Solved notification
- Cooked marker rendering

注意：不能只把绿色勾渲染出来；写操作、过滤和通知必须一起完成。

### 4.12 Topic moderation / 高级动作

普通用户不需要默认看到，按 serializer / guardian capability 动态展示。

| 功能 | 状态 |
| --- | --- |
| Close / Reopen | 🟡/待核对 |
| Pin / Unpin | 🟡/待核对 |
| Global pin | ❌/待核对 |
| Topic timer / auto close | ❌ |
| Slow Mode | ❌ |
| Banner | ❌/待核对 |
| Move posts | ❌/待核对 |
| Split topic | ❌ |
| Merge topic | ❌ |
| Change owner | ❌ |
| Staff timestamp/bump operations | ❌ |

### 4.13 Review Queue

当前 `lib/services/discourse/_reviewables.dart` 的注释已经明确：**仅覆盖“自己的待审内容”视角**。

已完成：

- 获取当前用户 pending posts
- 用户撤回自己的 pending reviewable

尚未实现 STAFF Review Queue：

- Flags
- Queued Posts
- Users needing review
- Reviewable types
- filters / score / history
- approve / reject / ignore 等 actions
- suspend / silence 等 staff 用户动作

因此 UI 命名应严格区分：

- `我的待审核内容`
- `审核队列`（STAFF）

### 4.14 Security / Account Lifecycle

| 功能 | 状态 |
| --- | --- |
| Change email | ❌ |
| Change password | ❌ |
| TOTP 2FA | ❌ |
| Security Key / WebAuthn | ❌ |
| Login sessions list | ❌ |
| Revoke session | ❌ |
| Associated accounts | ❌ |
| Authorized Apps | ❌ |
| Data Export | ❌ |
| Deactivate / Delete account | ❌，后置高风险 |
| Custom Status | ❌ |

---

## 5. 插件兼容：必须从专项适配升级为扩展架构

### 5.1 当前问题

Discourse 的帖子内容不是“只有 HTML”。Core、插件、主题组件会通过 class、`data-*`、decorator、plugin outlet 和 JS 行为给 Cooked HTML 增加交互。

Flutter 原生 renderer 如果只解析视觉结构，会出现：

- 内容看起来正常，但按钮不可操作；
- 动态时间只能显示一个静态值；
- 插件插入的 post action 消失；
- 新插件上线后必须等 FluxDO 发版才能使用；
- 未识别节点静默降级，用户不知道功能已经丢失。

### 5.2 建议架构

建议引入类似：

```text
DiscourseContentExtensionRegistry
  ├─ Core adapters
  │   ├─ discourse-local-date
  │   ├─ details
  │   ├─ spoiler
  │   ├─ onebox
  │   ├─ lightbox
  │   ├─ poll
  │   └─ ...
  ├─ Plugin adapters
  │   ├─ solved
  │   ├─ topic-voting
  │   ├─ calendar/event
  │   └─ linux.do-specific
  └─ Unknown interactive node
      └─ Web fragment / open-in-web fallback
```

### 5.3 最低兼容原则

1. 已知核心节点：原生 Flutter 渲染 + 原生操作。
2. 已知插件节点：通过 adapter 注册，不污染主 renderer。
3. 未知但明显可交互节点：**禁止静默退化为纯文本**。
4. 无法原生兼容时：给出“网页交互”fallback。
5. 插件 adapter 应可通过 capability / site settings 判定是否加载。

---

## 6. 不应重复投入的大模块

以下模块已跨过“功能缺失”阶段，后续应以 bugfix、一致性、性能和边界行为为主：

- 话题基础浏览
- 分类 / 标签浏览
- 搜索
- 普通发帖 / 回复 / 编辑
- Draft
- 上传
- Chat 主架构
- 通知 API 主架构
- Topic Voting
- 普通 PM Inbox/Sent/Archive
- PM 批量归档
- 群组目录 / 详情 / 成员 / join/leave
- 徽章

---

## 7. 推荐实施顺序

### P0 — 普通用户替代网页版的关键阻塞

1. 服务端 User Preferences 基础框架
2. Tracking + muted/ignored users
3. Bookmark Reminder
4. Content Extension Registry + unknown interactive fallback
5. Solved 完整链路

### P1 — 高频长尾能力

6. PM unread / group inbox / group archive / PM tags / warnings
7. User Activity：likes given / bookmark reminders / deleted posts / replies parity
8. Groups：requests / activity / mentions / group messages
9. Custom Status + Profile advanced fields
10. Notification 子分类和 plugin notification adapter

### P2 — 高级用户 / staff

11. Topic timer / slow mode / split / merge / change owner 等 moderation
12. Staff Review Queue
13. Security / 2FA / sessions / associated accounts / apps
14. Group owner/admin 全管理页
15. linux.do 专属插件 adapter 持续维护

---

## 8. Definition of Done

一个功能不能因为“页面能打开”就标记完成。建议 parity 项至少满足：

- [ ] API：读取接口完整
- [ ] API：写操作完整（如该功能允许写）
- [ ] Model：字段没有静默丢失关键状态
- [ ] UI：读状态正确
- [ ] UI：操作入口按 capability 显示
- [ ] Realtime/cache：操作后状态能及时一致
- [ ] Error：403/404/409 等能给出合理反馈
- [ ] Multi-account：状态不会串账号
- [ ] linux.do：至少完成一次真实站点验证
- [ ] Web parity：FluxDO 修改后网页可见，网页修改后 FluxDO 可见（服务端设置类功能）
- [ ] Regression：不破坏非 linux.do 的标准 Discourse 实例

---

## 9. 持续审计建议

建议以后每次 Discourse stable 大版本或 linux.do 上线明显新插件时更新本文件，并维护一张 capability matrix：

| Feature | Core/Plugin | API | Model | Read UI | Write UI | Realtime | linux.do tested |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Bookmark Reminder | Core | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| PM Archive | Core | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| PM Unread | Core | ? | ? | ❌ | — | ? | ❌ |
| Group Join | Core | ✅ | ✅ | ✅ | ✅ | — | ✅ |
| Solved | Plugin | ❌ | ❌ | 🟡 | ❌ | ❌ | ❌ |
| Topic Voting | Plugin | ✅ | ✅ | ✅ | ✅ | ? | ✅ |
| Local Date interaction | Core markup | — | 🟡 | 🟡 | ❌ | — | ❌ |
| Review Queue | Core/STAFF | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

本报告负责解释“为什么做”和“缺在哪里”；具体可执行事项维护在仓库根目录 [`TODO.md`](../TODO.md)。
