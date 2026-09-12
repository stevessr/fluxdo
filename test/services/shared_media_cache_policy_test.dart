import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/blob_image_cache.dart';
import 'package:fluxdo/services/discourse_cache_manager.dart';

void main() {
  group('account-invariant media cache routing', () {
    test('site/config assets use the shared long-lived bucket', () {
      final provider = siteAssetImageProvider(
        'https://linux.do/uploads/default/original/1X/flair.png',
      );

      expect(provider, isA<BlobImageProvider>());
      expect(
        (provider as BlobImageProvider).bucket,
        BlobImageCache.externalBucket,
      );
    });

    test('same site asset keeps one Flutter cache identity across accounts', () {
      final firstAccount = siteAssetImageProvider(
        'https://linux.do/uploads/default/original/1X/flair.png',
      );
      final secondAccount = siteAssetImageProvider(
        'https://linux.do/uploads/default/original/1X/flair.png',
      );

      expect(secondAccount, equals(firstAccount));
      expect(secondAccount.hashCode, firstAccount.hashCode);
    });

    test('avatar, emoji and sticker providers never include account identity', () {
      const avatarUrl =
          'https://linux.do/user_avatar/linux.do/example/96/123.png';
      const emojiUrl = 'https://linux.do/images/emoji/twitter/heart.png';
      const stickerUrl =
          'https://linux.do/uploads/default/original/1X/sticker.png';

      final avatarA = discourseImageProvider(avatarUrl);
      final avatarB = discourseImageProvider(avatarUrl);
      final emojiA = emojiImageProvider(emojiUrl);
      final emojiB = emojiImageProvider(emojiUrl);
      final stickerA = stickerImageProvider(stickerUrl);
      final stickerB = stickerImageProvider(stickerUrl);

      expect(avatarB, equals(avatarA));
      expect(emojiB, equals(emojiA));
      expect(stickerB, equals(stickerA));
      expect((avatarA as BlobImageProvider).bucket, BlobImageCache.avatarBucket);
      expect((emojiA as BlobImageProvider).bucket, BlobImageCache.emojiBucket);
      expect(
        (stickerA as BlobImageProvider).bucket,
        BlobImageCache.stickerOriginalBucket,
      );
    });
  });
}
