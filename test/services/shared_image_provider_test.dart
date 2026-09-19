import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/blob_image_cache.dart';
import 'package:fluxdo/services/discourse_cache_manager.dart';
import 'package:fluxdo/services/sticker_thumbnail_provider.dart';

void main() {
  group('统一图片 Provider / ImageCache key', () {
    const staticUrl = 'https://linux.do/uploads/default/original/1X/photo.png';

    test('基础图片由多个入口构造时使用相同的 key', () {
      final fromPost = discourseImageProvider(staticUrl);
      final fromSharedWidget = sharedImageProvider(staticUrl);
      expect(fromSharedWidget, equals(fromPost));
      expect(fromSharedWidget.hashCode, fromPost.hashCode);
    });

    test('静态图相同 URL + bucket + 尺寸复用解码 key', () {
      final fromAvatarWidget = sharedImageProvider(
        staticUrl,
        bucket: BlobImageCache.avatarBucket,
        cacheWidth: 128,
        cacheHeight: 128,
      );
      final fromOtherWidget = ResizeImage(
        const BlobImageProvider(
          staticUrl,
          bucket: BlobImageCache.avatarBucket,
        ),
        width: 128,
        height: 128,
        policy: ResizeImagePolicy.fit,
      );

      expect(fromAvatarWidget, equals(fromOtherWidget));
      expect(fromAvatarWidget.hashCode, fromOtherWidget.hashCode);
      expect(
        sharedImageProvider(
          staticUrl,
          bucket: BlobImageCache.avatarBucket,
          cacheWidth: 256,
          cacheHeight: 128,
        ),
        isNot(equals(fromAvatarWidget)),
      );
      expect(
        sharedImageProvider(
          staticUrl,
          bucket: BlobImageCache.contentBucket,
          cacheWidth: 128,
          cacheHeight: 128,
        ),
        isNot(equals(fromAvatarWidget)),
      );
    });

    test('URL 查询参数是字节身份的一部分，不合并不同鉴权/缩略图', () {
      final signedA = sharedImageProvider('$staticUrl?token=a&width=100');
      final signedB = sharedImageProvider('$staticUrl?token=b&width=100');
      final resized = sharedImageProvider('$staticUrl?token=a&width=200');
      expect(signedA, isNot(equals(signedB)));
      expect(signedA, isNot(equals(resized)));
    });

    test('带查询参数的 GIF 仍使用完整动画路由', () {
      const url = 'https://linux.do/uploads/default/a.gif?v=2';
      expect(
        sharedImageProvider(url),
        equals(discourseImageProvider(url)),
      );
      expect(sharedImageProvider(url), isNot(isA<BlobImageProvider>()));
    });

    test('贴纸缩略图使用独立尺寸和首帧 key，正文不退化成单帧', () {
      const url = 'https://linux.do/uploads/default/sticker.webp?v=2';
      final thumb = sharedImageProvider(
        url,
        bucket: BlobImageCache.stickerOriginalBucket,
        cacheWidth: 64,
        cacheHeight: 96,
        thumbnailMode: true,
      );
      expect(thumb, isA<StickerThumbnailProvider>());
      final typed = thumb as StickerThumbnailProvider;
      expect(typed.targetSize, 96);
      expect(
        thumb,
        equals(
          sharedImageProvider(
            url,
            bucket: BlobImageCache.stickerOriginalBucket,
            cacheWidth: 64,
            cacheHeight: 96,
            thumbnailMode: true,
          ),
        ),
      );
      expect(
        sharedImageProvider(
          url,
          bucket: BlobImageCache.stickerOriginalBucket,
          cacheWidth: 64,
          cacheHeight: 96,
        ),
        isNot(isA<StickerThumbnailProvider>()),
      );
    });

    test('动画头像即使启用缩略图模式也保留 alpha-safe 路由', () {
      const url =
          'https://linux.do/user_avatar/linux.do/example/96/123_2.gif?v=1';
      final fromContent = sharedImageProvider(
        url,
        cacheWidth: 96,
        cacheHeight: 96,
        thumbnailMode: true,
      );
      final fromAvatar = sharedImageProvider(
        url,
        bucket: BlobImageCache.avatarBucket,
      );
      expect(fromContent, isA<BlobImageProvider>());
      expect((fromContent as BlobImageProvider).bucket,
          BlobImageCache.avatarBucket);
      expect(fromContent, equals(fromAvatar));
    });
  });
}
