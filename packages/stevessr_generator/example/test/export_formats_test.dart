import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:stevessr_generator/stevessr_generator.dart';

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
    return Uint8List.fromList(img.encodePng(image));
  }

  test('default format remains PNG and supports AVIF/JPEG', () {
    expect(StevessrRenderParams.defaults().format, StevessrFormat.png);
    expect(StevessrFormat.values, contains(StevessrFormat.avif));
    expect(StevessrFormat.values, contains(StevessrFormat.jpeg));
    expect(
      StevessrRenderParams.defaults()
          .copyWith(format: StevessrFormat.avif)
          .normalized()
          .format,
      StevessrFormat.avif,
    );
  });

  test('JPEG encoder emits decodable dimensions', () async {
    final bytes = await StevessrExportService.encodeJpegPng(
      makePng(transparent: false),
      quality: 88,
    );
    expect(bytes.sublist(0, 2), [0xff, 0xd8]);
    expect(bytes.sublist(bytes.length - 2), [0xff, 0xd9]);
    final decoded = img.decodeJpg(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 24);
    expect(decoded.height, 20);
  });

  test('JPEG encoder rejects transparent PNG input', () async {
    await expectLater(
      StevessrExportService.encodeJpegPng(
        makePng(transparent: true),
        quality: 80,
      ),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('JPEG 不支持透明像素'),
      )),
    );
  });

  test('SVG export embeds the original character art', () async {
    final params = StevessrRenderParams.defaults().copyWith(
      format: StevessrFormat.svg,
    );
    final result = await StevessrExportService.render(
      params: params,
      repaintBoundaryKey: GlobalKey(),
    );
    final svg = String.fromCharCodes(result.bytes);
    expect(result.mimeType, 'image/svg+xml');
    expect(result.extension, 'svg');
    expect(svg, startsWith('<svg'));
    expect(svg, contains('data:image/webp;base64,'));
  });

  test('WebP output is decodable and preserves alpha', () async {
    final bytes = await StevessrExportService.encodeWebpPng(
      makePng(transparent: true),
      quality: 85,
    );
    final decoded = img.decodeWebP(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 24);
    expect(decoded.getPixel(0, 0).a.toInt(), 0);
    expect(decoded.getPixel(12, 0).a.toInt(), 255);
  });

}
