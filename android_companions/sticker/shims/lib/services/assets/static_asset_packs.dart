import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Sticker owns its bundled character assets and upgrades them with its APK.
///
/// This adapter also supports the versioned character loader from the asset
/// pack branch. It must not import the host's installer, trust store or files.
abstract final class StaticAssetPacks {
  static const Stream<String> changes = Stream<String>.empty();

  static Future<Uint8List> loadBytes(String path) async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static Future<String> loadString(String path) => rootBundle.loadString(path);
}
