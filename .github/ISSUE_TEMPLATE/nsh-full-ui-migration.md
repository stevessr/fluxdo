---
name: "NSH 全量 UI 迁移 Epic"
about: "追踪 Fluxdo 全部界面由 Flutter 逐步迁移为 Native Shell"
title: "[Epic] Fluxdo 全部 UI 逐步完整迁移至 Native Shell (NSH)"
labels: ""
assignees: ""
---

# 目标

逐步将 Fluxdo **全部用户可见 UI、导航、组件和交互**由 Flutter 重写为 [Native Shell (NSH)](https://nsh.dev/)，以独立 NSH 客户端作为最终正式入口，而不是只完成首页 Demo 或仅套用视觉样式。

- 长期迁移分支：[migration/nsh-full-ui](https://github.com/stevessr/fluxdo/tree/migration/nsh-full-ui)（与稳定 main 隔离）
- 已有只读原型：[#138](https://github.com/stevessr/fluxdo/pull/138)，用于技术参考，**尚未通过 NSH CLI 和真机验证**
- 迁移规范：[docs/nsh-full-ui-migration.md](https://github.com/stevessr/fluxdo/blob/migration/nsh-full-ui/docs/nsh-full-ui-migration.md)
- 基线核销清单：[docs/nsh-ui-inventory.md](https://github.com/stevessr/fluxdo/blob/migration/nsh-full-ui/docs/nsh-ui-inventory.md)

## 基本原则

- 保证功能等价、跨平台可安装、可回退；每完成一项提供代码链接/测试记录。
- 开发过程中保持原 Flutter 正式应用和 CI 正常；**未验证前不删除原 UI**。
- 完整替换全部 UI 为最终目标，Flutter ↔ NSH 的 PlatformView/混合嵌入只允许作为过渡。
- 保留已验证的服务端协议语义、账户/凭据保护、Rust 网络核心与站点扩展行为；JS 与第三方插件不得直接读写秘密。
- 持续吸收 main 的必要安全和功能更新，不让长期分支落后生产功能。

## P0 — 框架与架构可行性

- [ ] NSH 官方 CLI、类型检查、trace、至少一个真机/桌面目标的编译运行；列出 API、平台能力差距。
- [ ] 建立 nsh 应用入口、路由与生命周期、设计 token、资源、l10n、异常态、CI/ Nightly 独立产物。
- [ ] Rust/Native Host Services 和 NSH TSX 之间的版本化类型协议；登录/网络/缓存/插件/媒体/窗口/存储的能力边界。
- [ ] 备份/迁移现有本地数据、账户切换语义、安全存储/授权回调机制；禁止 WebView/插件绕过安全边界。
- [ ] 首屏耗时、列表滚动、内存峰值、图像缓存、网络开销和电量基准。
- [ ] 审核现有 Flutter 页面/部件目录，登记漏项及依赖关系；明确每个文件的迁移去向。

## P1 — Shell、阅读链路与导航

- [ ] Splash/Onboarding/登录/账号管理/全局导航/深链/路由、主题、i18n、键盘/触摸/可访问性。
- [ ] 最新/热门/分类/标签/看板/搜索/过滤/无限列表/刷新/缓存/滚动位置恢复。
- [ ] 话题详情、帖子树与楼层跳转、富文本、表情、代码块、图文音视频、投票、徽章、阅读进度和快捷操作。
- [ ] 桌面/平板双栏平行视界、窄屏投影返回、历史状态保留、系统预测式返回。
- [ ] 用真实可信的业务 Host Service 替换 #138 中匿名只读 API 原型。

## P2 — 写入和社区

- [ ] 新话题/回复/编辑、Markdown 编辑器、草稿与本地恢复、上传/长图/预览/引用/@提及/表情。
- [ ] 全局搜索和复杂过滤、通知与私信、书签/关注/历史/稍后读、邀请。
- [ ] 个人主页/设置/等级/徽章/排行榜/群组/成员、用户资料编辑。
- [ ] 举报、审核、标签/分类/帖子/话题的权限管理、看板管理。

## P3 — Chat、扩展和复杂交互

- [ ] 实时 Chat：频道/私信/群组、多账户、搜索、回复、附件、已读、静音、头像粘滞/合并。
- [ ] MessageBus/SSE/WS、断线重连、增量更新、后台恢复与消息状态；不支持的 NSH API 由受控 Host 实现。
- [ ] 内嵌浏览器/OAuth 系统浏览器、扫码和二维码、推送、通知、系统分享。
- [ ] 表情生成器/长图/元宇宙/AI/其他模块的全部独立页面与弹窗。
- [ ] 现有 SitePlugin、插件 UI、动态安装、签名/授权/隔离/版本兼容与回滚机制。

## P4 — 设置、平台与系统集成

- [ ] 外观/网络/代理/VPN/下载/通知/隐私/缓存/诊断/日志/更新/关于等全部设置界面。
- [ ] Android/iOS 原生权限、系统返回/预测返回、摄像头、文件/分享/通知和生命周期。
- [ ] Linux Wayland 优先：GTK、IME、剪贴板、文件选择、拖放、桌面窗口/托盘；补齐 Windows/macOS 同等能力。
- [ ] 检查 Web 目标与插件分发适配，记录原有平台支持和新端能力差异。

## P5 — 验收与 Flutter UI 退役

- [ ] 对 [完整 UI 源文件清单](https://github.com/stevessr/fluxdo/blob/migration/nsh-full-ui/docs/nsh-ui-inventory.md) 和所有运行时动态入口逐项核销，无未迁移页面或未说明的弃用功能。
- [ ] 跨平台构建、登录/多账号、上传/草稿/Chat/插件及端到端回归全通过；弱网、离线、重连、后台恢复及无障碍测试。
- [ ] 达到或优于 Flutter 基线（偏离须有书面解释），解决崩溃、内存泄漏、数据丢失和安全问题。
- [ ] 完成版本升级/数据迁移/安装包签名/Nightly/正式发布/回滚路径验收。
- [ ] 确认 NSH 成为正式默认 UI 后，分批移除不再使用的 Flutter UI/依赖/工作流；合并并关闭本 Epic。

## Definition of Done

每个迁移单元须标明对应旧 UI、NSH 文件/PR、业务行为差异、平台支持、测试记录（至少基础交互+异常态+恢复）、无障碍、性能回归及安全检查。只有全部迁移范围和正式发行通过才允许关闭本 Issue。

> 本模板被保存在仓库，因为创建时 GitHub API 返回 410：该仓库当前已禁用 Issues。待仓库在 Settings → General → Features 中开启 Issues 后，使用本模板创建主追踪 Issue。
