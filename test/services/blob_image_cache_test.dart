import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/blob_image_cache.dart';
import 'package:fluxdo/services/discourse_cache_manager.dart'
    show discourseImageProvider;

void main() {
  // 与 Telegram ImageLoader.getHttpUrlExtension 同款的规则:
  // 取最后一段路径里最后一个 '.' 的后缀;为空、长度 >4 或含非字母数字
  // 时回退默认值。缓存文件名靠它带扩展名,系统分享/保存才能按后缀定型。
  group('BlobImageCache.httpUrlExtension', () {
    test('常规图片 URL 提取扩展名并小写化', () {
      expect(
        BlobImageCache.httpUrlExtension(
          'https://example.com/uploads/a/b/Photo.JPEG',
        ),
        'jpeg',
      );
      expect(
        BlobImageCache.httpUrlExtension('https://example.com/x/y.gif'),
        'gif',
      );
      expect(
        BlobImageCache.httpUrlExtension('https://example.com/x/y.webp'),
        'webp',
      );
    });

    test('query / fragment 不影响提取', () {
      expect(
        BlobImageCache.httpUrlExtension(
          'https://example.com/a/b.png?v=123&w=100#frag',
        ),
        'png',
      );
    });

    test('最后一段无点时回退默认 jpg', () {
      expect(
        BlobImageCache.httpUrlExtension('https://example.com/uploads/short-url'),
        'jpg',
      );
      expect(BlobImageCache.httpUrlExtension('https://example.com/'), 'jpg');
      expect(BlobImageCache.httpUrlExtension('not a url'), 'jpg');
    });

    test('不会把域名后缀误吞成扩展名', () {
      expect(BlobImageCache.httpUrlExtension('https://a.io/x'), 'jpg');
    });

    test('后缀长度 >4 或含非字母数字时回退默认', () {
      expect(
        BlobImageCache.httpUrlExtension('https://example.com/a/b.html5'),
        'jpg',
      );
      expect(
        BlobImageCache.httpUrlExtension('https://example.com/a/b.c=d'),
        'jpg',
      );
    });

    test('支持自定义回退值', () {
      expect(
        BlobImageCache.httpUrlExtension('https://example.com/a/b', 'png'),
        'png',
      );
    });
  });

  group('BlobImageCache shared URL identity', () {
    test('物理对象只由 URL 决定，不受 bucket 或逻辑 key 影响', () {
      const url = 'https://example.com/uploads/shared/image.png';
      final objectFromContent = BlobImageCache.objectNameForUrl(url);
      final objectFromAvatar = BlobImageCache.objectNameForUrl(url);

      expect(objectFromAvatar, objectFromContent);
      expect(objectFromContent, endsWith('.png'));
    });

    test('不同逻辑 key 有不同引用身份，但可以共同指向同一 URL 对象', () {
      const url = 'https://example.com/uploads/shared/image.webp';
      final firstRef = BlobImageCache.referenceNameForKey('topic:123:hero');
      final secondRef = BlobImageCache.referenceNameForKey('profile:456:cover');

      expect(firstRef, isNot(secondRef));
      expect(BlobImageCache.objectNameForUrl(url), isNotEmpty);
    });
  });

  group('BlobImageProvider global identity', () {
    test('同 URL / bucket 跨 profile 始终复用同一图片身份', () {
      // profile/session 刻意不进入 BlobImageProvider key。账号切换只更换
      // cookie/session；相同图片 URL 必须命中同一 Flutter ImageCache 项，
      // 磁盘层也由 URL 的共享 object 唯一寻址。
      const firstProfile = BlobImageProvider(
        'https://linux.do/user_avatar/example/shared/96/1.png',
        bucket: BlobImageCache.avatarBucket,
      );
      const secondProfile = BlobImageProvider(
        'https://linux.do/user_avatar/example/shared/96/1.png',
        bucket: BlobImageCache.avatarBucket,
      );

      expect(secondProfile, equals(firstProfile));
      expect(secondProfile.hashCode, firstProfile.hashCode);
    });

    test('不同 bucket 仍保持用途隔离', () {
      const avatar = BlobImageProvider(
        'https://example.com/image.png',
        bucket: BlobImageCache.avatarBucket,
      );
      const content = BlobImageProvider(
        'https://example.com/image.png',
        bucket: BlobImageCache.contentBucket,
      );

      expect(content, isNot(equals(avatar)));
      expect(
        BlobImageCache.objectNameForUrl(content.url),
        BlobImageCache.objectNameForUrl(avatar.url),
      );
    });

    test('显式不同 cacheKey 保留独立逻辑身份', () {
      const first = BlobImageProvider(
        'https://example.com/image.png',
        bucket: BlobImageCache.contentBucket,
        cacheKey: 'topic:1:image',
      );
      const second = BlobImageProvider(
        'https://example.com/image.png',
        bucket: BlobImageCache.contentBucket,
        cacheKey: 'topic:2:image',
      );

      expect(second, isNot(equals(first)));
      expect(
        BlobImageCache.objectNameForUrl(second.url),
        BlobImageCache.objectNameForUrl(first.url),
      );
    });
  });

  group('avatar alpha-safe provider routing', () {
    test('Discourse 动图头像走标准 encoded codec 并自动进入 avatar bucket', () {
      final provider = discourseImageProvider(
        'https://linux.do/user_avatar/linux.do/example/96/123_2.gif',
      );

      expect(provider, isA<BlobImageProvider>());
      expect(
        (provider as BlobImageProvider).bucket,
        BlobImageCache.avatarBucket,
      );
    });

    test('显式 avatar bucket 的透明 WebP 也不进入 raw RGBA native 路径', () {
      final provider = discourseImageProvider(
        'https://cdn.example.com/custom/avatar.webp',
        bucket: BlobImageCache.avatarBucket,
      );

      expect(provider, isA<BlobImageProvider>());
      expect(
        (provider as BlobImageProvider).bucket,
        BlobImageCache.avatarBucket,
      );
    });

    test('正文动图继续保留 native 路由，不扩大 GIF disposal 回归面', () {
      final provider = discourseImageProvider(
        'https://linux.do/uploads/default/original/2X/a/animation.gif',
      );

      expect(provider, isNot(isA<BlobImageProvider>()));
    });
  });
}
