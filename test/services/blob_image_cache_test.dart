import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/blob_image_cache.dart';

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
      // 单字符尾段触发整串回退搜索时,'.io/x' 含 '/' 必须被拒绝。
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

  group('BlobImageProvider global identity', () {
    test('同 URL / bucket 跨 profile 始终复用同一图片身份', () {
      // profile/session 刻意不进入 BlobImageProvider key。账号切换只更换
      // cookie/session；相同图片 URL 必须命中同一 Flutter ImageCache 项，
      // 磁盘层也由 BlobImageCache 的 bucket + md5(url) 唯一寻址。
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
    });
  });
}
