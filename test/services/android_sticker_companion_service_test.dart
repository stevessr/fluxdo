import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/android_sticker_companion_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(
    'com.github.lingyan000.fluxdo/sticker_companion',
  );

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('missing signed companion is reported unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (method) async {
      expect(method.method, 'available');
      return false;
    });
    expect(await AndroidStickerCompanionService.isAvailable(), false);
  });

  test('cancelled independent generator does not create an upload', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (method) async {
      expect(method.method, 'generate');
      return null;
    });
    expect(await AndroidStickerCompanionService.generate(), isNull);
  });

  test('signed companion image is returned with original encoding', () async {
    final bytes = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => {
          'bytes': bytes,
          'mimeType': 'image/png',
          'extension': 'png',
        });
    final image = await AndroidStickerCompanionService.generate();
    expect(image?.extension, 'png');
    expect(image?.mimeType, 'image/png');
    expect(image?.bytes, bytes);
  });

  test('mismatched extension and MIME cannot enter upload pipeline', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => {
          'bytes': Uint8List.fromList([1, 2, 3]),
          'mimeType': 'image/jpeg',
          'extension': 'png',
        });
    expect(
      AndroidStickerCompanionService.generate(),
      throwsA(isA<FormatException>()),
    );
  });
}
