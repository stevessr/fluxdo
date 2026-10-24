import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

/// 与构建器 PACKS 对齐，不能信任 ZIP 自己声明的路径白名单。
const _roots = <String, String>{
  'font-misans': 'assets/fonts/MiSansVF.ttf',
  'render-cook': 'assets/cook/discourse-cook.js',
  'render-polyfill': 'assets/polyfill/compat-polyfill.js',
  'ai-brands': 'assets/ai_brands/',
  'avatar-touhou': 'assets/images/avater/touhou/',
  'avatar-blue-archive': 'assets/images/avater/blue_archive/',
  'avatar-witch-judgment': 'assets/images/avater/witch_judgment/',
  'avatar-llm': 'assets/images/avater/llm/',
  'avatar-stevessr': 'assets/images/avater/stevessr/',
};
const _maxFile = 128 * 1024 * 1024;
const _maxPack = 512 * 1024 * 1024;
final _digestPattern = RegExp(r'^[a-f0-9]{64}$');

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

bool _safePath(String path) =>
    path.isNotEmpty &&
    !path.startsWith('/') &&
    !path.contains('\\') &&
    !path.contains(':') &&
    !path.contains('\u0000') &&
    path.split('/').every(
      (part) => part.isNotEmpty && part != '.' && part != '..',
    );

bool _allows(String id, String path) {
  final root = _roots[id];
  if (root == null || !_safePath(path)) return false;
  return root.endsWith('/') ? path.startsWith(root) : path == root;
}

String? _owner(String path) {
  for (final id in _roots.keys) {
    if (_allows(id, path)) return id;
  }
  return null;
}

@visibleForTesting
Directory? testAssetPackStoreRoot;

Future<Directory> _base() async {
  if (testAssetPackStoreRoot != null) {
    await testAssetPackStoreRoot!.create(recursive: true);
    return testAssetPackStoreRoot!;
  }
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/static_asset_packs/v1');
  await dir.create(recursive: true);
  return dir;
}

/// 安装前对外部传入的可信 SHA、文件路径和每个文件散列执行严格校验。
/// ZIP 内容只有在全部通过后才切换当前包指针。
Future<void> installTrustedZip({
  required String packId,
  required Uint8List zipBytes,
  required String expectedSha256,
}) async {
  if (!_roots.containsKey(packId) || !_digestPattern.hasMatch(expectedSha256)) {
    throw ArgumentError('资源包 ID 或可信摘要错误');
  }
  if (zipBytes.length > _maxPack || _sha(zipBytes) != expectedSha256) {
    throw FormatException('ZIP 大小或整体 SHA-256 校验失败');
  }
  final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
  if (archive.files.isEmpty || archive.files.length > 1024) {
    throw FormatException('资源包条目数量异常');
  }
  final files = <String, ArchiveFile>{};
  var advertisedSize = 0;
  for (final file in archive.files) {
    if (!file.isFile || file.isSymbolicLink || !_safePath(file.name) ||
        files.containsKey(file.name) || file.size > _maxFile) {
      throw FormatException('资源包含非法条目');
    }
    advertisedSize += file.size;
    if (advertisedSize > _maxPack) throw FormatException('解压大小超限');
    files[file.name] = file;
  }
  final manifestEntry = files.remove('manifest.json');
  if (manifestEntry == null || manifestEntry.size > 1024 * 1024) {
    throw FormatException('缺少合法资源 manifest');
  }
  final manifestBytes = manifestEntry.readBytes();
  if (manifestBytes == null) throw FormatException('manifest 内容为空');
  final manifest = jsonDecode(utf8.decode(manifestBytes));
  if (manifest is! Map<String, dynamic> ||
      manifest['schema'] != 1 || manifest['id'] != packId ||
      manifest['files'] is! List) {
    throw FormatException('资源清单协议不匹配');
  }
  final entries = manifest['files'] as List;
  if (entries.length != files.length) {
    throw FormatException('资源数目不匹配');
  }

  final base = await _base();
  final stage = await Directory('${base.path}/.stage-').createTemp();
  final hashes = <String, String>{};
  try {
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        throw FormatException('无效清单条目');
      }
      final name = entry['path'];
      final hash = entry['sha256'];
      final declaredLength = entry['bytes'];
      if (name is! String || !_allows(packId, name) ||
          hash is! String || !_digestPattern.hasMatch(hash) ||
          declaredLength is! int || declaredLength < 0 ||
          declaredLength > _maxFile || hashes.containsKey(name)) {
        throw FormatException('资源清单路径或校验字段不合法');
      }
      final file = files[name];
      if (file == null || file.size != declaredLength) {
        throw FormatException('ZIP 文件与资源清单不符');
      }
      final content = file.readBytes();
      if (content == null) throw FormatException('资源文件内容为空');
      if (content.length != declaredLength || _sha(content) != hash) {
        throw FormatException('资源内容校验失败');
      }
      final out = File('${stage.path}/$name');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(content, flush: true);
      hashes[name] = hash;
    }
    if (hashes.length != files.length) throw FormatException('存在清单外文件');

    final target = Directory('${base.path}/$packId-$expectedSha256');
    if (await target.exists()) await target.delete(recursive: true);
    await stage.rename(target.path);

    final pointer = File('${base.path}/$packId.current.json');
    final temp = File('${base.path}/$packId.current.tmp');
    await temp.writeAsString(jsonEncode({
      'schema': 1, 'id': packId, 'digest': expectedSha256, 'files': hashes,
    }), flush: true);
    if (await pointer.exists()) await pointer.delete();
    await temp.rename(pointer.path);
  } finally {
    if (await stage.exists()) await stage.delete(recursive: true);
  }
}

/// 所有读取再次验证 SHA-256。安装未完成、包损坏或不兼容返回 null。
Future<Uint8List?> readVerifiedAsset(String assetPath) async {
  final packId = _owner(assetPath);
  if (packId == null) return null;
  try {
    final base = await _base();
    final pointer = File('${base.path}/$packId.current.json');
    if (!await pointer.exists()) return null;
    final current = jsonDecode(await pointer.readAsString());
    if (current is! Map<String, dynamic> ||
        current['schema'] != 1 || current['id'] != packId ||
        current['digest'] is! String ||
        !_digestPattern.hasMatch(current['digest'] as String) ||
        current['files'] is! Map) {
      return null;
    }
    final hash = (current['files'] as Map)[assetPath];
    if (hash is! String || !_digestPattern.hasMatch(hash)) return null;
    final path = '${base.path}/$packId-${current['digest']}/$assetPath';
    final file = File(path);
    if (!await file.exists() || await file.length() > _maxFile) return null;
    final content = await file.readAsBytes();
    return _sha(content) == hash ? content : null;
  } catch (_) {
    return null;
  }
}
