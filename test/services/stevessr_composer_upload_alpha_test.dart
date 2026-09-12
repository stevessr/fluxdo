import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/services/stevessr_composer_service.dart';
import 'package:fluxdo/services/stevessr_export_service.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('透明 StevesSR 上传副本保持 alpha 且压到 Discourse 安全阈值内', () async {
    final source = _largeTransparentPng();
    expect(source.length, greaterThan(72 * 1024));

    final prepared =
        await StevessrComposerService.prepareTransparentUploadForTesting(
          StevessrExportedImage(
            bytes: source,
            extension: 'png',
            mimeType: 'image/png',
          ),
        );

    expect(prepared.extension, 'png');
    expect(prepared.mimeType, 'image/png');
    expect(prepared.bytes.length, lessThanOrEqualTo(72 * 1024));

    final decoded = img.decodePng(prepared.bytes);
    expect(decoded, isNotNull);
    expect(decoded!.hasAlpha, isTrue);
    expect(decoded.getPixel(0, 0).a.toInt(), 0);
  });

  test('服务端仍转 JPEG 时用更小透明 PNG 重试而不是插入白底图', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'fluxdo-stevessr-alpha-',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final uploadedPaths = <String>[];
    final uploadedSizes = <int>[];
    var attempt = 0;

    Future<UploadResult> fakeUpload(String path) async {
      uploadedPaths.add(path);
      uploadedSizes.add(await File(path).length());
      attempt++;
      if (attempt == 1) {
        return UploadResult(
          shortUrl: 'upload://flattened',
          url: 'https://example.test/flattened.jpg',
          originalFilename: 'flattened.jpg',
          extension: 'jpg',
        );
      }
      return UploadResult(
        shortUrl: 'upload://transparent',
        url: 'https://example.test/transparent.png',
        originalFilename: 'transparent.png',
        extension: 'png',
      );
    }

    final result = await StevessrComposerService.uploadForTesting(
      StevessrExportedImage(
        bytes: _largeTransparentPng(),
        extension: 'png',
        mimeType: 'image/png',
      ),
      uploadFile: fakeUpload,
      temporaryDirectory: () async => tempDir,
    );

    expect(attempt, 2);
    expect(result.upload.extension, 'png');
    expect(result.path, uploadedPaths.last);
    expect(uploadedSizes.first, lessThanOrEqualTo(72 * 1024));
    expect(uploadedSizes.last, lessThanOrEqualTo(48 * 1024));

    final retried = img.decodePng(await File(result.path).readAsBytes());
    expect(retried, isNotNull);
    expect(retried!.getPixel(0, 0).a.toInt(), 0);
  });

  test('两次都被服务端转 JPEG 时拒绝插入', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'fluxdo-stevessr-alpha-reject-',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    var attempt = 0;
    Future<UploadResult> fakeUpload(String path) async {
      attempt++;
      return UploadResult(
        shortUrl: 'upload://flattened-$attempt',
        url: 'https://example.test/flattened-$attempt.jpg',
        originalFilename: 'flattened-$attempt.jpg',
        extension: 'jpg',
      );
    }

    await expectLater(
      StevessrComposerService.uploadForTesting(
        StevessrExportedImage(
          bytes: _largeTransparentPng(),
          extension: 'png',
          mimeType: 'image/png',
        ),
        uploadFile: fakeUpload,
        temporaryDirectory: () async => tempDir,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('避免透明区域变白'),
        ),
      ),
    );
    expect(attempt, 2);
  });
}

Uint8List _largeTransparentPng() {
  final image = img.Image(width: 512, height: 512, numChannels: 4);
  var state = 0x12345678;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      state = (state * 1664525 + 1013904223) & 0xffffffff;
      final r = state & 0xff;
      final g = (state >> 8) & 0xff;
      final b = (state >> 16) & 0xff;
      final a = x < 12 && y < 12 ? 0 : 255;
      image.setPixelRgba(x, y, r, g, b, a);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}
