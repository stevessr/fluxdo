# Fluxdo / Cloudflare 后量子 TLS

## 协商协议

Cloudflare 边缘 TLS 1.3 推荐混合密钥交换 `X25519MLKEM768`（TLS NamedGroup `0x11ec`）。旧的 `X25519Kyber768Draft00` 已过时。该功能保护**密钥交换**免受“现在记录、未来解密”风险；不代表现有证书签名也具备后量子安全性。

## 本次接入范围

Fluxdo 使用多个独立 TLS 网络栈，各自的协商行为不同：

| 路径 | TLS 栈 | 2026 年升级范围 |
| --- | --- | --- |
| DoH Gateway / MITM 至外部 HTTPS 站点 | `core/doh_proxy` Rust rustls + AWS-LC | 默认启用 `pqc`，优先 X25519MLKEM768，X25519 回退 |
| DoH 纯 CONNECT 隧道 | 最终客户端 TLS 实现 | 本地代理只转发字节，不替客户端选择 TLS 密钥交换 |
| rhttp 请求（Rust reqwest/rustls） | 外部 `Lingyan000/rhttp_plus` 依赖 | 当前仅配置 ECH，尚需上游显式启用、验证 `prefer-post-quantum` |
| Android 原生请求 | Cronet/BoringSSL | 取决于实际 Cronet 提供者、版本和协商；不继承子模块配置 |
| iOS/macOS 原生请求 | URLSession/系统 TLS | 取决于系统版本及系统 TLS 能力 |
| Windows/Linux Dart IO、WebView | Dart VM TLS、平台 WebView | 取决于运行时版本和对应浏览器/系统 TLS |

**不要**仅凭 Cloudflare 服务端支持或启用了 ECH、HTTP/3，就将所有连接标记为“后量子安全”。

## 实际开启的路径

在网络设置中启用 DoH，并使用由 `fluxdo_doh` 发起远端 TLS 的 Gateway/MITM 模式。对于直接通过 rhttp/Cronet/URLSession/WebView 发起的请求，本次子模块更新不改变其 TLS 提供者。启用用户代理或外部 HTTPS 检查代理时，还须分别验证其 TLS 路径。

## 验证与兼容性

在子模块目录运行：

```bash
cargo test --locked --lib tls_crypto::tests
cargo test --locked --features ech --lib tls_crypto::tests
cargo test --locked --no-default-features --lib tls_crypto::tests
cargo build --locked --release --features ech
```

以 `RUST_LOG=debug` 观察真实出站 TLS 日志：

- `key_exchange: Some(X25519MLKEM768)`：本条连接协商了后量子混合密钥交换。
- `key_exchange: Some(X25519)`：本条连接为传统密钥交换。
- 日志缺少结果时不能据此认定 PQC 成功；TLS 会话复用与重试需单独排查。

rustls 使用 `X25519MLKEM768` 首选、保留传统 X25519。遇到不支持新组的中间盒可能发生握手异常；不能自动关闭证书校验、不能静默重放非幂等请求。针对跨平台编译，Windows 构建需确保 AWS-LC 的 CMake/NASM 等依赖完整。

## 尚未覆盖

- `rhttp_plus` 上游 Rust TLS 默认与自建 ECH provider 的优先协商设置，需要进一步升级上游依赖，并在五个平台抓包验证。
- HTTP/3/QUIC 的后量子握手须分别验证（`rhttp`、Cronet 使用各自 QUIC TLS 栈）。
- 浏览器 WebView、系统网络 API 与 DoH DNS 自身的所有底层 TLS 会话不保证已协商 PQC。
- Cloudflare 边缘 TLS 目前的后量子证书签名支持与混合密钥交换是两件事。

参考：
- https://developers.cloudflare.com/ssl/post-quantum-cryptography/
- https://developers.cloudflare.com/ssl/post-quantum-cryptography/pqc-support/
