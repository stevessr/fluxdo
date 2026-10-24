import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/assets/static_asset_pack_backend_io.dart'
    as backend;
import 'package:fluxdo/services/assets/static_asset_packs.dart';

const _path = 'assets/cook/discourse-cook.js';

Uint8List _makePack(String filename, Uint8List contents) {
  final manifest = {
    'schema': 1,
    'id': 'render-cook',
    'files': [
      {
        'path': filename,
        'sha256': sha256.convert(contents).toString(),
        'bytes': contents.length,
      },
    ],
  };
  final archive = Archive()
    ..addFile(ArchiveFile.bytes('manifest.json', utf8.encode(jsonEncode(manifest))))
    ..addFile(ArchiveFile.bytes(filename, contents));
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fluxdo-pack-test-');
    backend.testAssetPackStoreRoot = temp;
  });
  tearDown(() async {
    backend.testAssetPackStoreRoot = null;
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('未安装外部包时 Cook JS 回退到内置 assets', () async {
    final original = await rootBundle.loadString(_path);
    expect(original, isNotEmpty);
    expect(await StaticAssetPacks.loadString(_path), original);
  });

  test('可信 ZIP 可安装，篡改本地内容会自动回退', () async {
    final original = await rootBundle.loadString(_path);
    final contents = Uint8List.fromList(utf8.encode('globalThis.verified = true;'));
    final zip = _makePack(_path, contents);
    final hash = sha256.convert(zip).toString();
    await StaticAssetPacks.installTrustedZip(
      packId: 'render-cook',
      zipBytes: zip,
      expectedSha256: hash,
    );
    expect(await StaticAssetPacks.loadString(_path), utf8.decode(contents));

    final file = File(
      temp.path + '/render-cook-' + hash + '/' + _path,
    );
    await file.writeAsString('tampered');
    expect(await StaticAssetPacks.loadString(_path), original);
  });

  test('错误的外部可信散列不能替换已安装资源包', () async {
    final zip = _makePack(_path, Uint8List.fromList(utf8.encode('trusted')));
    final hash = sha256.convert(zip).toString();
    await StaticAssetPacks.installTrustedZip(
      packId: 'render-cook',
      zipBytes: zip,
      expectedSha256: hash,
    );
    await expectLater(
      StaticAssetPacks.installTrustedZip(
        packId: 'render-cook',
        zipBytes: _makePack(_path, Uint8List.fromList(utf8.encode('malicious'))),
        expectedSha256: hash,
      ),
      throwsFormatException,
    );
    expect(await StaticAssetPacks.loadString(_path), 'trusted');
  });

  test('路径逃逸即使具有匹配的 ZIP 散列仍会拒绝安装', () async {
    final zip = _makePack(
      'assets/cook/../evil.js',
      Uint8List.fromList(utf8.encode('bad')),
    );
    await expectLater(
      StaticAssetPacks.installTrustedZip(
        packId: 'render-cook',
        zipBytes: zip,
        expectedSha256: sha256.convert(zip).toString(),
      ),
      throwsFormatException,
    );
  });
}
