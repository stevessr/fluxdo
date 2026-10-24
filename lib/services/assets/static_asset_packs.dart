import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'static_asset_pack_backend_stub.dart'
    if (dart.library.io) 'static_asset_pack_backend_io.dart' as backend;

/// 本地可信资源包优先；未安装或校验失败时回退 Flutter assets。
abstract final class StaticAssetPacks {
  static Future<Uint8List> loadBytes(String assetPath) async {
    final installed = await backend.readVerifiedAsset(assetPath);
    if (installed != null) return installed;
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static Future<String> loadString(String assetPath) async {
    return utf8.decode(await loadBytes(assetPath));
  }

  /// expectedSha256 必须来自可信发布渠道，不得从待安装 ZIP 自身读取。
  static Future<void> installTrustedZip({
    required String packId,
    required Uint8List zipBytes,
    required String expectedSha256,
  }) => backend.installTrustedZip(
    packId: packId,
    zipBytes: zipBytes,
    expectedSha256: expectedSha256,
  );
}
