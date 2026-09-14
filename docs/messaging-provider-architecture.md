# Experimental multi-protocol messaging architecture

Branch: `feat/experimental-matrix-telegram`

This document records the boundary used by the experimental Discourse / Matrix /
Telegram work so protocol-specific SDKs do not leak into shared Fluxdo UI.

## Layers

1. `ChatHubPage` selects a protocol identity only. It does not know how Matrix
   sync works or how Telegram authenticates.
2. `MessagingProvider` is the protocol-neutral native timeline contract. It
   covers conversation discovery, timeline loading, text send, read receipts,
   typing and reactions, plus explicit capability flags for edits, threads,
   media and E2EE.
3. Protocol adapters translate their native models to `MessagingConversation`
   and `MessagingMessage`.
4. Login/session/device management remains protocol specific because Matrix,
   Telegram and Discourse have very different account semantics.

The current Matrix implementation is:

`Matrix UI -> MatrixMessagingProvider -> MatrixClientService -> Matrix CS API`

The intended mature implementation can become:

`Matrix UI/shared timeline -> ExteraMatrixProvider -> matrix-dart-sdk`

without changing the hub persistence model or introducing Matrix SDK types into
shared message widgets.

## Matrix migration stages

### Stage 1: lightweight REST adapter

Current capabilities:

- secure access-token persistence;
- password/token login;
- incremental `/sync`;
- unencrypted room history and text send;
- read receipts;
- typing;
- reaction send.

Still intentionally missing:

- E2EE/device verification/key backup/cross-signing;
- media upload/download;
- threads and edits;
- robust local relation aggregation;
- persistent encrypted timeline database.

### Stage 2: normalize Matrix semantics before changing SDK

The REST adapter should first expose the same semantics expected by a mature SDK
provider: room heroes/display names, room encryption state, paginated history,
locally aggregated reactions and applied message replacements. This keeps UI
behavior stable when the underlying transport is replaced.

### Stage 3: optional Extera-backed provider

Extera already has a mature Matrix client lifecycle, database and crypto stack.
Fluxdo can reuse that implementation direction after the dependency and license
boundary is deliberately chosen.

The Matrix SDK fork currently used by Extera is AGPL-3.0-or-later while Fluxdo's
root project is GPL-3.0. Do not silently add the SDK as a hard dependency. A
maintainer should explicitly review the distribution/licensing consequences and
choose the integration shape before enabling that provider in release builds.
This note is architectural guidance, not legal advice.

## Telegram migration stages

Telegram Web remains the compatibility fallback. A future native provider should
implement the same `MessagingProvider` timeline contract but keep Telegram's
login/session layer separate.

A native implementation is not considered ready merely because MTProto can log
in. Before replacing Web fallback it should cover:

- developer `api_id` / `api_hash` configuration without bundled sample secrets;
- phone login, code delivery, 2FA and DC migration;
- persistent authorization key/session state;
- updates/reconnect/backoff;
- dialogs and paginated history;
- media transfer;
- reactions/read state/typing where supported;
- multi-platform lifecycle testing.

## Capability-driven UI

Shared widgets must check `MessagingCapabilities` rather than infer features from
protocol names. For example, reaction controls should only appear when
`capabilities.reactions` is true, while encrypted-content UI should rely on
`capabilities.e2ee` and message metadata rather than assuming all Matrix rooms
are encrypted.

This lets experimental providers degrade honestly instead of exposing controls
that silently fail.
