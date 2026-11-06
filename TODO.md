# FluxDO TODO

> 维护目标：持续对齐 Discourse，并优先保证 linux.do 日常使用体验。  
> 深度审计报告：[`docs/discourse-linuxdo-feature-gap.md`](docs/discourse-linuxdo-feature-gap.md)

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

### Tracking / Mute / Ignore

- [ ] 建立统一 `NotificationLevel` / tracking model
- [ ] Topic：regular / tracking / watching / muted
- [ ] Category：regular / tracking / watching / watching first post / muted
- [ ] Tag：regular / tracking / watching / watching first post / muted
- [ ] User：服务端 muted users
- [ ] User：服务端 ignored users
- [ ] 保留现有本地 `blockedUsernames` 时明确标记“仅本机过滤”
- [ ] 从话题、分类、标签和用户页提供一致的状态切换入口
- [ ] 验收跨 Web / FluxDO / 多账号同步

### Bookmark Reminder

- [ ] 补齐 bookmark model：name / reminder timestamp / reminder type 等上游字段
- [ ] 新建/编辑书签时支持 reminder presets
- [ ] 支持自定义 reminder 时间
- [ ] 支持清除/重设 reminder
- [ ] 通知跳转到对应书签位置
- [ ] “我的活动”增加 Bookmarks with reminders
- [ ] 验证 timezone 和 DST 行为

### Content Extension Registry

- [ ] 抽象 `DiscourseContentExtensionRegistry`
- [ ] 将核心 interactive cooked node 从主 renderer 中逐步注册化
- [ ] 为 `discourse-local-date` 增加完整时区交互
- [ ] 为插件 adapter 提供 capability/site-setting 判定
- [ ] 检测未知但明显可交互的 cooked node
- [ ] 未知交互节点禁止静默退化为纯文本
- [ ] 增加 web fragment / open-in-web fallback
- [ ] 添加 adapter 单元测试和 fixture

### Solved / Accepted Answer

- [ ] 解析 topic solved 状态
- [ ] 解析 post accepted answer 状态
- [ ] 解析 `can_accept_answer`
- [ ] Accept answer
- [ ] Unaccept answer
- [ ] 跳转 Accepted Answer
- [ ] Solved 主题过滤
- [ ] Solved 通知适配
- [ ] Cooked marker 原生渲染

---

## P1 — 高频长尾能力

### Private Messages

- [x] Inbox
- [x] Sent
- [x] Archive
- [x] New PM
- [x] 多选批量归档
- [ ] Unread mailbox
- [ ] Warnings mailbox（仅有权限/状态时显示）
- [ ] Group PM inbox
- [ ] Group PM archive
- [ ] PM Tags
- [ ] PM 搜索/过滤与网页语义核对

### User Activity

- [x] Topics
- [ ] Replies：确认并补齐独立完整 activity 入口
- [ ] Likes Given
- [x] Bookmarks
- [ ] Bookmarks with reminders
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
- [x] Add member
- [ ] Membership requests
- [ ] Activity / Topics
- [ ] Activity / Posts
- [ ] Activity / Mentions
- [ ] Group messages inbox
- [ ] Group messages archive
- [ ] Permissions view
- [ ] Owner/Admin：Manage profile
- [ ] Owner/Admin：Manage membership
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
- [ ] User Card Background
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
- [ ] Topic Voting 持续回归测试（当前已有实现）
- [ ] Solved adapter
- [ ] Calendar / Event adapter（站点启用时）
- [ ] `discourse-local-date` adapter
- [ ] linux.do 新插件上线时记录其 API / cooked markup / post-menu 扩展
- [ ] linux.do 专属插件优先走 adapter，不在通用 renderer 写站点硬编码
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
- [x] 普通 PM Inbox / Sent / Archive
- [x] PM 批量归档
- [x] 群组目录 / 详情 / 成员 / Join / Leave
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

