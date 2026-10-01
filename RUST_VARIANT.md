# FluxDO Rust Variant

This branch is the full-Rust variant of FluxDO.

## Goal

Move application-owned executable logic from Dart/Flutter to Rust while preserving FluxDO behavior and protocol compatibility. Platform manifests, icons, signing metadata, generated resources, and unavoidable vendor/platform glue are not counted as application logic.

The end state is:

- Rust owns domain models, Discourse API, authentication/session state, cookies, MessageBus, caching, storage, media processing, background work, update logic, navigation state, and UI state.
- Rust owns the application UI.
- Dart/Flutter is migration-only and is removed after feature parity.
- Existing user data remains migratable.
- Android, iOS, Windows, macOS, and Linux remain supported.

## Workspace

The new implementation lives under `rust/`.

- `fluxdo-core`: domain types and application services.
- `fluxdo-discourse`: Discourse protocol/client boundary.
- `fluxdo-storage`: persistence boundary and migration contracts.
- `fluxdo-app`: Rust application entry point / UI host.

## Migration rules

1. Do not mechanically transliterate Dart into Rust. Preserve externally observable behavior and redesign internals around ownership, traits, async tasks, and explicit error types.
2. New feature work on this branch should land in Rust first.
3. During migration, Dart may call Rust through a narrow compatibility bridge; Rust must not depend on Dart business logic.
4. Every migrated module needs behavior tests or protocol fixtures before the Dart implementation is removed.
5. Keep storage and network formats backward compatible unless a versioned migration is included.
6. Remove migrated Dart code rather than keeping two permanent implementations.
7. Generated code, platform project files, assets, localization catalogs, PDK/vendor code, and build metadata may remain non-Rust where the platform requires them.

## Migration order

### Phase 1 — foundations
- Domain models and typed errors
- Config/preferences
- Logging and diagnostics
- Discourse URL/request/response types
- Auth and cookie/session model
- Storage abstraction and data migrations

### Phase 2 — network and realtime
- HTTP stack
- Cloudflare/browser-trust coordination
- MessageBus
- uploads/downloads
- proxy/DoH integration

### Phase 3 — application services
- topics/posts/users/notifications/search
- bookmarks/history/read-later
- account switching
- stickers/emoji/media pipelines
- background notifications and update checks

### Phase 4 — UI/state
- navigation model
- state/store layer
- adaptive desktop/mobile UI
- editor/rendering
- settings and diagnostics

### Phase 5 — cutover
- import existing Flutter data
- feature-parity regression suite
- remove Dart/Flutter application code
- make Rust app the default build target

## Definition of “all code Rusted”

The branch is considered complete when no application-owned behavior requires Dart execution. Non-Rust files that are required as platform manifests, build metadata, resources, translations, shaders, or vendor code are allowed.
