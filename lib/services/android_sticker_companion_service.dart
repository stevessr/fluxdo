import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'stevessr_export_service.dart';

/// Android-only signed, standalone Flutter companion. Does not expose the
/// Discourse session, tokens, cookies, or private paths to another process.
abstract final class AndroidStickerCompanionService {
  static const _channel = MethodChannel(
    'com.github.lingyan000.fluxdo/sticker_companion',
  );

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> isAvailable() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Null means user cancelled. Exceptions are real transport/validation
  /// failures and must not silently reopen the in-process generator.
  static Future<StevessrExportedImage?> generate() async {
    if (!supported) throw UnsupportedError('Only Android supports companion APKs');
    final response = await _channel.invokeMapMethod<String, dynamic>('generate');
    if (response == null) return null;
    final bytes = response['bytes'];
    final mime = response['mimeType'];
    final extension = response['extension'];
    const supportedTypes = {
      'png': 'image/png',
      'webp': 'image/webp',
      'avif': 'image/avif',
      'jpg': 'image/jpeg',
      'svg': 'image/svg+xml',
    };
    if (bytes is! Uint8List || extension is! String ||
        mime != supportedTypes[extension] || bytes.isEmpty) {
      throw const FormatException('Invalid image returned by sticker APK');
    }
    return StevessrExportedImage(
      bytes: bytes,
      extension: extension,
      mimeType: mime as String,
    );
  }
}
