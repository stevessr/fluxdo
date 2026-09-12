import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/screenshot_utils.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('分块 PNG 截图保留透明 alpha 通道', (tester) async {
    tester.view.physicalSize = const Size(32, 4101);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: boundaryKey,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();

    final bytes = await tester.runAsync(
      () => ScreenshotUtils.captureWidget(boundaryKey, pixelRatio: 1),
    );
    final png = bytes == null ? null : img.decodePng(bytes);

    expect(bytes, isNotNull);
    expect(png, isNotNull);
    expect(png!.height, 4101);
    expect(png.numChannels, 4);
    expect(png.getPixel(0, 0).a.toInt(), 0);
    expect(png.getPixel(0, 4100).a.toInt(), 0);
  });
}
