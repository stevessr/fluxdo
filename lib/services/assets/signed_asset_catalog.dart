import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Verified metadata only. Hashes in an unsigned catalog are never trusted.
abstract final class SignedAssetCatalog {
  static const publicKeyBase64 = String.fromEnvironment(
    'FLUXDO_ASSET_CATALOG_ED25519_PUBKEY_B64',
  );
  static const _maxCatalogBytes = 256 * 1024;
  static const _maxZipBytes = 512 * 1024 * 1024;
  static final _hash = RegExp(r'^[a-f0-9]{64}$');
  static const _ids = <String>{
    'font-misans', 'render-cook', 'render-polyfill', 'ai-brands',
    'avatar-touhou', 'avatar-blue-archive', 'avatar-witch-judgment',
    'avatar-llm', 'avatar-stevessr',
  };

  static bool get hasPinnedKey {
    try {
      return base64Decode(publicKeyBase64).length == 32;
    } catch (_) {
      return false;
    }
  }

  /// Signature covers exact catalogBytes, including whitespace.
  /// trustedPublicKeyBase64 MUST be provisioned outside of this catalog.
  static Future<List<VerifiedAssetPack>> verify({
    required Uint8List catalogBytes,
    required Uint8List signatureBytes,
    required String trustedPublicKeyBase64,
  }) async {
    if (catalogBytes.isEmpty || catalogBytes.length > _maxCatalogBytes ||
        signatureBytes.length != 64) {
      throw const FormatException('资源目录或 Ed25519 签名长度不合法');
    }
    late final List<int> key;
    try {
      key = base64Decode(trustedPublicKeyBase64);
    } on FormatException {
      throw const FormatException('可信公钥必须为 base64');
    }
    if (key.length != 32) {
      throw const FormatException('Ed25519 公钥必须为 32 字节');
    }
    if (!await Ed25519().verify(
      catalogBytes,
      signature: Signature(
        signatureBytes,
        publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
      ),
    )) {
      throw const FormatException('资源目录签名验证失败');
    }

    final raw = jsonDecode(utf8.decode(catalogBytes));
    if (raw is! Map<String, dynamic> ||
        raw['schema'] != 1 || raw['packs'] is! List) {
      throw const FormatException('资源目录协议不兼容');
    }
    final result = <VerifiedAssetPack>[];
    final seen = <String>{};
    for (final entry in raw['packs'] as List) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('资源目录条目格式错误');
      }
      final id = entry['id'];
      final hash = entry['sha256'];
      final filename = entry['filename'];
      final length = entry['bytes'];
      if (id is! String || !_ids.contains(id) || !seen.add(id) ||
          hash is! String || !_hash.hasMatch(hash) ||
          filename is! String ||
          filename != '$id-${hash.substring(0, 16)}.zip' ||
          length is! int || length <= 0 || length > _maxZipBytes) {
        throw const FormatException('资源目录包含未知、不安全或重复条目');
      }
      result.add(VerifiedAssetPack(
        id: id, filename: filename, sha256: hash, bytes: length,
      ));
    }
    if (result.isEmpty) {
      throw const FormatException('资源目录没有可安装的包');
    }
    return List.unmodifiable(result);
  }
}

class VerifiedAssetPack {
  final String id;
  final String filename;
  final String sha256;
  final int bytes;

  const VerifiedAssetPack({
    required this.id,
    required this.filename,
    required this.sha256,
    required this.bytes,
  });
}
