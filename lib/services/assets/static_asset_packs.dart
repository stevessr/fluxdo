import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'signed_asset_catalog.dart';
import 'static_asset_pack_backend_stub.dart'
    if (dart.library.io) 'static_asset_pack_backend_io.dart' as backend;

/// 本地可信资源包优先；未安装或校验失败时回退 Flutter assets。
abstract final class StaticAssetPacks {
  static final _changes = StreamController<String>.broadcast(sync: true);

  /// 已验证的激活/回滚/禁用会同步通知消费者丢弃缓存。
  static Stream<String> get changes => _changes.stream;

  /// 只读取独立安装的包，不会回退内置资源。用于外置字体等可选功能。
  static Future<Uint8List?> loadInstalledBytes(String assetPath) =>
      backend.readVerifiedAsset(assetPath);

  static Future<List<Map<String, String>>> listInstalled() =>
      backend.listInstalledPacks();

  /// 只回收无效历史目录；当前/上一版不会删除，Web 上返回 0。
  static Future<int> pruneUnused() => backend.pruneUnusedPacks();

  static Future<bool> rollback(String packId) async {
    final changed = await backend.rollbackPack(packId);
    if (changed) _changes.add(packId);
    return changed;
  }

  static Future<bool> disable(String packId) async {
    final changed = await backend.disablePack(packId);
    if (changed) _changes.add(packId);
    return changed;
  }

  static Future<Uint8List> loadBytes(String assetPath) async {
    final installed = await backend.readVerifiedAsset(assetPath);
    if (installed != null) return installed;
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static Future<String> loadString(String assetPath) async {
    final installed = await backend.readVerifiedAsset(assetPath);
    if (installed == null) return rootBundle.loadString(assetPath);
    // 大型 JS 在 isolate 中解码，保留 rootBundle.loadString 的性能特征。
    if (installed.length > 50 * 1024) return compute(_decodeUtf8, installed);
    return utf8.decode(installed);
  }

  /// Never derive publisher trust from a ZIP or an unsigned catalog.
  static Future<void> installFromPinnedCatalog({
    required String packId,
    required Uint8List catalogBytes,
    required Uint8List signatureBytes,
    required Uint8List zipBytes,
  }) async {
    if (!SignedAssetCatalog.hasPinnedKey) {
      throw StateError('未内置可信的资源目录 Ed25519 公钥');
    }
    final entries = await SignedAssetCatalog.verify(
      catalogBytes: catalogBytes,
      signatureBytes: signatureBytes,
      trustedPublicKeyBase64: SignedAssetCatalog.publicKeyBase64,
    );
    final found = entries.where((item) => item.id == packId).toList();
    if (found.length != 1) {
      throw const FormatException('签名目录不包含该资源包');
    }
    final item = found.single;
    if (zipBytes.length != item.bytes) {
      throw const FormatException('ZIP 大小与签名目录不匹配');
    }
    await installTrustedZip(
      packId: packId, zipBytes: zipBytes, expectedSha256: item.sha256,
    );
  }

  /// expectedSha256 必须来自可信发布渠道，不得从待安装 ZIP 自身读取。
  static Future<void> installTrustedZip({
    required String packId,
    required Uint8List zipBytes,
    required String expectedSha256,
  }) async {
    await backend.installTrustedZip(
      packId: packId,
      zipBytes: zipBytes,
      expectedSha256: expectedSha256,
    );
    _changes.add(packId);
  }
}

String _decodeUtf8(Uint8List bytes) => utf8.decode(bytes);
