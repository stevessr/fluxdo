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

## Toolchain experiment

The branch pins **Flutter 3.47.2 / Dart 3.13.2** in `.fvmrc` and has a dedicated
`Experimental Matrix Telegram` workflow. The workflow prepares generated Fluxdo
sources through `tool/project_prep.dart`, analyzes the app sources separately
from standalone DevTools/plugin-example packages, and independently performs an
Android arm64 debug APK smoke build.

The Android defaults relevant to Fluxdo remain compatible with the existing
project setup (compile/target SDK 36, minSdk 24, NDK 28.2.13676358), so this
experiment does not force an unrelated Android Gradle/Kotlin migration.

## Matrix

The Matrix experiment currently supports:

- password login (`m.login.password`);
- importing an existing access token (useful for SSO homeservers), with the
  canonical Matrix user ID resolved through `/account/whoami`;
- encrypted local session persistence through `flutter_secure_storage`;
- joined-room discovery through filtered `/sync`;
- incremental room refresh using the returned `next_batch` token instead of
  repeating a full initial sync on every refresh;
- room ordering using the latest timeline event;
- unread notification count;
- paged room history (initial 50 events);
- sending plain-text `m.room.message` events;
- public `m.read` read receipts when a room is opened;
- debounced typing notifications;
- sending `m.reaction` annotations from a quick reaction picker;
- explicit placeholders for `m.room.encrypted` events.

The adapter intentionally does **not** pretend that encrypted events are plain
text. Full Matrix E2EE requires device keys, Olm/Megolm sessions, verification,
key backup/recovery, and cross-signing; that work belongs in a dedicated crypto
provider.

### Extera / matrix-dart-sdk path

Extera is still the preferred reference for the mature Matrix direction. Its
current Matrix SDK fork (`stevessr/matrix-dart-sdk`, Matrix 11.x snapshot)
requires Dart >= 3.11, so the Flutter 3.47.2 / Dart 3.13.2 experiment removes the
previous toolchain blocker.

The lightweight REST adapter remains useful as a low-dependency fallback and as
a protocol-boundary prototype. Replacing its crypto/message implementation with
Extera's SDK can now be evaluated independently, without changing the Chat hub
or Discourse provider.

## Telegram

Telegram starts with the complete official Web client embedded in-app. This is
not a bot-only integration: users can sign in to their normal Telegram account
and use the full Web UI, while cookies/session data remain managed by the
existing WebView stack.

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
  shown as plaintext.
- Matrix reaction aggregation/display, threads, edits, media, room avatars,
  membership-derived DM names and push notifications still need mapping.
- Incremental `/sync` is currently driven by UI refresh; a cancellable long-poll
  sync loop should replace periodic/manual refresh once account lifecycle and
  background execution semantics are settled.
- Telegram is Web-backed rather than mapped into Fluxdo's native message bubble
  model.
- Experimental strings are currently local to these LAB pages; move them into
  the generated localization catalog once the UX stabilizes.
- Keep Telegram Web as a fallback while a pure-Dart MTProto or TDLib transport is
  experimentally introduced behind the same provider boundary.
