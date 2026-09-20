import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/stevessr_export_service.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List sourcePng({required bool transparent}) {
    final image = img.Image(width: 32, height: 32, numChannels: 4);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgba(
          x,
          y,
          235,
          40 + x,
          90 + y,
          transparent && x < 12 ? 0 : 255,
        );
      }
    }
    return img.encodePng(image);
  }

  testWidgets('WebP 导出为真实的 RIFF/WebP，保留透明区域与尺寸', (tester) async {
    final webp = await tester.runAsync(
      () => StevessrExportService.encodeWebpPng(
        sourcePng(transparent: true),
        quality: 85,
      ),
    );
    expect(webp, isNotNull);
    expect(webp!.sublist(0, 4), [0x52, 0x49, 0x46, 0x46]); // RIFF
    expect(webp.sublist(8, 12), [0x57, 0x45, 0x42, 0x50]); // WEBP
    final decoded = img.decodeWebP(webp);
    expect(decoded, isNotNull);
    expect(decoded!.width, 32);
    expect(decoded.height, 32);
    expect(decoded.getPixel(0, 0).a.toInt(), 0);
    expect(decoded.getPixel(31, 31).a.toInt(), 255);
  });

  testWidgets('100 质量导出使用无损编码并保持 RGBA', (tester) async {
    final png = sourcePng(transparent: true);
    final webp = await tester.runAsync(
      () => StevessrExportService.encodeWebpPng(png, quality: 100),
    );
    expect(webp, isNotNull);
    final before = img.decodePng(png)!;
    final after = img.decodeWebP(webp!)!;
    for (final (x, y) in <(int, int)>[(0, 0), (12, 0), (31, 31)]) {
      final expected = before.getPixel(x, y);
      final actual = after.getPixel(x, y);
      expect(
        [
          actual.r.toInt(),
          actual.g.toInt(),
          actual.b.toInt(),
          actual.a.toInt(),
        ],
        [
          expected.r.toInt(),
          expected.g.toInt(),
          expected.b.toInt(),
          expected.a.toInt(),
        ],
      );
    }
  });

  testWidgets('不透明 PNG 也可以导出 WebP', (tester) async {
    final webp = await tester.runAsync(
      () => StevessrExportService.encodeWebpPng(
        sourcePng(transparent: false),
        quality: 75,
      ),
    );
    expect(webp, isNotNull);
    final decoded = img.decodeWebP(webp!);
    expect(decoded, isNotNull);
    expect(decoded!.getPixel(0, 0).a.toInt(), 255);
  });
}
