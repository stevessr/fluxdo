# Generator avatar source artwork

This directory contains the full source artwork used to produce the runtime character assets in `../assets/images/avater/`.

## Rebuild manifests and delta images

Run from the package directory (the script also resolves all package input/output paths relative to itself):

```sh
cd packages/stevessr_generator
dart pub get
dart run tool/gen_avatar_deltas.dart
dart run tool/gen_avatar_deltas.dart --check
```

`gen_avatar_deltas.dart` reads these source files and writes only under this package's `assets/images/avater/`. LLM expression patches are encoded losslessly and selected from PNG/WebP by encoded size. StevesSR source deltas are copied into runtime assets without re-encoding. No root `tool/`, workspace CLI helper, FluxDO package, or ImageMagick is needed to rebuild manifests.

## Import an edited LLM expression

ImageMagick is required only for source authoring. Given a generated/edited PNG:

```sh
dart run tool/import_avatar_expression.dart claude happy /path/to/edited.png
```

The importer edits only the lower face region and writes the resulting lossless WebP into `tool/avatar_sources/llm/<character>/`.

## Pack new StevesSR full expressions

Put the full `neutral.webp` and expression WebPs in a temporary directory, then run:

```sh
dart run tool/pack_stevessr_sources.dart /path/to/full-expressions
dart run tool/optimize_avatar_bases.dart
dart run tool/gen_avatar_deltas.dart
```

The packer writes canonical source images and `source.json` into this directory. Packing and optional optimization require ImageMagick; delta generation does not. `optimize_avatar_bases.dart --all-avatars` additionally checks static Touhou, Blue Archive and Witch Judgment images in the package's `assets/images/avater/`, retaining a replacement only when its decoded visible RGBA pixels are unchanged and the file is smaller.
