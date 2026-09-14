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

## Matrix

The Matrix experiment currently supports:

- password login (`m.login.password`);
- importing an existing access token (useful for SSO homeservers);
- encrypted local session persistence through `flutter_secure_storage`;
- joined-room discovery through a single filtered `/sync` request;
- room ordering using the latest timeline event;
- unread notification count;
- paged room history (initial 50 events);
- sending plain-text `m.room.message` events;
- explicit placeholders for `m.room.encrypted` events.

The adapter intentionally does **not** pretend that encrypted events are plain
text. Full Matrix E2EE requires device keys, Olm/Megolm sessions, verification,
key backup/recovery, and cross-signing; that work belongs in a dedicated crypto
provider.

### Why not directly depend on Extera yet?

Extera is a useful source for the mature Matrix direction, but its current
Matrix SDK path effectively requires builds using Dart >= 3.11.1. Fluxdo still
advertises Dart `^3.10.4` as its minimum. For this experiment, the REST adapter
keeps the existing toolchain contract and avoids making Matrix a hard build-time
requirement for the rest of the app.

The Matrix UI/service boundary is deliberately isolated so the REST client can
later be replaced by an Extera/matrix-dart-sdk backed implementation without
changing the protocol hub.

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

- Matrix E2EE is not implemented yet.
- Matrix room avatars, typing, reactions, receipts, threads, edits, media and
  push notifications are not mapped yet.
- Matrix room display-name fallback is intentionally conservative; unnamed DMs
  may show their room ID until member-summary mapping is added.
- Telegram is Web-backed rather than mapped into Fluxdo's native message bubble
  model.
- Experimental strings are currently local to these LAB pages; move them into
  the generated localization catalog once the UX stabilizes.
- Add protocol-level notification aggregation only after account/session
  lifecycle semantics are finalized.
