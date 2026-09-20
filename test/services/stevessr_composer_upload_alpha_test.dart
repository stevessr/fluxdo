import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/services/stevessr_composer_service.dart';
import 'package:fluxdo/services/stevessr_export_service.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('透明 StevesSR 上传保持原字节、原尺寸和原扩展名', () async {
    // Must remain larger than the old, incorrect 72 KiB conversion workaround.
    final tempDir = await Directory.systemTemp.createTemp(
      'fluxdo-stevessr-alpha-original-',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final source = _largeTransparentPng();
    expect(source.length, greaterThan(72 * 1024));
    Uint8List? uploadedBytes;
    String? uploadedPath;
    bool? preserveImageFormat;

    Future<UploadResult> fakeUpload(
      String path,
      bool shouldPreserveImageFormat,
    ) async {
      uploadedPath = path;
      uploadedBytes = await File(path).readAsBytes();
      preserveImageFormat = shouldPreserveImageFormat;
      return UploadResult(
        shortUrl: 'upload://transparent',
        url: 'https://example.test/transparent.png',
        originalFilename: 'transparent.png',
        extension: 'png',
      );
    }

    final result = await StevessrComposerService.uploadForTesting(
      StevessrExportedImage(
        bytes: source,
        extension: 'png',
        mimeType: 'image/png',
      ),
      uploadFile: fakeUpload,
      temporaryDirectory: () async => tempDir,
    );

    expect(preserveImageFormat, isTrue);
    expect(uploadedPath, endsWith('.png'));
    expect(uploadedBytes, orderedEquals(source));
    expect(result.path, uploadedPath);

    final decoded = img.decodePng(uploadedBytes!);
    expect(decoded, isNotNull);
    expect(decoded!.width, 512);
    expect(decoded.height, 512);
    expect(decoded.getPixel(0, 0).a.toInt(), 0);
  });

  test('透明 raster 不再被上传层固定改写成 PNG', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'fluxdo-stevessr-alpha-format-',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    // 这里复用可解码的 alpha fixture，测试关注 composer 是否改写导出结果；
    // 真正的 WebP 编码由 StevessrExportService 负责。
    final source = _largeTransparentPng();
    Uint8List? uploadedBytes;
    String? uploadedPath;
    bool? preserveImageFormat;

    Future<UploadResult> fakeUpload(
      String path,
      bool shouldPreserveImageFormat,
    ) async {
      uploadedPath = path;
      uploadedBytes = await File(path).readAsBytes();
      preserveImageFormat = shouldPreserveImageFormat;
      return UploadResult(
        shortUrl: 'upload://transparent-webp',
        url: 'https://example.test/transparent.webp',
        originalFilename: 'transparent.webp',
        extension: 'webp',
      );
    }

    await StevessrComposerService.uploadForTesting(
      StevessrExportedImage(
        bytes: source,
        extension: 'webp',
        mimeType: 'image/webp',
      ),
      uploadFile: fakeUpload,
      temporaryDirectory: () async => tempDir,
    );

    expect(preserveImageFormat, isTrue);
    expect(uploadedPath, endsWith('.webp'));
    expect(uploadedBytes, orderedEquals(source));
  });

  test('透明 AVIF 上传保留原始格式和字节，拒绝服务端 JPEG 回退', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'fluxdo-stevessr-avif-upload-',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    // Upload tests exercise the format/metadata path, not native AVIF encoding.
    final source = Uint8List.fromList([
      0, 0, 0, 20, 0x66, 0x74, 0x79, 0x70,
      0x61, 0x76, 0x69, 0x66, 0, 0, 0, 0,
      0x61, 0x76, 0x69, 0x66,
    ]);
    var calls = 0;
    await expectLater(
      StevessrComposerService.uploadForTesting(
        StevessrExportedImage(
          bytes: source,
          extension: 'avif',
          mimeType: 'image/avif',
          containsTransparency: true,
        ),
        uploadFile: (path, preserveImageFormat) async {
          calls++;
          expect(path, endsWith('.avif'));
          expect(await File(path).readAsBytes(), orderedEquals(source));
          expect(preserveImageFormat, isTrue);
          return UploadResult(
            shortUrl: 'upload://avif-jpeg-reencode',
            url: 'https://example.test/avif-jpeg-reencode.jpg',
            originalFilename: 'avif-jpeg-reencode.jpg',
            extension: 'jpg',
          );
        },
        temporaryDirectory: () async => tempDir,
      ),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('避免透明区域变白'),
      )),
    );
    expect(calls, 1);
  });

  test('不透明 AVIF 也要求站点保留上传格式', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'fluxdo-stevessr-avif-opaque-',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    bool? preserveImageFormat;
    await StevessrComposerService.uploadForTesting(
      StevessrExportedImage(
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        extension: 'avif',
        mimeType: 'image/avif',
        containsTransparency: false,
      ),
      uploadFile: (path, preserve) async {
        preserveImageFormat = preserve;
        expect(path, endsWith('.avif'));
        return UploadResult(
          shortUrl: 'upload://opaque-avif',
          url: 'https://example.test/opaque.avif',
          originalFilename: 'opaque.avif',
          extension: 'avif',
        );
      },
      temporaryDirectory: () async => tempDir,
    );
    expect(preserveImageFormat, isTrue);
  });

  test('不透明图片继续走普通 composer 上传路径', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'fluxdo-stevessr-opaque-',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    bool? preserveImageFormat;
    Future<UploadResult> fakeUpload(
      String path,
      bool shouldPreserveImageFormat,
    ) async {
      preserveImageFormat = shouldPreserveImageFormat;
      return UploadResult(
        shortUrl: 'upload://opaque',
        url: 'https://example.test/opaque.png',
        originalFilename: 'opaque.png',
        extension: 'png',
      );
    }

    await StevessrComposerService.uploadForTesting(
      StevessrExportedImage(
        bytes: _opaquePng(),
        extension: 'png',
        mimeType: 'image/png',
      ),
      uploadFile: fakeUpload,
      temporaryDirectory: () async => tempDir,
    );

    expect(preserveImageFormat, isFalse);
  });

  test('服务端仍把透明图片转 JPEG 时拒绝插入且不做低清重试', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'fluxdo-stevessr-alpha-reject-',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final source = _largeTransparentPng();
    var attempt = 0;
    bool? preserveImageFormat;
    Uint8List? uploadedBytes;

    Future<UploadResult> fakeUpload(
      String path,
      bool shouldPreserveImageFormat,
    ) async {
      attempt++;
      preserveImageFormat = shouldPreserveImageFormat;
      uploadedBytes = await File(path).readAsBytes();
      return UploadResult(
        shortUrl: 'upload://flattened',
        url: 'https://example.test/flattened.jpg',
        originalFilename: 'flattened.jpg',
        extension: 'jpg',
      );
    }

    await expectLater(
      StevessrComposerService.uploadForTesting(
        StevessrExportedImage(
          bytes: source,
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

    expect(attempt, 1);
    expect(preserveImageFormat, isTrue);
    expect(uploadedBytes, orderedEquals(source));
  });
  test('4 MiB 或更大的生成图明确拒绝，且不会压缩、写盘或发起上传', () async {
    for (final extraByte in <int>[0, 1]) {
      final source = Uint8List(
        StevessrComposerService.maxGeneratorUploadBytes + extraByte,
      );
      await expectLater(
        StevessrComposerService.uploadForTesting(
          StevessrExportedImage(
            bytes: source,
            extension: 'png',
            mimeType: 'image/png',
          ),
          uploadFile: (path, preserveImageFormat) async {
            throw AssertionError('Oversized images must not be uploaded');
          },
          temporaryDirectory: () async {
            throw AssertionError(
              'Oversized images must not be written to disk',
            );
          },
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('4 MB'),
          ),
        ),
      );
      expect(
        source.length,
        greaterThanOrEqualTo(StevessrComposerService.maxGeneratorUploadBytes),
      );
    }
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

Uint8List _opaquePng() {
  final image = img.Image(width: 64, height: 64, numChannels: 4);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgba(x, y, 20, 40, 60, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}
