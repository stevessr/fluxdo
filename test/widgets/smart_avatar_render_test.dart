import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fluxdo/services/avatar_cache_pool.dart';
import 'package:fluxdo/utils/avatar_url.dart';
import 'package:fluxdo/utils/url_helper.dart';
import 'package:fluxdo/widgets/common/smart_avatar.dart';

void main() {
  testWidgets('avatar templates resolve and recycled widgets use new images', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    UrlHelper.debugSetOverrides(baseUri: '', cdnUrl: 'https://cdn.example.com');
    addTearDown(UrlHelper.debugClearOverrides);
    AvatarUrl.configure('24|48|72|96|144|288');
    addTearDown(() => AvatarUrl.configure(null));

    final keys = <Object>[];
    for (final username in ['alice', 'bob']) {
      final url =
          'https://cdn.example.com/user_avatar/linux.do/$username/72/1.png';
      final provider = AvatarCachePool.instance.imageProvider(
        url,
        logicalDiameter: 32,
        devicePixelRatio: 2,
      );
      final key = await provider.obtainKey(ImageConfiguration.empty);
      keys.add(key);
      final pixels = (await tester.runAsync(
        () => createTestImage(width: 64, height: 64, cache: false),
      ))!;
      tester.binding.imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(Future.value(ImageInfo(image: pixels))),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SmartAvatar(
              imageUrl: '/user_avatar/linux.do/$username/{size}/1.png',
              radius: 16,
              fallbackText: username,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(find.byType(Image));
      expect(await image.image.obtainKey(ImageConfiguration.empty), key);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    for (final key in keys) {
      tester.binding.imageCache.evict(key);
    }
  });
}
