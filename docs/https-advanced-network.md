# HTTPS advanced transport: implementation and contracts

Fluxdo uses a **dynamic** Dio adapter chain, not one universal HTTP client. Features must be advertised by the active native transport; do not add a global `Accept-Encoding: br, zstd` header unless every fallback can decode those representations.

| Transport | HTTP/2 | HTTP/3 | Compression handling | Caveat |
| --- | --- | --- | --- | --- |
| Android Cronet | enabled | QUIC enabled, negotiated via Alt-Svc | native gzip/Brotli (`enableBrotli: true`) | Enabled is not equal to negotiated |
| rhttp (opt-in) | reqwest ALPN | probe after a valid H3 Alt-Svc hint, with failure backoff | Rust reqwest gzip, deflate, Brotli and Zstandard features enabled | Decoding is native; do not manually decompress it again |
| Apple URLSession | platform-managed | platform-managed when available | URLSession-managed | Cookie auto-management disabled to avoid two jars |
| Dart IO / local proxy | HTTP/1.1 to the next hop | no H3 at the Dart IO hop | gzip auto-uncompression | An upstream proxy may use a different HTTP version |
| WebView fallback | browser-managed | browser-managed | browser-managed | Only eligible same-origin requests |

The locked `rhttp` dependency resolves to `Lingyan000/rhttp_plus` commit `02eb4114b57c108e76a9ed526b6118bc048b5604`; that commit's `rhttp/rust/Cargo.toml` explicitly enables reqwest features `gzip`, `deflate`, `brotli`, and `zstd`. Runtime tests are still required to ensure target binaries contain that implementation and server responses are decoded correctly.

## HTTPS security

- HSTS is learned from authenticated HTTPS responses, scoped by host with optional `includeSubDomains`, and capped at two years / 128 entries. The application-wide policy is persisted in bounded SharedPreferences storage (five-second coalesced writes and pre-request restoration), while standalone policy instances remain memory-only by default. Corrupt/oversized (over 64 KiB) persisted data is ignored, and no more than 128 hosts are loaded. There is no bundled HSTS preload list. Invalid directives and cleartext responses cannot add policies.
- HSTS upgrades happen before CSRF/cookie/cache/scheduling interceptors. The localhost HTTP hop used by the application's own gateway is a transport implementation detail, **not** an HTTPS origin downgrade.
- HTTPS-to-HTTP redirects are rejected unless the target is upgraded under a previously learned HSTS policy.
- Redirects support 301/302/303/307/308, preserving the body for same-origin 307/308 with replayable payloads; streaming bodies and cross-origin body replays are rejected rather than silently duplicated.
- Cross-origin redirects copy only safe request headers and a small set of known control flags. **They use `dio.fetch(RequestOptions)` rather than `dio.request(Options)`**, preventing `BaseOptions.headers` from restoring original-origin Authorization/Cookie/API-key headers. `Accept-Encoding` is not forwarded: each adapter must renegotiate an encoding it can decode. Cached validators (including same-origin redirect validators), auth copying intent, and session-private metadata are discarded; destination cookies must be selected independently. Foreign-origin redirect hops also set `skipAuthCheck`, `skipSessionStateSync`, `skipCfChallenge` and `noRecovery` so an external 401/403 cannot start a forum-specific session repair or Cloudflare challenge. They also discard internal `requestTag` markers (avoiding preload/CSRF routing), refuse URLs containing userinfo credentials, drop original `If-Range` validators, and remove URL fragments before issuing the next request.
- Cloudflare `103 Early Hints` is informational, never an API success response. The existing recovery fallback remains in place.

## QUIC discovery and diagnostics

The rhttp path must observe an authenticated HTTPS origin `Alt-Svc: h3=":443"; ma=...` on a normal request **before** attempting a subsequent QUIC request. H3 discovery is keyed by HTTPS host+port and only accepts same-port alternatives; other-host or alternate-port endpoints cannot safely be attempted by the existing rhttp configuration. Unadvertised hosts use HTTP/2 or HTTP/1.1 normally. A connection failure triggers a ten-minute backoff; a successful negotiated H3 session retains the origin's advertised `ma` expiry, capped at one hour rather than extending beyond the server policy. The origin cache is bounded at 128 entries. `Alt-Svc: clear` and `ma=0` revoke the advertisement; malformed `ma` entries are rejected.

The JSONL network log records `httpVersion` only when the adapter actually supplies the negotiated protocol (currently rhttp), separately from `http3Advertised`, which only reflects a response hint. When unknown, no negotiated protocol is asserted. Raw certificate contents, headers, token values and remote IPs are not added to this log.

## Verification

```sh
mkdir -p assets/certs assets/images/llm
flutter pub get --enforce-lockfile
dart run tool/gen_l10n.dart
dart format --output=none --set-exit-if-changed \
  lib/services/network/adapters/platform_adapter.dart \
  lib/services/network/adapters/rhttp_adapter.dart \
  lib/services/network/interceptors/https_security_interceptor.dart \
  lib/services/network/interceptors/redirect_interceptor.dart \
  lib/services/network/interceptors/network_log_interceptor.dart \
  test/services/network/adapters/rhttp_adapter_test.dart \
  test/services/network/interceptors/https_security_interceptor_test.dart \
  test/services/network/interceptors/redirect_interceptor_test.dart \
  test/services/network/request_tag_logging_test.dart
flutter analyze lib/services/network test/services/network
dart tool/flutterw.dart test test/services/network
```

The network redirect regression suite includes in-memory adapters that fully consume multipart upload streams on both 307 and 308, verifying bytes survive the replay. HTTP-version diagnostics accept `http_version` (rhttp) and `httpVersion` (Dio IO adapter) while keeping `Alt-Svc` hints separate.

The PR-specific `.github/workflows/https-advanced-network.yml` uses Flutter 3.47.4 from `.fvmrc` and runs **independent** `format`, `analyze`, and `test` jobs, so formatting or analysis errors do not suppress the other results. Each code-verification job restores locked dependencies; tests run through the repository's `tool/flutterw.dart` entrypoint. Browser TLS fingerprint, ECH, and compression features should be tested on a real device/network per adapter. HTTP/3 support cannot be demonstrated by a successful HTTP/2 response that merely contains Alt-Svc.

## Current CI visibility blocker

As of the latest PR review, GitHub returned **zero workflow runs and zero check runs** on this branch despite repeated pushes, so none of the code changes or tests are confirmed by CI yet. The workflow declares `push`, `pull_request`, and `workflow_dispatch` triggers; the cause of missing runs is not established. Check the repository's Actions settings, runner/usage status, and any event restrictions on app-authored commits; do **not** merge purely because GitHub reports the PR as mergeable. A local checkout of this PR branch can run the exact commands above without relying on Actions. In addition to these unit tests, verify login, normal uploads, 307/308 replay, Cloudflare 103, proxy fallback and browser/Wasm builds on applicable real targets.
