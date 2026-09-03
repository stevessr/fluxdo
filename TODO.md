# FluxDO TODO

> 维护目标：持续对齐 Discourse，并优先保证 linux.do 日常使用体验。  
> 深度审计报告：[`docs/discourse-linuxdo-feature-gap.md`](docs/discourse-linuxdo-feature-gap.md)
>
> 说明：本清单以**当前代码事实**为准。发现已有完整实现时应直接勾选并注明，禁止为了“完成 TODO”重复造轮子。

## P0 — 普通用户替代网页版的关键阻塞

### Server-side User Preferences

- [ ] 新增独立“社区账户设置”入口，和 FluxDO 本地设置明确区分
- [ ] 建立 Discourse user preferences model / service，避免页面直接拼 API 字段
- [ ] Account：读取和修改姓名、title、primary group、flair 等服务端字段
- [ ] Profile：about、location、website、timezone、profile background、user card background
- [ ] Emails：摘要、邮件通知、mailing list mode 等站点支持项
- [ ] Notifications：服务端通知偏好，不与本地推送设置混淆
- [ ] Interface：语言、主题/颜色方案、默认首页等站点支持项
- [ ] 根据 `site.json` / current user / serializer capability 隐藏站点未启用功能
- [ ] 验收：网页改设置后 FluxDO 能读到；FluxDO 修改后网页能立即反映

> 当前仍是最明显的 P0：用户资料页“设置”入口仍打开 Discourse WebView。

### Tracking / Mute / Ignore

- [ ] 建立统一 `NotificationLevel` / tracking model
- [x] Topic：regular / tracking / watching / muted（已有 `TopicNotificationLevel` 与话题状态链，继续做一致性回归）
- [ ] Category：regular / tracking / watching / watching first post / muted
- [ ] Tag：regular / tracking / watching / watching first post / muted
- [x] User：服务端 muted users（用户页已有服务端 mute 状态/操作）
- [x] User：服务端 ignored users（用户页已有服务端 ignore 状态/操作）
- [ ] 保留现有本地 `blockedUsernames` 时明确标记“仅本机过滤”
- [ ] 从话题、分类、标签和用户页提供一致的状态切换入口
- [ ] 验收跨 Web / FluxDO / 多账号同步

### Bookmark Reminder

- [x] bookmark model 已包含 name / reminder timestamp；创建/更新 API 已支持 reminder 与 auto-delete preference
- [x] 新建/编辑书签支持 reminder presets（现有 BookmarkEditSheet）
- [x] 支持自定义 reminder 时间
- [x] 支持清除/重设 reminder
- [ ] 通知跳转到对应书签位置专项回归
- [ ] “我的活动”增加 Bookmarks with reminders 独立入口（已有派生 provider，尚需正式 UI）
- [ ] 验证 timezone 和 DST 行为

### Content Extension Registry

- [x] 抽象 `DiscourseContentExtensionRegistry`
- [x] 登记当前 renderer 已原生支持的核心 interactive cooked roots，防止对子控件误判
- [x] `discourse-local-date` 已有原生 builder；不再作为缺失项重复实现
- [ ] 为插件 adapter 提供 capability/site-setting 判定
- [x] 检测未知但明显可交互的 cooked node
- [x] 未知交互节点禁止静默退化为纯文本：转换为明确 warning callout
- [x] 未知交互节点保留可用 URL 时提供“Open interactive content”链接
- [ ] 无直接 URL 的未知插件节点增加“打开当前帖子网页版/片段”的兜底
- [x] runtime transform adapter 注册/撤销 API
- [x] registry revision 纳入短帖/长帖解析 LRU 签名，adapter 变化自动失效缓存
- [x] 短帖与长帖 chunk parser 均接入 registry
- [x] 添加 registry 单元测试
- [ ] 为 linux.do 实际插件建立 fixture/adapters，而不是在通用 renderer 写站点硬编码

### Solved / Accepted Answer

> 重新审计后确认：这不是 P0 缺失模块，核心闭环已经存在。仅保留真正未确认的外围一致性项。

- [x] 解析 topic solved / accepted answer 状态
- [x] 解析 post accepted answer 状态
- [x] 解析 `can_accept_answer` / `can_unaccept_answer`
- [x] Accept answer API + UI
- [x] Unaccept answer API + UI
- [x] Accepted Answer 主楼摘要与精确跳楼
- [x] Accepted Answer 帖子盖章/状态同步
- [x] 用户资料 Solved 列表
- [ ] 话题目录中的 Solved / Unsolved 筛选能力与当前 Discourse 对齐
- [ ] Solved 相关通知类型/icon/action 专项核对

---

## P1 — 高频长尾能力

### Private Messages

- [x] Inbox
- [x] Unread mailbox
- [x] Sent
- [x] Archive
- [x] New PM
- [x] 多选批量归档
- [ ] Warnings mailbox（service 已具备；仅有权限/状态时接 UI）
- [x] Group PM inbox
- [x] Group PM unread
- [x] Group PM new
- [x] Group PM archive
- [ ] PM Tags
- [ ] PM 搜索/过滤与网页语义核对

### User Activity

- [x] Topics
- [x] Replies（资料页已有独立 filter=5）
- [x] Likes Given（资料页已有独立 filter=1）
- [x] Bookmarks
- [ ] Bookmarks with reminders 独立入口
- [x] Drafts
- [x] Pending（自己的待审核内容）
- [ ] Read：核对和 Discourse `/activity/read` 的语义一致性
- [ ] Deleted Posts（按权限显示）
- [x] Badges

### Groups

