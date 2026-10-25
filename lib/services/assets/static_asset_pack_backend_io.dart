import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

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

/// 在 ZIP 解码前检查中央目录，提前拒绝超限声明和 ZIP64。
void _preflightZip(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  if (bytes.length < 22) throw FormatException('ZIP 尾部不完整');
  int? eocd;
  final limit = bytes.length > 65557 ? bytes.length - 65557 : 0;
  for (var i = bytes.length - 22; i >= limit; i--) {
    if (view.getUint32(i, Endian.little) == 0x06054b50 &&
        i + 22 + view.getUint16(i + 20, Endian.little) == bytes.length) {
      eocd = i;
      break;
    }
  }
  if (eocd == null ||
      view.getUint16(eocd + 4, Endian.little) != 0 ||
      view.getUint16(eocd + 6, Endian.little) != 0) {
    throw FormatException('ZIP 尾部不存在或为跨磁盘压缩包');
  }
  final count = view.getUint16(eocd + 10, Endian.little);
  final directorySize = view.getUint32(eocd + 12, Endian.little);
  final directoryOffset = view.getUint32(eocd + 16, Endian.little);
  if (count == 0 || count > 1024 ||
      directoryOffset + directorySize > eocd) {
    throw FormatException('ZIP 中央目录非法');
  }
  var position = directoryOffset;
  var totalSize = 0;
  for (var index = 0; index < count; index++) {
    if (position + 46 > eocd ||
        view.getUint32(position, Endian.little) != 0x02014b50) {
      throw FormatException('ZIP 中央目录条目不完整');
    }
    final flags = view.getUint16(position + 8, Endian.little);
    final method = view.getUint16(position + 10, Endian.little);
    final size = view.getUint32(position + 24, Endian.little);
    if ((flags & 1) != 0 || (method != 0 && method != 8) ||
        size == 0xffffffff || size > _maxFile) {
      throw FormatException('ZIP 加密/压缩方法或单文件大小不受支持');
    }
    totalSize += size;
    if (totalSize > _maxPack) {
      throw FormatException('ZIP 展开大小超过允许值');
    }
    position += 46 +
        view.getUint16(position + 28, Endian.little) +
        view.getUint16(position + 30, Endian.little) +
        view.getUint16(position + 32, Endian.little);
  }
  if (position != directoryOffset + directorySize) {
    throw FormatException('ZIP 中央目录长度不匹配');
  }
}

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
final _locks = <String, Lock>{};

Lock _lock(String id) => _locks.putIfAbsent(id, Lock.new);

Future<void> installTrustedZip({
  required String packId,
  required Uint8List zipBytes,
  required String expectedSha256,
}) {
  if (!_roots.containsKey(packId) || !_digestPattern.hasMatch(expectedSha256)) {
    throw ArgumentError('资源包 ID 或可信摘要错误');
  }
  return _lock(packId).synchronized(() => _installZip(packId, zipBytes, expectedSha256));
}

Future<void> _installZip(
  String packId,
  Uint8List zipBytes,
  String expectedSha256,
) async {
  if (zipBytes.length > _maxPack || _sha(zipBytes) != expectedSha256) {
    throw FormatException('ZIP 大小或整体 SHA-256 校验失败');
  }
  _preflightZip(zipBytes);
  final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
  if (archive.files.isEmpty || archive.files.length > 1024) {
    throw FormatException('资源包条目数量异常');
  }
  final files = <String, ArchiveFile>{};
  final foldedNames = <String>{};
  var advertisedSize = 0;
  for (final file in archive.files) {
    if (!file.isFile || file.isSymbolicLink || !_safePath(file.name) ||
        files.containsKey(file.name) ||
        !foldedNames.add(file.name.toLowerCase()) || file.size > _maxFile) {
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
  final stage = await base.createTemp('.stage-');
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
    // 相同版本目录不可原地删除：并发读取仍可能持有旧指针。
    if (await target.exists()) {
      if (!await _matches(target, hashes)) {
        throw StateError('相同摘要的资源已损坏，拒绝覆盖正在使用的版本');
      }
    } else {
      await stage.rename(target.path);
    }
    await _commitPointer(base, packId, <String, dynamic>{
      'schema': 1,
      'id': packId,
      'digest': expectedSha256,
      'files': hashes,
    });
  } finally {
    if (await stage.exists()) await stage.delete(recursive: true);
  }
}

/// 保留旧版本文件直到单独执行垃圾回收，不因切换而破坏并发读。
Future<bool> _matches(Directory root, Map<String, String> hashes) async {
  for (final entry in hashes.entries) {
    final file = File('${root.path}/${entry.key}');
    if (!await file.exists() || await file.length() > _maxFile ||
        _sha(await file.readAsBytes()) != entry.value) {
      return false;
    }
  }
  return true;
}

/// 指针更新先将 current 移到 previous，再启用新版本。
/// Windows 不允许直接覆盖已有目标时也可以恢复；进程在两次 rename 之间
/// 崩溃，读取方将使用 previous。旧资源目录保持不变。
Future<void> _commitPointer(
  Directory base,
  String id,
  Map<String, dynamic> data,
) async {
  final current = File('${base.path}/$id.current.json');
  final previous = File('${base.path}/$id.previous.json');
  final pending = File('${base.path}/$id.pending.json');
  await pending.writeAsString(jsonEncode(data), flush: true);
  var backedUp = false;
  try {
    if (!await current.exists() && await previous.exists()) {
      await previous.rename(current.path); // 崩溃恢复
    }
    if (await current.exists()) {
      if (await previous.exists()) await previous.delete();
      await current.rename(previous.path);
      backedUp = true;
    }
    await pending.rename(current.path);
  } catch (_) {
    if (backedUp && !await current.exists() && await previous.exists()) {
      await previous.rename(current.path);
    }
    rethrow;
  } finally {
    if (await pending.exists()) await pending.delete();
  }
}

Future<Map<String, dynamic>?> _readPointerFile(File file, String id) async {
  try {
    if (!await file.exists()) return null;
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic> ||
        value['schema'] != 1 || value['id'] != id) {
      return null;
    }
    if (value['disabled'] == true) return value;
    final digest = value['digest'];
    final hashes = value['files'];
    if (digest is! String || !_digestPattern.hasMatch(digest) ||
        hashes is! Map || hashes.isEmpty) {
      return null;
    }
    for (final entry in hashes.entries) {
      if (entry.key is! String || !_allows(id, entry.key as String) ||
          entry.value is! String ||
          !_digestPattern.hasMatch(entry.value as String)) {
        return null;
      }
    }
    return value;
  } catch (_) {
    return null;
  }
}

