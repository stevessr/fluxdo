# HTTPS advanced transport: implementation and contracts

Fluxdo uses a **dynamic** Dio adapter chain, not one universal HTTP client. Features must be advertised by the active native transport; do not add a global `Accept-Encoding: br, zstd` header unless every fallback can decode those representations.

| Transport | HTTP/2 | HTTP/3 | Compression handling | Caveat |
| --- | --- | --- | --- | --- |
| Android Cronet | enabled | QUIC enabled, negotiated via Alt-Svc | native gzip/Brotli (`enableBrotli: true`) | Enabled is not equal to negotiated |
| rhttp (opt-in) | reqwest ALPN | probe after a valid H3 Alt-Svc hint, with failure backoff | delegated to the compiled Rust client | Never force br/zstd from Dart without verifying Rust features |
| Apple URLSession | platform-managed | platform-managed when available | URLSession-managed | Cookie auto-management disabled to avoid two jars |
| Dart IO / local proxy | HTTP/1.1 to the next hop | no H3 at the Dart IO hop | gzip auto-uncompression | An upstream proxy may use a different HTTP version |
| WebView fallback | browser-managed | browser-managed | browser-managed | Only eligible same-origin requests |

## HTTPS security

- HSTS is learned from authenticated HTTPS responses, scoped by host with optional `includeSubDomains`, and capped at two years / 128 entries. The application-wide policy is persisted in bounded SharedPreferences storage (five-second coalesced writes and pre-request restoration), while standalone policy instances remain memory-only by default. There is no bundled HSTS preload list. Invalid directives and cleartext responses cannot add policies.
- HSTS upgrades happen before CSRF/cookie/cache/scheduling interceptors. The localhost HTTP hop used by the application's own gateway is a transport implementation detail, **not** an HTTPS origin downgrade.
- HTTPS-to-HTTP redirects are rejected unless the target is upgraded under a previously learned HSTS policy.
- Redirects support 301/302/303/307/308, preserving the body for same-origin 307/308 with replayable payloads; streaming bodies and cross-origin body replays are rejected rather than silently duplicated.
- Cross-origin redirects copy only safe request headers and a small set of known control flags. Cached validators (including same-origin redirect validators), auth copying intent, and session-private metadata are discarded; destination cookies must be selected independently.
- Cloudflare `103 Early Hints` is informational, never an API success response. The existing recovery fallback remains in place.

## QUIC discovery and diagnostics

The rhttp path must observe an authenticated HTTPS origin `Alt-Svc: h3=":443"; ma=...` on a normal request **before** attempting a subsequent QUIC request. H3 discovery is keyed by HTTPS host+port and only accepts same-port alternatives; other-host or alternate-port endpoints cannot safely be attempted by the existing rhttp configuration. Unadvertised hosts use HTTP/2 or HTTP/1.1 normally. A connection failure triggers a ten-minute backoff; a successful negotiated H3 session is remembered for up to one hour. `Alt-Svc: clear` and `ma=0` revoke the advertisement.

The JSONL network log records `httpVersion` only when the adapter actually supplies the negotiated protocol (currently rhttp), separately from `http3Advertised`, which only reflects a response hint. When unknown, no negotiated protocol is asserted. Raw certificate contents, headers, token values and remote IPs are not added to this log.

## Verification

```sh
flutter pub get
dart run tool/gen_l10n.dart
flutter analyze lib/services/network test/services/network
flutter test test/services/network
```

The PR-specific `.github/workflows/https-advanced-network.yml` runs focused analysis, protocol/security tests and network regressions. Browser TLS fingerprint, ECH, and compression features should be tested on a real device/network per adapter. HTTP/3 support cannot be demonstrated by a successful HTTP/2 response that merely contains Alt-Svc.
