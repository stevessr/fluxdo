import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/avatar_cache_pool.dart';
import 'package:fluxdo/services/blob_image_cache.dart';

void main() {
  group('process-wide avatar image pool', () {
    const url =
        'https://linux.do/user_avatar/linux.do/example/96/123_2.png?v=4';

    test('nearby display sizes share a single decode key after switching', () {
      final pool = AvatarCachePool.instance;
      final accountA = pool.imageProvider(
        url,
        logicalDiameter: 30,
        devicePixelRatio: 2,
      );
      final accountB = pool.imageProvider(
        url,
        logicalDiameter: 32,
        devicePixelRatio: 2,
      );

      expect(accountA, equals(accountB));
      expect(accountA.hashCode, accountB.hashCode);
      expect(accountA, isA<ResizeImage>());

      final image = accountA as ResizeImage;
      expect(image.width, 128);
      expect(image.height, 128);
      expect(
        (image.imageProvider as BlobImageProvider).bucket,
        BlobImageCache.avatarBucket,
      );
    });

    test('larger render size remains distinct to prevent blurry avatars', () {
      final pool = AvatarCachePool.instance;
      final small = pool.imageProvider(
        url,
        logicalDiameter: 32,
        devicePixelRatio: 2,
      );
      final large = pool.imageProvider(
        url,
        logicalDiameter: 64,
        devicePixelRatio: 2,
      );
      expect(large, isNot(equals(small)));
      expect((large as ResizeImage).width, 256);
    });

    test('full URLs (host, revision, query and signature) remain isolated', () {
      final pool = AvatarCachePool.instance;
      ImageProvider avatar(String path) =>
          pool.imageProvider(path, logicalDiameter: 32, devicePixelRatio: 2);
      final original = avatar(url);
      expect(
        avatar(url.replaceFirst('linux.do/', 'other.do/')),
        isNot(equals(original)),
      );
      expect(
        avatar(url.replaceFirst('123_2', '124_2')),
        isNot(equals(original)),
      );
      expect(avatar(url.replaceFirst('v=4', 'v=5')), isNot(equals(original)));
      expect(avatar('$url&token=account-b'), isNot(equals(original)));
    });

    test('decode sizes are bounded and quantized', () {
      expect(AvatarCachePool.decodeSideFor(1, 1), 64);
      expect(AvatarCachePool.decodeSideFor(30, 2), 128);
      expect(AvatarCachePool.decodeSideFor(32, 2), 128);
      expect(AvatarCachePool.decodeSideFor(33, 2), 192);
      expect(AvatarCachePool.decodeSideFor(1024, 4), 512);
      expect(AvatarCachePool.decodeSideFor(double.nan, 2), 64);
    });

    test('only explicit SVG URLs need an eager disk probe', () {
      expect(AvatarCachePool.isExplicitSvg('https://a.test/x.svg?v=2'), isTrue);
      expect(
        AvatarCachePool.isExplicitSvg('https://a.test/u/avatar.png?v=.svg'),
        isFalse,
      );
      expect(AvatarCachePool.isExplicitSvg(url), isFalse);
    });
  });

  group('avatar SVG probe memory', () {
    test(
      'in-flight disk checks are coalesced across widget instances',
      () async {
        final completer = Completer<String?>();
        var calls = 0;
        final pool = AvatarCachePool.forTesting(
          svgLoader: (_) {
            calls++;
            return completer.future;
          },
        );

        const url = 'https://a.test/profile.svg';
        final first = pool.probeCachedSvg(url);
        final second = pool.probeCachedSvg(url);
        expect(identical(first, second), isTrue);
        expect(calls, 1);
        completer.complete('<svg>cached</svg>');
        expect(await first, '<svg>cached</svg>');
        expect(await second, '<svg>cached</svg>');
        expect(pool.hasSvgResult(url), isTrue);
        expect(pool.cachedSvg(url), '<svg>cached</svg>');
        expect(await pool.probeCachedSvg(url), '<svg>cached</svg>');
        expect(calls, 1);
      },
    );

    test('fallback discovered SVG supersedes an in-flight disk miss', () async {
      final completer = Completer<String?>();
      final pool = AvatarCachePool.forTesting(
        svgLoader: (_) => completer.future,
      );
      const url = 'https://a.test/user_avatar/example.png';
      final pending = pool.probeCachedSvg(url);
      pool.rememberSvg(url, '<svg>real</svg>');
      completer.complete(null);
      expect(await pending, '<svg>real</svg>');
      expect(pool.cachedSvg(url), '<svg>real</svg>');
    });

    test(
      'negative disk probes are memoized but valid SVG can replace them',
      () async {
        var calls = 0;
        final pool = AvatarCachePool.forTesting(
          svgLoader: (_) async {
            calls++;
            return null;
          },
        );
        const url = 'https://a.test/asset.svg';
        expect(await pool.probeCachedSvg(url), isNull);
        expect(pool.hasSvgResult(url), isTrue);
        expect(await pool.probeCachedSvg(url), isNull);
        expect(calls, 1);
        pool.rememberSvg(url, '<svg>updated</svg>');
        expect(pool.cachedSvg(url), '<svg>updated</svg>');
      },
    );

    test('SVG payload total stays bounded after visiting many accounts', () {
      final pool = AvatarCachePool.forTesting(svgLoader: (_) async => null);
      final svg = ''.padRight(48 * 1024, 'x');
      for (var i = 0; i < 100; i++) {
        pool.rememberSvg('https://a.test/$i.svg', svg);
      }

      // 100 * 48 KiB exceeds the independent 4 MiB SVG memo limit.
      expect(pool.svgMemoCharactersForTest, lessThanOrEqualTo(4 * 1024 * 1024));
      expect(pool.hasSvgResult('https://a.test/0.svg'), isFalse);
      expect(pool.hasSvgResult('https://a.test/99.svg'), isTrue);

      final previous = pool.svgMemoCharactersForTest;
      pool.rememberSvg('https://a.test/99.svg', '<svg/>');
      expect(pool.svgMemoCharactersForTest, previous - svg.length + 6);
    });

    test('SVG metadata is bounded independently from active accounts', () {
      final pool = AvatarCachePool.forTesting(svgLoader: (_) async => null);
      for (var i = 0; i < 1600; i++) {
        pool.rememberSvg('https://a.test/$i.svg', '<svg/>');
      }
      expect(pool.hasSvgResult('https://a.test/0.svg'), isFalse);
      expect(pool.cachedSvg('https://a.test/1599.svg'), '<svg/>');
    });
  });
}
