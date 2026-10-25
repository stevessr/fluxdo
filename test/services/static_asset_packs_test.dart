import 'dart:convert';
import 'dart:io';

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
      '${temp.path}/render-cook-$hash/$_path',
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


  test('禁用后回退内置，回滚重启原资源包', () async {
    final bundled = await rootBundle.loadString(_path);
    final zip = _makePack(_path, Uint8List.fromList(utf8.encode('external')));
    final hash = sha256.convert(zip).toString();
    final changes = <String>[];
    final subscription = StaticAssetPacks.changes.listen(changes.add);
    addTearDown(subscription.cancel);

    await StaticAssetPacks.installTrustedZip(
      packId: 'render-cook', zipBytes: zip, expectedSha256: hash,
    );
    expect(await StaticAssetPacks.loadString(_path), 'external');
    expect(await StaticAssetPacks.listInstalled(), contains(<String, String>{
      'id': 'render-cook', 'digest': hash,
    }));
    expect(await StaticAssetPacks.disable('render-cook'), isTrue);
    expect(await StaticAssetPacks.loadString(_path), bundled);
    expect(await StaticAssetPacks.listInstalled(), isEmpty);
    expect(await StaticAssetPacks.rollback('render-cook'), isTrue);
    expect(await StaticAssetPacks.loadString(_path), 'external');
    expect(changes, ['render-cook', 'render-cook', 'render-cook']);
  });

  test('两版资源安装后可回滚，旧目录仍在', () async {
    final a = _makePack(_path, Uint8List.fromList(utf8.encode('v1')));
    final hashA = sha256.convert(a).toString();
    await StaticAssetPacks.installTrustedZip(
      packId: 'render-cook', zipBytes: a, expectedSha256: hashA,
    );
    final b = _makePack(_path, Uint8List.fromList(utf8.encode('v2')));
    final hashB = sha256.convert(b).toString();
    await StaticAssetPacks.installTrustedZip(
      packId: 'render-cook', zipBytes: b, expectedSha256: hashB,
    );
    expect(await StaticAssetPacks.loadString(_path), 'v2');
    expect(await Directory('${temp.path}/render-cook-$hashA').exists(), isTrue);
    expect(await StaticAssetPacks.rollback('render-cook'), isTrue);
    expect(await StaticAssetPacks.loadString(_path), 'v1');
  });

  test('崩溃在 current -> previous 之间仍能读取旧版本', () async {
    final zip = _makePack(_path, Uint8List.fromList(utf8.encode('stable')));
    await StaticAssetPacks.installTrustedZip(
      packId: 'render-cook',
      zipBytes: zip,
      expectedSha256: sha256.convert(zip).toString(),
    );
    await File('${temp.path}/render-cook.current.json')
        .rename('${temp.path}/render-cook.previous.json');
    expect(await StaticAssetPacks.loadString(_path), 'stable');
  });

  test('重复安装同摘要不会覆盖正在使用的目录', () async {
    final zip = _makePack(_path, Uint8List.fromList(utf8.encode('stable')));
    final hash = sha256.convert(zip).toString();
    await StaticAssetPacks.installTrustedZip(
      packId: 'render-cook', zipBytes: zip, expectedSha256: hash,
    );
    await StaticAssetPacks.installTrustedZip(
      packId: 'render-cook', zipBytes: zip, expectedSha256: hash,
    );
    expect(await StaticAssetPacks.loadString(_path), 'stable');
  });

  test('同一插件并发安装请求按锁串行执行', () async {
    final a = _makePack(_path, Uint8List.fromList(utf8.encode('alpha')));
    final b = _makePack(_path, Uint8List.fromList(utf8.encode('beta')));
    await Future.wait([
      StaticAssetPacks.installTrustedZip(
        packId: 'render-cook',
        zipBytes: a, expectedSha256: sha256.convert(a).toString(),
      ),
      StaticAssetPacks.installTrustedZip(
        packId: 'render-cook',
        zipBytes: b, expectedSha256: sha256.convert(b).toString(),
      ),
    ]);
    expect(await StaticAssetPacks.loadString(_path), 'beta');
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
