import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/stevessr_render_params.dart';
import 'package:fluxdo/services/stevessr_export_service.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List makePng({required bool transparent}) {
    final image = img.Image(width: 24, height: 20, numChannels: 4);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgba(
          x,
          y,
          100 + x,
          60 + y,
          200,
          transparent && x < 8 ? 0 : 255,
        );
      }
    }
    return img.encodePng(image);
  }

  test('generator model exposes AVIF and JPEG without changing PNG default', () {
    expect(StevessrFormat.values, contains(StevessrFormat.avif));
    expect(StevessrFormat.values, contains(StevessrFormat.jpeg));
    expect(StevessrRenderParams.defaults().format, StevessrFormat.png);
    expect(
      StevessrRenderParams.defaults()
          .copyWith(format: StevessrFormat.avif)
          .normalized()
          .format,
      StevessrFormat.avif,
    );
  });

  testWidgets('JPEG export is real JPEG with the requested pixel dimensions',
      (tester) async {
    final bytes = await tester.runAsync(
      () => StevessrExportService.encodeJpegPng(
        makePng(transparent: false),
        quality: 88,
      ),
    );
    expect(bytes, isNotNull);
    expect(bytes!.sublist(0, 2), [0xff, 0xd8]);
    expect(bytes.sublist(bytes.length - 2), [0xff, 0xd9]);
    final decoded = img.decodeJpg(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 24);
    expect(decoded.height, 20);
  });

  testWidgets('JPEG export refuses to flatten transparent PNG pixels',
      (tester) async {
    final future = tester.runAsync(
      () => StevessrExportService.encodeJpegPng(
        makePng(transparent: true),
        quality: 80,
      ),
    );
    await expectLater(
      future,
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('JPEG 不支持透明像素'),
      )),
    );
  });
}