- [x] Directory
- [x] Detail
- [x] Members
- [x] Public Join / Leave
- [x] Request Membership（支持可选 reason）
- [x] Add member
- [x] Owner/Admin Membership Requests：requesters / reason / requested_at / approve / reject
- [ ] Activity / Topics
- [x] Activity / Posts（`before_post_id` cursor）
- [x] Activity / Mentions（`before_post_id` cursor）
- [x] Group messages inbox
- [x] Group messages unread
- [x] Group messages new
- [x] Group messages archive
- [ ] Permissions view
- [ ] Owner/Admin：Manage profile
- [ ] Owner/Admin：Manage membership（除 requests / add member 外的完整管理项）
- [ ] Owner/Admin：Manage interaction
- [ ] Owner/Admin：Manage email
- [ ] Owner/Admin：Manage categories
- [ ] Owner/Admin：Manage tags
- [ ] Owner/Admin：Logs

### Profile / Status

- [ ] Custom Status 读取
- [ ] Custom Status 设置 / 清除 / 到期时间
- [ ] Featured Topic
- [ ] Profile Header Background
- [ ] User Card Background 编辑
- [ ] Primary Group / Flair 编辑
- [ ] 自定义 user fields 编辑

### Notifications UI parity

- [x] Recent notifications API
- [x] History pagination API
- [x] Read / unread API
- [x] Mark one / all read
- [ ] Responses 子分类完整对齐
- [ ] Likes Received 子分类完整对齐
- [ ] Mentions 子分类完整对齐
- [ ] Edits 子分类完整对齐
- [ ] Links 子分类完整对齐
- [ ] Plugin notification icon/action adapter

---

## P2 — 高级用户 / Moderator / Staff

### Topic moderation

- [ ] 核对并补齐 Close / Reopen
- [ ] 核对并补齐 Pin / Unpin
- [ ] Global Pin
- [ ] Banner
- [ ] Topic Timer / Auto Close
- [ ] Slow Mode
- [ ] Move Posts
- [ ] Split Topic
- [ ] Merge Topic
- [ ] Change Owner
- [ ] Staff timestamp / bump operations
- [ ] 所有入口严格根据 serializer / guardian capability 显示

### Staff Review Queue

> 不与当前“我的待审核内容”混淆。

- [ ] Review Queue service / model
- [ ] Flags
- [ ] Queued Posts
- [ ] Users needing review
- [ ] Reviewable type filters
- [ ] Status filters / history
- [ ] Score / reason / context 展示
- [ ] Approve / Reject / Ignore 等 review actions
- [ ] Suspend / Silence 等 staff user actions（按上游 capability）
- [ ] MessageBus / 刷新一致性

### Security / Account Lifecycle

- [ ] Change Email
- [ ] Change Password
- [ ] TOTP 2FA
- [ ] Security Key / WebAuthn
- [ ] Login Sessions list
- [ ] Revoke Session
- [ ] Associated Accounts
- [ ] Authorized Apps
- [ ] Data Export
- [ ] Calendar Subscriptions（站点启用时）
- [ ] Deactivate Account（后置，高风险）
- [ ] Delete Account（后置，高风险）

---

## linux.do / Plugin Compatibility

- [ ] 建立 `Core / Plugin / linux.do-specific` capability matrix
- [x] Topic Voting：已有完整实现，继续回归测试
- [x] Solved：核心 serializer/API/UI 已实现，不再重复造 adapter
- [ ] Calendar / Event adapter（站点启用时）
- [x] `discourse-local-date`：已有原生 parser/builder
- [ ] linux.do 新插件上线时记录其 API / cooked markup / post-menu 扩展
- [ ] linux.do 专属插件优先走 `DiscourseContentExtensionRegistry` adapter
- [ ] 每次 linux.do 站点插件变化后跑真实账号 smoke test

---

## Parity Infrastructure

- [ ] 为每个 Discourse feature 记录 `API / Model / Read UI / Write UI / Realtime / linux.do tested`
- [ ] 新增 site capability snapshot，方便诊断某实例启用了哪些插件/设置
- [ ] 多账号测试：所有 provider/cache key 必须包含账号/实例维度
- [ ] 所有写操作验证 401 / 403 / 404 / 409 等错误反馈
- [ ] 建立标准 Discourse 测试实例，避免只针对 linux.do 产生硬编码
- [ ] 建立 linux.do 真实环境 smoke checklist
- [ ] Discourse stable 大版本升级时重新审计 route / serializer / plugin API

---

## 已确认无需作为“大功能缺失”重做

这些模块应继续修 bug 和一致性，但不要重复重构主架构：

- [x] 话题基础浏览
- [x] 分类 / 标签基础浏览
- [x] 搜索
- [x] 发帖 / 回复 / 编辑
- [x] Draft
- [x] 上传
- [x] Chat 主架构
- [x] Notifications API 主架构
- [x] Topic Voting
- [x] Solved / Accepted Answer 核心闭环
- [x] `discourse-local-date` 原生渲染
- [x] 普通 PM Inbox / Unread / Sent / Archive
- [x] PM 批量归档
- [x] Group PM Inbox / Unread / New / Archive
- [x] 群组目录 / 详情 / 成员 / Join / Leave / Request Membership
- [x] 群组 Posts / Mentions / Membership Requests 审核
- [x] User Activity Replies / Likes Given
- [x] Badges

---

## 每个 TODO 的完成标准

标记 `[x]` 前至少检查：

- [ ] API 读取完整
- [ ] 写操作完整（如果上游允许写）
- [ ] 关键字段未被 model 静默丢弃
- [ ] UI 状态和网页一致
- [ ] capability/权限控制正确
- [ ] 操作后 cache / realtime 状态一致
- [ ] 多账号不会串状态
- [ ] linux.do 真实验证通过
- [ ] 标准 Discourse 实例回归通过
