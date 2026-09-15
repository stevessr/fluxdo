# Experimental Matrix + Telegram chat

Branch: `feat/experimental-matrix-telegram`

This branch keeps the existing Discourse chat implementation intact and adds a
small protocol hub above it. The Chat navigation entry now exposes three
providers:

- **Discourse** — the existing Fluxdo chat UI and providers, unchanged.
- **Matrix (LAB)** — native Client-Server API adapter using Fluxdo's existing
  `dio` and `flutter_secure_storage` dependencies.
- **Telegram (LAB)** — Telegram Web embedded through Fluxdo's existing
  `flutter_inappwebview` dependency.

Protocol pages are lazily instantiated and kept alive only after first use, so
opening Discourse does not eagerly initialize Matrix networking or a Telegram
WebView.

## Toolchain experiment

The branch pins **Flutter 3.47.2 / Dart 3.13.2** in `.fvmrc` and has a dedicated
`Experimental Matrix Telegram` workflow. The workflow prepares generated Fluxdo
sources through `tool/project_prep.dart`, analyzes the app sources separately
from standalone DevTools/plugin-example packages, runs the chat/messaging test
suites, and independently performs an Android arm64 debug APK smoke build.

The Android defaults relevant to Fluxdo remain compatible with the existing
project setup (compile/target SDK 36, minSdk 24, NDK 28.2.13676358), so this
experiment does not force an unrelated Android Gradle/Kotlin migration.

## Matrix

The lightweight Matrix adapter currently supports:

- password login (`m.login.password`), access-token import and SSO;
- Matrix homeserver discovery through `.well-known` with explicit endpoint
  validation;
- canonical Matrix user ID verification through `/account/whoami`;
- encrypted local session persistence through `flutter_secure_storage`;
- joined-room discovery through a filtered initial `/sync`;
- incremental room state using `next_batch` / `since`;
- lifecycle-aware, cancellable 30-second `/sync` long polling while the Matrix
  page is active, with cancellation on background/logout/manual full-sync and
  bounded retry delay after transport failures;
- event-driven active-Room refresh: `/sync` only broadcasts the IDs of rooms
  whose timeline changed, and the open Room requests a fresh `/messages` page
  only for its own room instead of polling history every 20 seconds;
- Room invalidation coalescing while the app is backgrounded, a Thread route is
  visible, or history/send/upload work is already in flight;
- explicit Room refreshes consume older pending invalidations, while a newer
  `/sync` delta arriving during that request remains pending and triggers one
  follow-up refresh;
- room ordering using the latest visible timeline event and unread counts;
- `m.heroes`-based room-name fallback without requesting full membership state
  for every large room;
- paged room history with bounded relation-event caches across pages;
- Matrix rich replies and `m.thread` relations, including fallback reply
  metadata for clients without thread rendering;
- dedicated Thread pages with pagination, read receipts, typing notifications,
  reactions and attachment sending;
- public `m.read` read receipts and debounced typing notifications;
- reaction sending plus local aggregation with sender/key de-duplication;
- standard text edits through `m.replace` + `m.new_content`;
- standard event redaction through `/rooms/{roomId}/redact/{eventId}/{txnId}`;
- edit/redaction actions for the current user's eligible plaintext messages in
  both Room and Thread views;
- plaintext image/file uploads using streaming IO rather than loading the whole
  attachment into the Dart heap;
- authenticated Matrix media download/thumbnail endpoints, bounded in-memory
  media caching, request coalescing and streamed temporary-file downloads;
- a short-lived `/media/config` cache to avoid querying upload limits for every
  attachment;
- explicit placeholders for `m.room.encrypted` events rather than pretending
  they are plaintext.

The room-update signal deliberately contains only room IDs. Raw `/sync` timeline
events are not copied into the paged-history LRU, so live room-list traffic does
not evict relation/history data for recently opened rooms. The active Room owns
its `/messages` cache and uses `/sync` only as an invalidation source.

The adapter intentionally does **not** pretend that encrypted events are plain
text. Full Matrix E2EE requires device keys, Olm/Megolm sessions, verification,
key backup/recovery, cross-signing and encrypted-media handling; that work
belongs in a dedicated SDK/crypto provider. Plaintext send/reply/thread,
reaction, edit/redaction, typing and attachment actions stay disabled in E2EE
rooms until that provider exists.

### Provider boundary

The common messaging abstraction exposes protocol capabilities rather than
assuming every backend has identical semantics. Matrix additionally implements
an optional mutation provider for edit/redaction, so future Discourse or
Telegram adapters do not need fake mutation methods merely to satisfy the base
interface.

### Extera / matrix-dart-sdk path

Extera is still the preferred reference for the mature Matrix direction. Its
current Matrix SDK fork (`stevessr/matrix-dart-sdk`, Matrix 11.x snapshot)
requires Dart >= 3.11, so the Flutter 3.47.2 / Dart 3.13.2 experiment removes the
previous toolchain blocker.

The lightweight REST adapter remains useful as a low-dependency fallback and as
a protocol-boundary prototype. Replacing its crypto/message implementation with
Extera's SDK can now be evaluated independently, without changing the Chat hub
or Discourse provider. The SDK dependency also needs a deliberate license review
before it is made part of Fluxdo's default dependency graph.

## Telegram

Telegram starts with the complete official Web client embedded in-app. This is
not a bot-only integration: users can sign in to their normal Telegram account
and use the full Web UI, while cookies/session data remain managed by the
existing WebView stack.

The WebView integration keeps Telegram-owned navigation inside the embedded
client, routes custom/external schemes outside the WebView, handles the current
InAppWebView download callback and avoids progress-driven rebuild churn.

This choice avoids shipping platform-specific TDLib (`tdjson`) binaries in the
first experiment. Fluxdo already depends on `flutter_inappwebview
^6.2.0-beta.3`, including its Linux implementation.

### Native follow-up

Two viable native directions remain behind the `TelegramChatPage` boundary:

1. `tg` (pure Dart MTProto) — attractive because it has no TDLib native binary,
   but currently exposes a relatively low-level login/DC/session API and needs a
   user/developer `api_id` + `api_hash` flow.
2. `tdlib_ex` — broader TDLib semantics, but it adds native binary packaging and
   version-matching work for every supported platform.

A native implementation should preserve Telegram Web as fallback until login,
2FA, DC migration, updates, media downloads/uploads, and session persistence are
verified on Android, iOS, Windows, Linux, and macOS.

## Known limitations / next steps

- Matrix E2EE is not implemented yet; encrypted events are deliberately not
  shown as plaintext and plaintext mutation/send controls stay disabled there.
- The REST adapter does not yet implement device verification, cross-signing,
  key backup/recovery, encrypted attachments, push notifications, room avatars
  or the complete member/presence model. These are better candidates for the
  SDK-backed provider than for hand-written crypto/state logic.
- The live Room invalidation layer intentionally refetches the bounded latest
  `/messages` page instead of merging raw `/sync` events into history. A future
  SDK-backed provider can replace this invalidation/refetch boundary with its
  native timeline cache without changing Room UI semantics.
- Telegram is Web-backed rather than mapped into Fluxdo's native message bubble
  model.
- Experimental strings are currently local to these LAB pages; move them into
  the generated localization catalog once the UX stabilizes.
- Keep Telegram Web as a fallback while a pure-Dart MTProto or TDLib transport is
  experimentally introduced behind the same provider boundary.
