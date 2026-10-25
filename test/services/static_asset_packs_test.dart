import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/assets/static_asset_pack_backend_io.dart'
    as backend;
import 'package:fluxdo/services/assets/static_asset_packs.dart';
import 'package:fluxdo/services/discourse_cook_service.dart';

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
    final installed = await StaticAssetPacks.listInstalled();
    expect(installed, hasLength(1));
    expect(installed.single['id'], 'render-cook');
    expect(installed.single['digest'], hash);
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

  test('Python 生成的真实 Cook ZIP 与 Dart 安装器协议兼容', () async {
    final catalog = jsonDecode(
      await File('test/fixtures/generated_asset_packs/catalog.json').readAsString(),
    ) as Map<String, dynamic>;
    final pack = (catalog['packs'] as List).single as Map<String, dynamic>;
    expect(pack['id'], 'render-cook');
    final content = await File(
      'test/fixtures/generated_asset_packs/${pack['filename']}',
    ).readAsBytes();
    await StaticAssetPacks.installTrustedZip(
      packId: 'render-cook',
      zipBytes: content,
      expectedSha256: pack['sha256'] as String,
    );
    expect(await StaticAssetPacks.loadString(_path), await rootBundle.loadString(_path));
  }, skip: !File('test/fixtures/generated_asset_packs/catalog.json').existsSync());

  test('ZIP 中央目录声明异常压缩比时在解压前拒绝', () async {
    final input = Uint8List.fromList(
      List<int>.generate(10000, (index) => index % 251),
    );
    final zip = _makePack(_path, input);
    var entry = -1;
    for (var i = 0; i < zip.length - 46; i++) {
      if (zip[i] == 0x50 && zip[i + 1] == 0x4b &&
          zip[i + 2] == 0x01 && zip[i + 3] == 0x02) {
        entry = i;
        break;
      }
    }
    expect(entry, greaterThanOrEqualTo(0));
    // Announce one compressed byte for a 10 KiB uncompressed payload.
    for (var i = 0; i < 4; i++) {
      zip[entry + 20 + i] = i == 0 ? 1 : 0;
    }
    await expectLater(
      StaticAssetPacks.installTrustedZip(
        packId: 'render-cook', zipBytes: zip,
        expectedSha256: sha256.convert(zip).toString(),
      ),
      throwsFormatException,
    );
  });

  test('篡改 ZIP 中央目录为超大文件会在解压前拒绝', () async {
    final zip = _makePack(_path, Uint8List.fromList(utf8.encode('small')));
    var entry = -1;
    for (var i = 0; i < zip.length - 46; i++) {
      if (zip[i] == 0x50 && zip[i + 1] == 0x4b &&
          zip[i + 2] == 0x01 && zip[i + 3] == 0x02) {
        entry = i;
        break;
      }
    }
    expect(entry, greaterThanOrEqualTo(0));
    for (var i = 0; i < 4; i++) {
      zip[entry + 24 + i] = 0xff;
    }
    await expectLater(
      StaticAssetPacks.installTrustedZip(
        packId: 'render-cook',
        zipBytes: zip,
        expectedSha256: sha256.convert(zip).toString(),
      ),
      throwsFormatException,
    );
  });


  test('空间回收仅删除第三旧版本，保留当前和上一版', () async {
    final hashes = <String>[];
    for (final value in ['one', 'two', 'three']) {
      final zip = _makePack(
        _path, Uint8List.fromList(utf8.encode(value)),
      );
      final hash = sha256.convert(zip).toString();
      hashes.add(hash);
      await StaticAssetPacks.installTrustedZip(
        packId: 'render-cook', zipBytes: zip, expectedSha256: hash,
      );
    }
    final first = Directory('${temp.path}/render-cook-${hashes[0]}');
    final second = Directory('${temp.path}/render-cook-${hashes[1]}');
    final third = Directory('${temp.path}/render-cook-${hashes[2]}');
    expect(await first.exists(), isTrue);
    expect(await backend.pruneUnusedPacks(minAge: Duration.zero),
        greaterThan(0));
    expect(await first.exists(), isFalse);
    expect(await second.exists(), isTrue);
    expect(await third.exists(), isTrue);
    expect(await StaticAssetPacks.loadString(_path), 'three');
    expect(await StaticAssetPacks.rollback('render-cook'), isTrue);
    expect(await StaticAssetPacks.loadString(_path), 'two');
  });

  test('无有效激活指针时不会主动删除孤立资源目录', () async {
    final zip = _makePack(_path, Uint8List.fromList(utf8.encode('stable')));
    final hash = sha256.convert(zip).toString();
    await StaticAssetPacks.installTrustedZip(
      packId: 'render-cook', zipBytes: zip, expectedSha256: hash,
    );
    await File('${temp.path}/render-cook.current.json').delete();
    expect(await backend.pruneUnusedPacks(minAge: Duration.zero), 0);
    expect(await Directory('${temp.path}/render-cook-$hash').exists(),
        isTrue);
  });

  test('签名资源序号不可降级，回滚/禁用后仍记录最高序号', () async {
    // ZIP header timestamps can vary between separate encodings; use the
    // same bytes when simulating a re-download of the same signed release.
    final zipCache = <String, Uint8List>{};
    Future<void> signed(String value, int sequence) async {
      final key = '$sequence:$value';
      final zip = zipCache.putIfAbsent(
        key,
        () => _makePack(_path, Uint8List.fromList(utf8.encode(value))),
      );
      await backend.installAuthenticatedZip(
        packId: 'render-cook', zipBytes: zip,
        expectedSha256: sha256.convert(zip).toString(),
        releaseSequence: sequence,
      );
    }
    await signed('v10', 10);
    await signed('v11', 11);
    await expectLater(signed('v10', 10), throwsStateError);
    await expectLater(signed('other-v11', 11), throwsStateError);
    expect(await StaticAssetPacks.rollback('render-cook'), isTrue);
    expect(await StaticAssetPacks.loadString(_path), 'v10');
    await expectLater(signed('v10', 10), throwsStateError);
    expect(await StaticAssetPacks.disable('render-cook'), isTrue);
    await expectLater(signed('v10', 10), throwsStateError);
    await signed('v11', 11);
    final current = File('${temp.path}/render-cook.release.json');
    final backup = File('${temp.path}/render-cook.release.previous.json');
    if (await backup.exists()) await backup.delete();
    await current.rename(backup.path);
    await expectLater(signed('v10', 10), throwsStateError);
    await signed('v12', 12);
    expect(await StaticAssetPacks.loadString(_path), 'v12');
  });

  test('防回滚状态损坏时拒绝自动安装，保留已安装版本', () async {
    final zip = _makePack(_path, Uint8List.fromList(utf8.encode('v20')));
    final hash = sha256.convert(zip).toString();
    await backend.installAuthenticatedZip(
      packId: 'render-cook', zipBytes: zip,
      expectedSha256: hash, releaseSequence: 20,
    );
    await File('${temp.path}/render-cook.release.json').writeAsString('{bad');
    await expectLater(
      backend.installAuthenticatedZip(
        packId: 'render-cook', zipBytes: zip,
        expectedSha256: hash, releaseSequence: 21,
      ),
      throwsFormatException,
    );
    expect(await StaticAssetPacks.loadString(_path), 'v20');
  });

  test('Cook 外置脚本安装/禁用/回滚后使已缓存引擎版本失效', () async {
    final service = DiscourseCookService();
    final before = service.debugAssetGeneration;
    final zip = _makePack(_path, Uint8List.fromList(utf8.encode('version 1')));
    await StaticAssetPacks.installTrustedZip(
      packId: 'render-cook',
      zipBytes: zip,
      expectedSha256: sha256.convert(zip).toString(),
    );
    expect(service.debugAssetGeneration, before + 1);
    expect(await StaticAssetPacks.disable('render-cook'), isTrue);
    expect(service.debugAssetGeneration, before + 2);
    expect(await StaticAssetPacks.rollback('render-cook'), isTrue);
    expect(service.debugAssetGeneration, before + 3);
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
