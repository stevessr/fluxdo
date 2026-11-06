# 系统浏览器授权：PR #142 后续验证

## 检查结论

PR #142 已合并，后续修改基于 main 的 a241fc98。原测试覆盖通道配置与授权 URL 校验；Android 的源码字符串检查仅能说明相关代码存在，不能证明 PackageManager 或 Activity 启动行为。

本次将桌面发现逻辑独立为不依赖 Flutter 的 Dart 模块，服务继续调用同一份实现，既有导入与通道 ID 保持兼容。

修复 Linux 发现依赖外部 `which` 的问题：直接按 PATH 检查文件类型、执行位；别名仍按符号链接目标去重。选中的启动入口保存为发现时的绝对路径（包括 Flatpak），避免启动时再次按 PATH 查找。不会将解析后的目标替换启动入口，以保留包装脚本的启动语义。

## 当前环境实际完成

环境：Linux x64、Dart 3.13.1。

- `dart tool/verify_browser_discovery.dart`：23 项行为检查通过。
- `dart analyze lib/services/desktop_browser_discovery.dart tool/verify_browser_discovery.dart`：通过。
- `git diff --check`：通过。
- Linux 真实临时文件：不含 `which` 的 PATH、非可执行文件排除、符号链接去重、独立 Beta 入口、绝对路径启动、带查询参数的 URL 原样传入子进程。
- 注入依赖验证：Linux 稳定/预览通道并存、链接解析失败回退、Flatpak 沙箱不探测宿主、Flatpak 应用过滤与进程异常；macOS 系统/用户 Applications 目录、空格路径参数；Windows 系统/x86/用户安装根目录、大小写重复根目录、Canary SxS、Nightly 备用目录；无候选时保留默认入口。

现有 Flutter 测试已接入同一行为检查入口。尝试运行 `flutter pub get`，本机 Flutter 3.47.1 在准备 Gradle Wrapper 时因 tar 无法设置归属 UID 而失败；且此 SDK 低于项目要求的 3.47.4。本机未完成 Flutter 单元测试、完整应用构建或 Android 原生测试，不把独立 Dart 检查计作这些项目通过。

## CI 验证入口

`.github/workflows/system-browser-auth.yaml` 新增 Ubuntu、macOS、Windows 三系统 Dart 行为测试；macOS、Windows 分支分别创建真实临时应用包/安装文件验证文件系统访问。原 Flutter 3.47.5 分析与测试任务继续保留。实际运行状态以本次 PR 的 Checks 为准。

测试不启动真实浏览器，不发出真实授权请求，不读取浏览器 Cookie。Linux 启动的是临时脚本；Windows 临时 exe 仅用于文件发现。

## 仍需真实安装与交互验证

| 系统 | 尚待验证的项目 |
| --- | --- |
| Android | API 30–32 与 API 33+ 的 PackageManager 分支；同时安装 Chrome/Edge Stable、Beta、Dev、Canary 和 Firefox Stable、Beta、Nightly；通道标签与实际包名一致；非默认通道仍可发现；禁用/卸载后的列表与启动结果；HTTP、HTTPS 分别声明的过滤器；仅深链、非 exported Activity 不作为浏览器；最终授权链接只交给所选包。源码字符串测试不能替代上述行为验证。 |
| Linux 桌面 | 各发行版真实通道包装脚本、现有浏览器进程复用与 Profile；Wayland/niri 下前台打开；Snap/自定义安装入口；安装后卸载的错误反馈。 |
| Flatpak | 实际沙箱中 Portal 的宿主浏览器列表、选择/取消、缺少 Portal 时的反馈；返回请求句柄仅表示提交成功，不等于授权完成。 |
| macOS | 真实 `.app` 名称、系统与用户目录、`open -a` 打开指定通道并复用 Profile；签名与系统提示；自定义安装位置不在当前扫描范围。 |
| Windows | 各安装器的真实 Stable/Beta/Dev/Canary/ESR 目录；用户/系统/x86 安装；已有进程复用；Firefox Beta/ESR 若使用标准 Mozilla Firefox 目录，当前按路径显示为 Firefox，需实际安装确认。注册表和自定义安装目录不在当前扫描范围。 |
| 各端完整登录 | 用有现成 Google/GitHub 会话的指定通道打开授权页，确认不跳到另一通道；授权后 `discourse://auth_redirect` 返回正确账户；取消、重复回调及浏览器已卸载时正确反馈。 |

iOS 未扩展 TestFlight 通道，继续依赖已公开 URL scheme；不把桌面与 Android 预览版支持推广为 iOS 验证结果。

## XDG 补充（本次提交）

Linux 在 PATH 回退前扫描 `$XDG_DATA_HOME/applications`（默认 `~/.local/share/applications`）和 `$XDG_DATA_DIRS/applications`（默认 `/usr/local/share:/usr/share`）。支持递归 desktop ID、用户覆盖与 Hidden 墓碑、本地化名称、OnlyShowIn/NotShowIn、TryExec、双协议 MIME 处理器、文件链接及独立 Profile。NoDisplay 不排除合法 MIME 处理器；终端入口和客户端自身被排除。相对 XDG 路径被忽略。

使用所选文件的绝对路径调用 `gio launch`，不通过 shell、不调用默认浏览器、不自行展开 Exec。GIO 负责字段码、包装程序参数、工作目录及 D-Bus 激活；服务检查 GIO 退出码。缺少 GIO 时继续 PATH/Flatpak 回退；Flatpak 沙箱仍仅走 Portal。XDG 与同入口的 PATH 回退去重，不合并不同 desktop ID 的 Profile，已由 XDG 发现的 Flatpak ID 不重复列出。

本地通过原 23 项行为检查与新增 24 项 XDG 检查；本地没有 GIO，真实 `gio launch` 集成验证交由 Linux CI（明确要求 GIO 存在）。集成测试仅启动临时脚本，检查带空格参数、`%U` 展开及授权 URL 原文。Flutter 单元测试额外验证 GIO 启动成功、非零退出、入口消失和非法 URL 拒绝。

规范依据：[Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry/latest/)，特别是 Desktop File ID、Recognized Keys 与 Exec 字段。