Future<Map<String, dynamic>?> _currentPointer(Directory base, String id) async {
  return await _readPointerFile(File('${base.path}/$id.current.json'), id) ??
      await _readPointerFile(File('${base.path}/$id.previous.json'), id);
}

/// 恢复上一版资源（包括禁用状态），内容损坏时拒绝回滚。
Future<bool> rollbackPack(String id) {
  if (!_roots.containsKey(id)) throw ArgumentError.value(id, 'id');
  return _lock(id).synchronized(() async {
    final base = await _base();
    final previous = await _readPointerFile(
      File('${base.path}/$id.previous.json'), id,
    );
    if (previous == null) return false;
    if (previous['disabled'] != true) {
      final digest = previous['digest'] as String;
      final hashes = (previous['files'] as Map).cast<String, String>();
      if (!await _matches(Directory('${base.path}/$id-$digest'), hashes)) {
        return false;
      }
    }
    await _commitPointer(base, id, previous);
    return true;
  });
}

/// 禁用可选资源；不删除旧资源，以便重新激活与恢复。
Future<bool> disablePack(String id) {
  if (!_roots.containsKey(id)) throw ArgumentError.value(id, 'id');
  return _lock(id).synchronized(() async {
    final base = await _base();
    final current = await _currentPointer(base, id);
    if (current == null || current['disabled'] == true) return false;
    await _commitPointer(base, id, <String, dynamic>{
      'schema': 1, 'id': id, 'disabled': true,
    });
    return true;
  });
}

/// 已激活资源列表，不包括缺失或禁用项。
Future<List<Map<String, String>>> listInstalledPacks() async {
  final base = await _base();
  final result = <Map<String, String>>[];
  for (final id in _roots.keys) {
    final pointer = await _currentPointer(base, id);
    if (pointer != null && pointer['disabled'] != true) {
      result.add(<String, String>{
        'id': id, 'digest': pointer['digest'] as String,
      });
    }
  }
  return result;
}

/// 所有读取再次验证 SHA-256。安装未完成、包损坏或不兼容返回 null。
Future<Uint8List?> readVerifiedAsset(String assetPath) async {
  final packId = _owner(assetPath);
  if (packId == null) return null;
  return _lock(packId).synchronized(() async {
  try {
    final base = await _base();
    final current = await _currentPointer(base, packId);
    if (current == null || current['disabled'] == true) return null;
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
  });
}

/// 显式清理非 current/previous 的历史内容目录。每个包独立加锁，
/// 防止读取与回滚被删除中的旧目录打断；绝不删除未知文件或符号链接。
/// 默认只清理至少一天前的版本，避免对刚更新的版本进行反复 IO。
Future<int> pruneUnusedPacks({
  Duration minAge = const Duration(days: 1),
}) async {
  if (minAge.isNegative) throw ArgumentError.value(minAge, 'minAge');
  final base = await _base();
  var reclaimed = 0;
  for (final id in _roots.keys) {
    reclaimed += await _lock(id).synchronized(() async {
      final current = await _readPointerFile(
        File('${base.path}/$id.current.json'), id,
      );
      final previous = await _readPointerFile(
        File('${base.path}/$id.previous.json'), id,
      );
      // 不能确定可靠的激活指针时停止回收，优先保护离线数据。
      if (current == null && previous == null) return 0;
      final protected = <String>{
        if (current?['digest'] is String) current!['digest'] as String,
        if (previous?['digest'] is String) previous!['digest'] as String,
      };
      var freed = 0;
      await for (final entity in base.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = entity.uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .last;
        if (!name.startsWith('$id-')) continue;
        final digest = name.substring(id.length + 1);
        if (!_digestPattern.hasMatch(digest) || protected.contains(digest)) {
          continue;
        }
        final age = DateTime.now().difference((await entity.stat()).modified);
        if (age < minAge) continue;
        final bytes = await _safeDirectorySize(entity);
        if (bytes == null) continue;
        await entity.delete(recursive: true);
        freed += bytes;
      }
      return freed;
    });
  }
  return reclaimed;
}

/// 对清理目标做递归确认：文件与目录允许，任何软链接均拒绝清理。
Future<int?> _safeDirectorySize(Directory directory) async {
  var total = 0;
  await for (final file in directory.list(recursive: true, followLinks: false)) {
    final kind = await FileSystemEntity.type(file.path, followLinks: false);
    if (kind == FileSystemEntityType.link) return null;
    if (kind == FileSystemEntityType.file) {
      total += await File(file.path).length();
    }
  }
  return total;
}
