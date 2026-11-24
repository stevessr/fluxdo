import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/modules/mini_apps/mini_app.dart';
import 'package:fluxdo/modules/mini_apps/mini_app_card_surface.dart';
import 'package:fluxdo/modules/mini_apps/mini_app_icon.dart';
import 'package:fluxdo/services/discourse_cache_manager.dart';
import 'package:fluxdo/utils/url_helper.dart';
import 'package:fluxdo/modules/mini_apps/mini_app_runtime_surface.dart';

void main() {
  testWidgets('relative mini app artwork uses the resolved cached image', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    UrlHelper.debugSetOverrides(baseUri: '', cdnUrl: 'https://cdn.example.com');
    addTearDown(UrlHelper.debugClearOverrides);
    const url = 'https://cdn.example.com/uploads/default/app.png?v=2';
    final provider = sharedImageProvider(url, cacheWidth: 44, cacheHeight: 44);
    final key = await provider.obtainKey(ImageConfiguration.empty);
    final pixels = (await tester.runAsync(
      () => createTestImage(width: 44, height: 44, cache: false),
    ))!;
    tester.binding.imageCache.putIfAbsent(
      key,
      () => OneFrameImageStreamCompleter(Future.value(ImageInfo(image: pixels))),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: MiniAppIcon(
            MiniApp(
              id: 'relative',
              name: 'App',
              iconUrl: '/uploads/default/app.png?v=2',
            ),
            size: 44,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(find.byType(Image));
    expect(await image.image.obtainKey(ImageConfiguration.empty), key);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.imageCache.evict(key);
  });

  testWidgets('启动图标的渐变底座与图片一同裁为正圆', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: const MiniAppLaunchSurface(
              app: MiniApp(id: 'launch-circle', name: '应用'),
              failed: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final base = find.ancestor(
      of: find.byType(MiniAppCardSurface),
      matching: find.byType(ClipOval),
    );
    expect(base, findsOneWidget);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final origin = tester.getTopLeft(base) - tester.getTopLeft(find.byKey(key));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        ))!;
        final pixels = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        List<int> pixel(int x, int y) => pixels.sublist(
          (y * image.width + x) * 4,
          (y * image.width + x) * 4 + 4,
        );
        final background = pixel(0, 0);
        expect(
          pixel(origin.dx.round() + 12, origin.dy.round() + 12),
          background,
        );
        expect(
          pixel(origin.dx.round() + 52, origin.dy.round() + 4),
          isNot(background),
        );
      } finally {
        image.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  });

  for (final size in [28.0, 56.0, 96.0]) {
    testWidgets('小程序首字与空名称占位在 $size 尺寸下保持正圆', (tester) async {
      final key = GlobalKey();
      for (final name in ['应用', '']) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: RepaintBoundary(
                key: key,
                child: MiniAppIcon(
                  MiniApp(id: 'circle', name: name),
                  size: size,
                ),
              ),
            ),
          ),
        );
        expect(
          find.descendant(
            of: find.byType(MiniAppIcon),
            matching: find.byType(ClipOval),
          ),
          findsOneWidget,
        );
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final data = await image.toByteData(
              format: ui.ImageByteFormat.rawStraightRgba,
            );
            final pixels = data!.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            );
            final outside = (size / 8).floor();
            final inside = (size / 4).floor();
            expect(image.width, size.toInt());
            expect(image.height, size.toInt());
            expect(pixels[(outside * image.width + outside) * 4 + 3], 0);
            expect(pixels[(inside * image.width + inside) * 4 + 3], 255);
          } finally {
            image.dispose();
          }
        });
      }
    });
  }
}
