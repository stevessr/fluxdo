import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/assets/signed_asset_catalog.dart';
import 'package:fluxdo/services/assets/static_asset_packs.dart';
import 'package:fluxdo/services/assets/static_asset_pack_backend_io.dart' as backend;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fixture = 'test/fixtures/generated_asset_packs';
  final hasFixture = File('$fixture/catalog.sig').existsSync();

  test('OpenSSL Ed25519 签名目录与 Dart 验证器互通', () async {
    final catalog = await File('$fixture/catalog.json').readAsBytes();
    final signature = await File('$fixture/catalog.sig').readAsBytes();
    final spki = await File('$fixture/ci-test-public.der').readAsBytes();
    // DER SubjectPublicKeyInfo prefix for Ed25519 (RFC 8410).
    const prefix = <int>[0x30, 0x2a, 0x30, 0x05, 0x06, 0x03,
      0x2b, 0x65, 0x70, 0x03, 0x21, 0x00];
    expect(spki.length, 44);
    expect(spki.sublist(0, prefix.length), prefix);
    final publicKey = base64Encode(spki.sublist(prefix.length));
    final packs = await SignedAssetCatalog.verify(
      catalogBytes: Uint8List.fromList(catalog),
      signatureBytes: Uint8List.fromList(signature),
      trustedPublicKeyBase64: publicKey,
    );
    expect(packs, hasLength(1));
    final pack = packs.single;
    expect(pack.id, 'render-cook');
    expect(pack.releaseSequence, 1);
    final actualZip = await File('$fixture/${pack.filename}').readAsBytes();
    expect(actualZip.length, pack.bytes);

    final tamperedSignature = Uint8List.fromList(signature);
    tamperedSignature[0] ^= 1;
    await expectLater(
      SignedAssetCatalog.verify(
        catalogBytes: Uint8List.fromList(catalog),
        signatureBytes: tamperedSignature,
        trustedPublicKeyBase64: publicKey,
      ),
      throwsFormatException,
    );
    final tamperedCatalog = Uint8List.fromList([...catalog, 0x20]);
    await expectLater(
      SignedAssetCatalog.verify(
        catalogBytes: tamperedCatalog,
        signatureBytes: Uint8List.fromList(signature),
        trustedPublicKeyBase64: publicKey,
      ),
      throwsFormatException,
    );
    final wrongKey = List<int>.from(spki.sublist(prefix.length));
    wrongKey[0] ^= 1;
    await expectLater(
      SignedAssetCatalog.verify(
        catalogBytes: Uint8List.fromList(catalog),
        signatureBytes: Uint8List.fromList(signature),
        trustedPublicKeyBase64: base64Encode(wrongKey),
      ),
      throwsFormatException,
    );
  }, skip: !hasFixture);

  test('应用只依据编译期钉住的公钥安装真实签名 ZIP', () async {
    expect(SignedAssetCatalog.hasPinnedKey, isTrue);
    final root = await Directory.systemTemp.createTemp('signed-catalog-test-');
    backend.testAssetPackStoreRoot = root;
    try {
      final catalog = await File('$fixture/catalog.json').readAsBytes();
      final signature = await File('$fixture/catalog.sig').readAsBytes();
      final record = (jsonDecode(utf8.decode(catalog)) as Map<String, dynamic>);
      final pack = (record['packs'] as List).single as Map<String, dynamic>;
      final zip = await File('$fixture/${pack['filename']}').readAsBytes();
      await StaticAssetPacks.installFromPinnedCatalog(
        packId: 'render-cook',
        catalogBytes: Uint8List.fromList(catalog),
        signatureBytes: Uint8List.fromList(signature),
        zipBytes: Uint8List.fromList(zip),
      );
      expect((await StaticAssetPacks.listInstalled()).single['id'], 'render-cook');
      final poisoned = Uint8List.fromList(zip)..[0] ^= 1;
      await expectLater(
        StaticAssetPacks.installFromPinnedCatalog(
          packId: 'render-cook',
          catalogBytes: Uint8List.fromList(catalog),
          signatureBytes: Uint8List.fromList(signature),
          zipBytes: poisoned,
        ),
        throwsFormatException,
      );
      expect((await StaticAssetPacks.listInstalled()).single['id'], 'render-cook');
    } finally {
      backend.testAssetPackStoreRoot = null;
      await root.delete(recursive: true);
    }
  }, skip: !hasFixture);

  test('未内置发行公钥时拒绝目录驱动的资源安装', () async {
    if (SignedAssetCatalog.hasPinnedKey) return;
    await expectLater(
      StaticAssetPacks.installFromPinnedCatalog(
        packId: 'render-cook',
        catalogBytes: Uint8List.fromList([]),
        signatureBytes: Uint8List.fromList([]),
        zipBytes: Uint8List.fromList([]),
      ),
      throwsStateError,
    );
  });
}
