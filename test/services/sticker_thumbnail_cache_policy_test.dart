import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/sticker_thumbnail_cache_policy.dart';

Uint8List _pngPayload() => Uint8List.fromList(const [
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ]);

Uint8List _avifBytes() => Uint8List.fromList(const [
      0x00,
      0x00,
      0x00,
      0x18,
      0x66,
      0x74,
      0x79,
      0x70,
      0x61,
      0x76,
      0x69,
      0x66,
      0x00,
      0x00,
      0x00,
      0x00,
      0x6d,
      0x69,
      0x66,
      0x31,
      0x61,
      0x76,
      0x69,
      0x66,
    ]);

Uint8List _gifBytes() => Uint8List.fromList(const [
      0x47,
      0x49,
      0x46,
      0x38,
      0x39,
      0x61,
    ]);

Uint8List _webpBytes() => Uint8List.fromList(const [
      0x52,
      0x49,
      0x46,
      0x46,
      0x04,
      0x00,
      0x00,
      0x00,
      0x57,
      0x45,
      0x42,
      0x50,
    ]);

Uint8List _apngBytes() => Uint8List.fromList(const [
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
      // zero-length acTL chunk is enough for the cache format sniffer test;
      // production decoding still validates the actual file.
      0x00,
      0x00,
      0x00,
      0x00,
      0x61,
      0x63,
      0x54,
      0x4c,
      0x00,
      0x00,
      0x00,
      0x00,
    ]);

void main() {
  test('resource key is stable and contains no cache schema version', () {
    final key = StickerThumbnailCachePolicy.key(
      'https://example.com/sticker.avif',
      256,
    );
    expect(key, 'sticker_thumb:256:https://example.com/sticker.avif');
    expect(key.contains('sticker_thumb:v'), isFalse);
  });

  test('formats keep independent schema versions', () {
    expect(
      StickerThumbnailCachePolicy.schemaVersion(StickerThumbnailFormat.avif),
      4,
    );
    expect(
      StickerThumbnailCachePolicy.schemaVersion(StickerThumbnailFormat.gif),
      2,
    );
    expect(
      StickerThumbnailCachePolicy.schemaVersion(StickerThumbnailFormat.webp),
      1,
    );
    expect(
      StickerThumbnailCachePolicy.schemaVersion(StickerThumbnailFormat.apng),
      1,
    );
  });

  test('cache envelope round-trips current format version', () {
    final payload = _pngPayload();
    final record = StickerThumbnailCachePolicy.wrap(
      StickerThumbnailFormat.avif,
      payload,
    );
    expect(StickerThumbnailCachePolicy.unwrap(record), orderedEquals(payload));
  });

  test('stale schema invalidates only that record', () {
    final staleAvif = StickerThumbnailCachePolicy.wrap(
      StickerThumbnailFormat.avif,
      _pngPayload(),
    );
    // Header bytes 5..6 are the per-format uint16 schema version.
    staleAvif[5] = 0;
    staleAvif[6] = 3;
    expect(StickerThumbnailCachePolicy.unwrap(staleAvif), isNull);

    final currentGif = StickerThumbnailCachePolicy.wrap(
      StickerThumbnailFormat.gif,
      _pngPayload(),
    );
    expect(StickerThumbnailCachePolicy.unwrap(currentGif), isNotNull);
  });

  test('actual bytes override misleading CDN suffixes', () {
    expect(
      StickerThumbnailCachePolicy.detectFormat(
        _avifBytes(),
        'https://example.com/sticker.gif',
      ),
      StickerThumbnailFormat.avif,
    );
    expect(
      StickerThumbnailCachePolicy.detectFormat(
        _gifBytes(),
        'https://example.com/sticker.avif',
      ),
      StickerThumbnailFormat.gif,
    );
  });

  test('detects WebP and APNG cache formats', () {
    expect(
      StickerThumbnailCachePolicy.detectFormat(
        _webpBytes(),
        'https://example.com/sticker.bin',
      ),
      StickerThumbnailFormat.webp,
    );
    expect(
      StickerThumbnailCachePolicy.detectFormat(
        _apngBytes(),
        'https://example.com/sticker.bin',
      ),
      StickerThumbnailFormat.apng,
    );
  });
}
