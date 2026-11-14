# stevessr_generator

Standalone Flutter package containing the StevesSR image generator UI, render model, interactive preview, canvas painter, text layout, character asset/delta decoding, and PNG/WebP/AVIF/JPEG/SVG export. Assets are registered by this package at `assets/images/avater/`; the package does not import FluxDO, its services, or its localization layer.

## Run the example independently

```sh
cd packages/stevessr_generator/example
flutter pub get
for test_file in test/*_test.dart; do flutter test "$test_file"; done
flutter run
# Standalone Android ARM64 APK:
flutter build apk --release --target-platform android-arm64
# Desktop and web builds:
flutter build linux
flutter build web
# Or: flutter build windows / flutter build macos
```

For an initial checkout that lacks Flutter platform scaffolding in `example/`, generate it once with `flutter create --platforms=android,ios,linux,macos,windows,web .` from that directory.

## Embed in another Flutter app

Add the path dependency `stevessr_generator: { path: ../stevessr_generator }` (or use the published package when available), import `package:stevessr_generator/stevessr_generator.dart`, then use:

```dart
StevessrGeneratorPage(
  onInsert: (image) => editor.insertImage(image.bytes, mimeType: image.mimeType),
  onSave: (image) => hostSave(image.bytes, 'stevessr.${image.extension}'),
  onShare: (image) => hostShare(image.bytes, image.mimeType),
)
```

Callbacks are optional: insert is hidden when `onInsert` is null; save and share use package defaults when omitted. Generator UI strings have a package-local facade and copied StevesSR ARB source files, with no host localization dependency. To customize UI strings fully, use an app wrapper or extend the package-local localization implementation.

## Maintain avatar assets

The package owns the full source artwork and maintenance scripts under `tool/avatar_sources/` and `tool/`. Run these commands from the package directory; scripts resolve package input/output paths relative to their own location:

```sh
cd packages/stevessr_generator
dart pub get
dart run tool/gen_avatar_deltas.dart
dart run tool/gen_avatar_deltas.dart --check
```

The delta generator reads the package source artwork and rebuilds manifests, base images and expression patches only under `packages/stevessr_generator/assets/images/avater/`. It requires Dart dependencies only. See [tool/avatar_sources/README.md](tool/avatar_sources/README.md) for importing expressions, packing full StevesSR art and optional ImageMagick optimization.

## Android AVIF build note

The standalone Android example overrides `flutter_avif_android` with the source under `third_party/flutter_avif_android/`. The upstream 3.1.0 archive contains both Java and Kotlin implementations of the same plugin class and declares Java 11 while the Kotlin task targets Java 17. The local patch keeps the Java implementation required by Flutter's generated registrant, removes the duplicate Kotlin implementation, and aligns Java compatibility and compile SDK with the example app. This override is scoped to the example app; other consumers that build Android APKs should apply the same override or use an upstream release after these fixes are published.

## Public API

The single entrypoint exports `StevessrGeneratorPage`, `StevessrRenderParams`, `StevessrExportedImage`, `StevessrExportService`, `StevessrCanvas`, `StevessrInteractivePreview`, `StevessrCharacterAssets`, and `StevessrTextLayout`.
