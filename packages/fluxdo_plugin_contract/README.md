# FluxDO plugin contract

Pure Dart policy for the Android companion protocol. This package has no
Flutter, host application, filesystem, network or third-party dependency.
It deliberately stays outside the root Pub workspace, so the contract can be
validated even when the host's Flutter plugins or git submodules are unavailable.
The host consumes it as a local path dependency.

```sh
cd packages/fluxdo_plugin_contract
dart pub get --offline
dart analyze --fatal-infos
dart run test/contract_test.dart
```

`lib/src/catalog.g.dart` and Android's `PluginProtocol.kt` are generated together
by `scripts/ci/generate_android_plugin_catalog.py`. Edit the module identities,
operations and versions in `android_modular/plugins.json`; edit shared wire
limits in `scripts/ci/android_plugin_catalog.py`, then regenerate from the repo
root. CI refuses stale output.

The library validates native operation requests, launch payloads, bounded JSON
responses and plugin status identity. Status display names come from the catalog;
unknown or duplicate identities and contradictory readiness are protocol errors.
An unsupported future reason can be displayed only as an incompatible module.

Activity launch payloads contain only an opaque account slot (CDK/LDC) or public
recipient identity (LDC Reward). Account hashing, platform channels, same-signer
checks, service binding, UI and feature implementations belong to their existing
host/native modules. The Dart checks do not replace Android signature permissions
or native validation. Sticker uses a separate Activity/URI transport.

The SDK-only runner throws on failure with assertions enabled or disabled. Its
cases cover every declared operation, module identity, transport mixups, field
allowlists, DNS labels, account partitions, public recipient bounds, missing or
invalid JSON, multibyte byte limits and immutable collections. The host Flutter
tests additionally exercise real MethodChannel encoding, fallback and timeout.
