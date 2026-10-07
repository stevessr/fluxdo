# LINUX DO 官方 iOS 客户端请求追踪

这组工具用于继续定位官方 iOS 客户端发帖时，设备型号最终位于请求的哪个位置。

当前已经可以确认：

- 官方客户端关键请求走 `ios.linux.do`，而不是普通 `linux.do` 的公开 Discourse 路径。
- 官方客户端是 Swift + Objective-C 原生实现，并使用 App Attest；公开开发记录还提到 mTLS、SSL Pin、HTTP/3 等网络机制。
- 服务端 Post JSON 中的 `via_ios_app` / `ios_device_name` 是响应字段。已验证样例中 `ios_device_name` 为类似 `iPhone 17 Pro Max` 的营销型号名。
- 直接向普通 `/posts.json` 添加 `via_ios_app` / `ios_device_name` 会被忽略，所以不能继续把响应字段名当作请求参数名猜测。

因此这里采用“在加密前观察 URLRequest”的办法，而不是绕 TLS / Pinning：只要官方 App 最终经 Foundation `URLRequest` 发出请求，就能直接看到 query、header 和 body 的真实结构。

## 使用

1. 在一台能够运行官方 App 的**真机**上准备 Frida。优先使用原始 App Store 安装包；重新签名可能改变 App Attest 身份，导致关键请求在发送前就被拒绝。
2. 查询实际 bundle id：

   ```bash
   frida-ps -Uai | grep -i 'LINUX DO'
   ```

3. 启动并注入：

   ```bash
   frida -U -f '<bundle-id>' \
     -l tools/ios-official-reverse/linux_do_ios_request_trace.js \
     --no-pause
   ```

4. 在官方客户端中发一条测试回复。脚本只筛选 `ios.linux.do`，并重点输出：
   - `query.<key>`：URL query 参数；
   - `header.<key>`：HTTP header；
   - `body.<json.path>`：JSON 中的真实层级；
   - `body.<form-key>`：表单字段；
   - `AppAttest generateAssertion`：确认该请求附近是否生成了 App Attest assertion。

脚本默认将 `Cookie`、`Authorization`、CSRF、token、App Attest assertion、key id、signature 等值全部打码，只保留字段名和长度。不要关闭这层脱敏后提交日志到仓库或 PR。

## 如何判定 `ios_device_name` 的真实来源

观察一次官方发帖/回帖请求后按以下顺序判断：

- 如果日志出现 `query.*` / `header.*` / `body.*` 且值为设备营销型号，则该路径就是需要复刻的参数位；接下来再确认这个字段是否被 App Attest 签名覆盖。
- 如果请求中存在另一种设备字段名（例如只含 `device` / `model`），而响应最终变成 `ios_device_name`，说明 `ios_device_name` 只是服务端 serializer 名称，FluxDO 应发送真实的上游字段名。
- 如果完整的发帖请求里完全没有设备型号相关值，但服务端仍返回 `ios_device_name`，则设备型号来自 `ios.linux.do` 网关的已登记设备上下文/认证会话，FluxDO 不应在 `/posts.json` 里添加任何设备型号字段。

这三种结果只有抓到官方客户端请求后才能区分。PR #127 在此之前应继续保持“不向公开 `/posts.json` 注入伪字段”的行为。

## 覆盖范围与限制

脚本 hook `NSURLSession` 和 `NSURLSessionTask.resume`，对 Swift `URLRequest` / Foundation 网络请求有效；它不会绕过 SSL Pin，也不会伪造 App Attest。

如果官方客户端在发帖路径上完全绕过 Foundation、直接使用自定义 QUIC / Network.framework 封装，则需要再从其 request encoder 或 Network.framework 调用点向上追踪。
