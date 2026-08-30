import 'dart:typed_data';

/// Sticker thumbnail payload format.
///
/// Cache schema versions are intentionally attached to the decoded source
/// format instead of the resource key. A decoder/cache fix for one format can
/// therefore invalidate only that format without flushing every sticker.
enum StickerThumbnailFormat {
  avif,
  gif,
  webp,
  apng,
  unknown,
}

/// Versionless sticker-thumbnail key + format-scoped cache envelope.
///
/// The BlobImageCache key is always stable:
/// `sticker_thumb:<targetSize>:<url>`.
///
/// Per-format schema versions live inside a tiny envelope in front of the PNG
/// payload. On read, a stale version is treated as a cache miss and the same
/// stable key is overwritten. This keeps cache identity independent from
/// decoder implementation versions and prevents an AVIF-only fix from
/// invalidating GIF/WebP/APNG thumbnails.
class StickerThumbnailCachePolicy {
  StickerThumbnailCachePolicy._();

  static const Map<StickerThumbnailFormat, int> schemaVersions = {
    // v4 corresponds to the animated-AVIF first-frame decoder fix.
    StickerThumbnailFormat.avif: 4,
    // v2 corresponds to the GIF true-first-frame decoder path.
    StickerThumbnailFormat.gif: 2,
    StickerThumbnailFormat.webp: 1,
    StickerThumbnailFormat.apng: 1,
    StickerThumbnailFormat.unknown: 1,
  };

  // "STC1" = Sticker Thumbnail Cache envelope v1.
  static const List<int> _magic = [0x53, 0x54, 0x43, 0x31];
  static const int _headerLength = 8;

  static String key(String url, int targetSize) {
    return 'sticker_thumb:$targetSize:$url';
  }

  static int schemaVersion(StickerThumbnailFormat format) {
    return schemaVersions[format] ?? 1;
  }

  /// Wrap a PNG payload with source-format + schema-version metadata.
  static Uint8List wrap(
    StickerThumbnailFormat format,
    Uint8List pngBytes,
  ) {
    final version = schemaVersion(format);
    if (version < 0 || version > 0xffff) {
      throw RangeError.range(version, 0, 0xffff, 'schemaVersion');
    }

    final out = Uint8List(_headerLength + pngBytes.length);
    out.setRange(0, _magic.length, _magic);
    out[4] = format.index;
    out[5] = (version >> 8) & 0xff;
    out[6] = version & 0xff;
    out[7] = 0; // reserved for envelope flags
    out.setRange(_headerLength, out.length, pngBytes);
    return out;
  }

  /// Return the PNG payload only when the envelope is valid and the stored
  /// format schema still matches the current one. Legacy/raw PNG entries and
  /// stale format versions deliberately miss and are overwritten lazily.
  static Uint8List? unwrap(Uint8List cachedBytes) {
    if (cachedBytes.length < _headerLength + 8) return null;
    for (var i = 0; i < _magic.length; i++) {
      if (cachedBytes[i] != _magic[i]) return null;
    }

    final formatIndex = cachedBytes[4];
    if (formatIndex < 0 || formatIndex >= StickerThumbnailFormat.values.length) {
      return null;
    }
    final format = StickerThumbnailFormat.values[formatIndex];
    final storedVersion = (cachedBytes[5] << 8) | cachedBytes[6];
    if (storedVersion != schemaVersion(format)) return null;

    final payload = Uint8List.sublistView(cachedBytes, _headerLength);
    // Cached thumbnail payloads are always PNG. Reject a malformed/truncated
    // record before passing it into Flutter's codec.
    if (!_looksLikePng(payload)) return null;
    return payload;
  }

  /// Detect the actual downloaded container first, then use the URL suffix only
  /// as a fallback. This matters for Discourse/CDN URLs whose suffix can differ
  /// from the bytes they serve: such a file must inherit the decoder schema of
  /// its real format, not its advertised extension.
  static StickerThumbnailFormat detectFormat(Uint8List bytes, String url) {
    if (_looksLikeAvif(bytes)) return StickerThumbnailFormat.avif;
    if (_looksLikeGif(bytes)) return StickerThumbnailFormat.gif;
    if (_looksLikeWebp(bytes)) return StickerThumbnailFormat.webp;
    if (_looksLikeApng(bytes)) return StickerThumbnailFormat.apng;

    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    if (path.endsWith('.avif')) return StickerThumbnailFormat.avif;
    if (path.endsWith('.gif')) return StickerThumbnailFormat.gif;
    if (path.endsWith('.webp')) return StickerThumbnailFormat.webp;
    if (path.endsWith('.apng')) return StickerThumbnailFormat.apng;
    return StickerThumbnailFormat.unknown;
  }

  static bool _looksLikeAvif(Uint8List bytes) {
    if (bytes.length < 12) return false;
    if (bytes[4] != 0x66 ||
        bytes[5] != 0x74 ||
        bytes[6] != 0x79 ||
        bytes[7] != 0x70) {
      return false;
    }
    final b8 = bytes[8], b9 = bytes[9], b10 = bytes[10], b11 = bytes[11];
    return (b8 == 0x61 && b9 == 0x76 && b10 == 0x69 && (b11 == 0x66 || b11 == 0x73)) ||
        (b8 == 0x6d && b9 == 0x69 && b10 == 0x66 && b11 == 0x31) ||
        (b8 == 0x6d && b9 == 0x73 && b10 == 0x66 && b11 == 0x31);
  }

  static bool _looksLikeGif(Uint8List bytes) {
    if (bytes.length < 6) return false;
    return bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        (bytes[4] == 0x37 || bytes[4] == 0x39) &&
        bytes[5] == 0x61;
  }

  static bool _looksLikeWebp(Uint8List bytes) {
    if (bytes.length < 12) return false;
    return bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
  }

  static bool _looksLikePng(Uint8List bytes) {
    if (bytes.length < 8) return false;
    return bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a;
  }

  static bool _looksLikeApng(Uint8List bytes) {
    if (!_looksLikePng(bytes)) return false;
    var offset = 8;
    while (offset + 12 <= bytes.length) {
      final length = (bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
      if (length < 0 || offset + 12 + length > bytes.length) return false;
      final t0 = bytes[offset + 4];
      final t1 = bytes[offset + 5];
      final t2 = bytes[offset + 6];
      final t3 = bytes[offset + 7];
      // acTL must appear before the first IDAT in a valid APNG.
      if (t0 == 0x61 && t1 == 0x63 && t2 == 0x54 && t3 == 0x4c) return true;
      if (t0 == 0x49 && t1 == 0x44 && t2 == 0x41 && t3 == 0x54) return false;
      offset += 12 + length;
    }
    return false;
  }
}
