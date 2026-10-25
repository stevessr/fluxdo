import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'blob_image_cache.dart';
import 'discourse_cache_manager.dart';
import '../utils/svg_utils.dart';

typedef AvatarSvgLoader = Future<String?> Function(String url);

/// Process-wide avatar cache policy.
///
/// Account switching disposes page widgets, not this pool. Encoded bytes stay
/// in BlobImageCache's shared avatar bucket; decoded images use Flutter's
/// process-wide ImageCache and stable (URL, bucket, decode size) identities.
/// Neither layer uses the currently signed-in account as part of the key.
/// Complete URLs, including hosts, query parameters and avatar revisions,
/// remain distinct so a changed avatar never reuses an older image.
class AvatarCachePool {
  AvatarCachePool._(this._svgLoader);

  static final AvatarCachePool instance = AvatarCachePool._(_readCachedSvg);

  @visibleForTesting
  AvatarCachePool.forTesting({required AvatarSvgLoader svgLoader})
    : _svgLoader = svgLoader;

  static const int _maxSvgEntries = 1500;
  static const int _maxMemoizedSvgCharacters = 64 * 1024;
  static const List<int> _decodeSides = [64, 96, 128, 192, 256, 384, 512];

  final AvatarSvgLoader _svgLoader;
  final Map<String, String?> _svgMemo = {};
  final Map<String, Future<String?>> _svgInFlight = {};

  /// Normalize nearby layout sizes to a small set of decoded texture sizes.
  /// This prevents every avatar radius from creating another ImageCache key
  /// after profile/account navigation while preserving 2x physical resolution.
  static int decodeSideFor(double logicalDiameter, double devicePixelRatio) {
    if (!logicalDiameter.isFinite ||
        !devicePixelRatio.isFinite ||
        logicalDiameter <= 0 ||
        devicePixelRatio <= 0) {
      return _decodeSides.first;
    }
    final requested = (logicalDiameter * devicePixelRatio * 2).ceil();
    for (final side in _decodeSides) {
      if (requested <= side) return side;
    }
    return _decodeSides.last;
  }

  ImageProvider imageProvider(
    String url, {
    required double logicalDiameter,
    required double devicePixelRatio,
  }) {
    final side = decodeSideFor(logicalDiameter, devicePixelRatio);
    return sharedImageProvider(
      url,
      bucket: BlobImageCache.avatarBucket,
      cacheWidth: side,
      cacheHeight: side,
    );
  }

  /// A real .svg URL can be probed before attempting bitmap decoding. Most
  /// Discourse avatars are ordinary bitmaps and skip the disk probe entirely;
  /// disguised SVGs are detected and memorized by the error fallback instead.
  static bool isExplicitSvg(String url) =>
      Uri.tryParse(url)?.path.toLowerCase().endsWith('.svg') ?? false;

  bool hasSvgResult(String url) => _svgMemo.containsKey(url);

  String? cachedSvg(String url) {
    if (!_svgMemo.containsKey(url)) return null;
    final value = _svgMemo.remove(url);
    _svgMemo[url] = value; // Recent reads remain in the bounded LRU.
    return value;
  }

  /// Store the SVG discovered by the bitmap decoder's error fallback. A
  /// positive result may supersede an earlier disk-miss (negative probe).
  void rememberSvg(String url, String content) {
    if (content.length > _maxMemoizedSvgCharacters) return;
    _putSvg(url, content);
  }

  Future<String?> probeCachedSvg(String url) {
    if (_svgMemo.containsKey(url)) return Future.value(cachedSvg(url));
    final inFlight = _svgInFlight[url];
    if (inFlight != null) return inFlight;

    final future = _performProbe(url);
    _svgInFlight[url] = future;
    unawaited(
      future.then((_) {
        if (identical(_svgInFlight[url], future)) _svgInFlight.remove(url);
      }),
    );
    return future;
  }

  Future<String?> _performProbe(String url) async {
    String? result;
    try {
      result = await _svgLoader(url);
    } catch (_) {
      // Probe failures are only optimization misses. Image decoding and its
      // SVG fallback remain responsible for rendering and retry behavior.
    }
    if (_svgMemo.containsKey(url)) return cachedSvg(url);
    if (result == null) {
      _putSvg(url, null);
    } else {
      rememberSvg(url, result);
    }
    return result;
  }

  void _putSvg(String url, String? content) {
    _svgMemo.remove(url);
    _svgMemo[url] = content;
    if (_svgMemo.length > _maxSvgEntries) {
      _svgMemo.remove(_svgMemo.keys.first);
    }
  }

  static Future<String?> _readCachedSvg(String url) async {
    final bytes = await BlobImageCache.read(BlobImageCache.avatarBucket, url);
    if (bytes == null || bytes.isEmpty || !SvgUtils.isSvgBytes(bytes)) {
      return null;
    }
    return SvgUtils.sanitize(SvgUtils.decodeSvgBytes(bytes));
  }
}
