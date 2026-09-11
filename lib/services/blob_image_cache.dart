import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' show md5;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dio_http_client.dart';

/// Blob 图片缓存的磁盘使用统计。
///
/// [diskBytes] 是缓存根目录里真实文件的字节数；[logicalBytes] 按逻辑引用
/// 计算，同一 URL 被多个 key / bucket 引用时会重复计入，因此两者之差中
/// 的 [deduplicatedBytes] 可以直观看出共享物理副本节省了多少 payload。
@immutable
class BlobImageCacheUsage {
  const BlobImageCacheUsage({
    required this.diskBytes,
    required this.payloadBytes,
    required this.logicalBytes,
    required this.deduplicatedBytes,
    required this.objectCount,
    required this.referenceCount,
    required this.sharedObjectCount,
    required this.bucketBytes,
  });

  final int diskBytes;
  final int payloadBytes;
  final int logicalBytes;
  final int deduplicatedBytes;
  final int objectCount;
  final int referenceCount;
  final int sharedObjectCount;
  final Map<String, int> bucketBytes;
}

class _CacheRefStat {
  const _CacheRefStat({
    required this.path,
    required this.target,
    required this.mtime,
    required this.size,
  });

  final String path;
  final String target;
  final DateTime mtime;
  final int size;
}

/// 图片的 URL 寻址文件缓存（Telegram ImageLoader 形态）。
///
/// ## 存储身份与逻辑身份分离
///
/// 旧实现虽然不使用 sqlite，但路径仍是 `bucket/md5(url)`，因此同一 URL
/// 只要同时以正文图、原图、头像或外部图等不同用途出现，就会在磁盘上
/// 保存多份 payload，并且并发请求也会重复下载。
///
/// 现在拆为两层：
/// - `_objects/md5(url).ext`：URL 决定唯一物理对象，全局只保存一份；
/// - `_refs/<bucket>/md5(key).ref`：很小的逻辑引用，记录 key 指向哪个
///   物理对象。不同 key、不同 bucket 都可以共享同一个 URL 对象。
///
/// bucket 仍负责保留期、容量上限和分类清理。删除一个 bucket 只删除它
/// 的引用；只有最后一个引用消失后才回收物理对象，所以共享不会破坏
/// Telegram Storage Usage 式的分类管理语义。
class BlobImageCache {
  BlobImageCache._();

  /// 根目录名（Temporary 下），也是数据管理页统计/清理的口径。
  static const String dirName = 'blobImageCache';

  /// 共享物理对象目录。
  static const String objectDirName = '_objects';

  /// 逻辑引用目录。
  static const String referenceDirName = '_refs';

  /// bucket → 保留期。沿用被替换的各 cache manager 的 stalePeriod 语义。
  static const Map<String, Duration> buckets = {
    emojiBucket: Duration(days: 90),
    avatarBucket: Duration(days: 30),
    stickerThumbBucket: Duration(days: 90),
    contentBucket: Duration(days: 7),
    originalBucket: Duration(days: 7),
    stickerOriginalBucket: Duration(days: 90),
    externalBucket: Duration(days: 30),
  };

  /// 大图 bucket 的逻辑字节上限。
  ///
  /// 同一个物理对象在同 bucket 下即使存在多个 key，也只计一次容量；
  /// 跨 bucket 则分别参与各自策略，但磁盘 payload 仍只有一份。
  static const Map<String, int> bucketByteLimits = {
    contentBucket: 1 << 30, // 1 GB
    originalBucket: 512 << 20, // 512 MB
    stickerOriginalBucket: 1 << 30, // 1 GB
    externalBucket: 256 << 20, // 256 MB
  };

  static const String emojiBucket = 'emoji';
  static const String avatarBucket = 'avatar';
  static const String stickerThumbBucket = 'stickerThumb';
  static const String contentBucket = 'content';
  static const String originalBucket = 'original';
  static const String stickerOriginalBucket = 'stickerOriginal';
  static const String externalBucket = 'external';

  static Directory? _root;
  static Future<Directory>? _rootFuture;

  /// 同 URL 在途下载全局去重，不再把 bucket 算进下载身份。
  static final Map<String, Future<Uint8List>> _inflight = {};

  /// 本会话已经写过的引用目标。
  ///
  /// value 也保留下来，以便同一个 cacheKey 在会话内改指向新 URL 时可以
  /// 正确更新，而不是被“每会话 touch 一次”的优化误挡住。
  static final Map<String, String> _referenceTargets = {};

  static Future<Directory> _ensureRoot() =>
      _rootFuture ??= (() async {
        final tmp = await getTemporaryDirectory();
        final dir = Directory('${tmp.path}/$dirName');
        await dir.create(recursive: true);
        _root = dir;
        return dir;
      })();

  static String _hash(String value) => md5.convert(utf8.encode(value)).toString();

  /// URL 对应的唯一物理对象文件名。
  ///
  /// 公开这个纯函数主要用于诊断/测试：无论从哪个 bucket 或 cacheKey
  /// 访问，只要 URL 完全相同，返回值就完全相同。
  static String objectNameForUrl(String url) =>
      '${_hash(url)}.${httpUrlExtension(url)}';

  /// 逻辑 key 对应的引用文件名。key 与 URL 完全解耦。
  static String referenceNameForKey(String key) => '${_hash(key)}.ref';

  static Future<File> _objectFileFor(String url) async {
    final root = _root ?? await _ensureRoot();
    return File('${root.path}/$objectDirName/${objectNameForUrl(url)}');
  }

  static Future<File> _referenceFileFor(String bucket, String key) async {
    final root = _root ?? await _ensureRoot();
    return File(
      '${root.path}/$referenceDirName/$bucket/${referenceNameForKey(key)}',
    );
  }

  /// v10 以前 `bucket/md5(url).ext` 的旧布局，只用于惰性迁移。
  static Future<File> _legacyFileFor(String bucket, String url) async {
    final root = _root ?? await _ensureRoot();
    return File('${root.path}/$bucket/${objectNameForUrl(url)}');
  }

  /// 从 URL 提取扩展名（Telegram `ImageLoader.getHttpUrlExtension` 同款）。
  static String httpUrlExtension(String url, [String defaultExt = 'jpg']) {
    var haystack = url;
    final segments = Uri.tryParse(url)?.pathSegments;
    if (segments != null && segments.isNotEmpty && segments.last.length > 1) {
      haystack = segments.last;
    }
    final idx = haystack.lastIndexOf('.');
    final ext = idx == -1 ? '' : haystack.substring(idx + 1).toLowerCase();
    final valid =
        ext.isNotEmpty && ext.length <= 4 && _extPattern.hasMatch(ext);
    return valid ? ext : defaultExt;
  }

  static final RegExp _extPattern = RegExp(r'^[a-z0-9]+$');

  static bool _isSafeObjectName(String value) =>
      value.isNotEmpty && !value.contains('/') && !value.contains('\\');

  static bool _isTempPath(String path) =>
      path.endsWith('.tmp') || path.contains('.tmp.');

  /// 为 bucket/key 建立或刷新逻辑引用。
  ///
  /// 引用文件只有几十字节，mtime 就是该逻辑引用的 LRU 时间。每会话同一
  /// key→object 只写一次，避免热图片反复产生小 IO。
  static Future<void> _ensureReference(
    String bucket,
    String key,
    File object,
  ) async {
    final ref = await _referenceFileFor(bucket, key);
    final target = p.basename(object.path);
    if (_referenceTargets[ref.path] == target) return;

    try {
      await ref.parent.create(recursive: true);
      final tmp = File(
        '${ref.path}.tmp.${DateTime.now().microsecondsSinceEpoch}',
      );
      await tmp.writeAsString(target, flush: false);
      try {
        await tmp.rename(ref.path);
      } on FileSystemException {
        if (await ref.exists()) await ref.delete();
        await tmp.rename(ref.path);
      }
      _referenceTargets[ref.path] = target;
    } catch (e) {
      debugPrint('[BlobImageCache] 写引用失败 $bucket/$key: $e');
    }
  }

  static Future<Uint8List?> _readObject(File object) async {
    try {
      final bytes = await object.readAsBytes();
      if (bytes.isEmpty) return null;
      return bytes;
    } on FileSystemException {
      return null;
    }
  }

  /// 把旧的 per-bucket payload 惰性迁入共享对象池。
  ///
  /// 已知 URL 后可以反推出所有旧 bucket 的确定性路径，因此会把同 URL
  /// 的旧重复副本一次性收敛成一个 object，并为发现它的每个旧 bucket
  /// 补引用，最大限度保留升级前的分类语义。
  static Future<File?> _migrateLegacyCopies(
    String requestedBucket,
    String requestedKey,
    String url,
  ) async {
    final found = <({String bucket, File file})>[];
    final order = <String>[
      requestedBucket,
      ...buckets.keys.where((b) => b != requestedBucket),
    ];
    for (final bucket in order) {
      final file = await _legacyFileFor(bucket, url);
      try {
        if (await file.exists()) found.add((bucket: bucket, file: file));
      } catch (_) {}
    }
    if (found.isEmpty) return null;

    final object = await _objectFileFor(url);
    try {
      await object.parent.create(recursive: true);
      if (!await object.exists()) {
        final source = found.first.file;
        try {
          await source.rename(object.path);
        } on FileSystemException {
          await source.copy(object.path);
        }
      }

      for (final entry in found) {
        // 旧布局的 key 就是 URL，因此保留原逻辑引用。
        await _ensureReference(entry.bucket, url, object);
        try {
          if (await entry.file.exists()) await entry.file.delete();
        } catch (_) {}
      }
      // 如果本次调用显式用了不同 cacheKey，再额外建立该别名。
      if (requestedKey != url) {
        await _ensureReference(requestedBucket, requestedKey, object);
      }
      return object;
    } catch (e) {
      debugPrint('[BlobImageCache] 迁移旧缓存失败 $url: $e');
      return null;
    }
  }

  /// 只读缓存：物理身份由 [url] 决定，逻辑身份由 [key] 决定。
  ///
  /// 省略 [url] 时保持旧 API 兼容，即 key 本身就是 URL。
  static Future<Uint8List?> read(
    String bucket,
    String key, {
    String? url,
  }) async {
    final resourceUrl = url ?? key;
    var object = await _objectFileFor(resourceUrl);
    var bytes = await _readObject(object);
    if (bytes == null) {
      object =
          await _migrateLegacyCopies(bucket, key, resourceUrl) ?? object;
      bytes = await _readObject(object);
    }
    if (bytes == null) return null;
    await _ensureReference(bucket, key, object);
    return bytes;
  }

  static Future<void> _writeObject(String url, Uint8List bytes) async {
    final object = await _objectFileFor(url);
    try {
      await object.parent.create(recursive: true);
      final tmp = File(
        '${object.path}.tmp.${DateTime.now().microsecondsSinceEpoch}',
      );
      await tmp.writeAsBytes(bytes, flush: true);
      try {
        await tmp.rename(object.path);
      } on FileSystemException {
        if (await object.exists()) await object.delete();
        await tmp.rename(object.path);
      }
    } catch (e) {
      debugPrint('[BlobImageCache] 写共享对象失败 $url: $e');
    }
  }

  /// 写入缓存。不同 key 只要 [url] 相同，最终都引用同一个物理文件。
  static Future<void> write(
    String bucket,
    String key,
    Uint8List bytes, {
    String? url,
  }) async {
    final resourceUrl = url ?? key;
    await _writeObject(resourceUrl, bytes);
    final object = await _objectFileFor(resourceUrl);
    if (await object.exists()) {
      await _ensureReference(bucket, key, object);
    }
  }

  /// 读缓存，miss 则下载并落盘。
  ///
  /// [cacheKey] 只决定逻辑引用；下载和 payload 永远以 URL 为身份，所以
  /// 不同 key / bucket 对同一 URL 的并发调用也只会发生一次 HTTP 请求。
  static Future<Uint8List> fetch(
    String bucket,
    String url, {
    String? cacheKey,
    DownloadPriority priority = DownloadPriority.normal,
    void Function(int received, int? total)? onProgress,
  }) async {
    final key = cacheKey ?? url;
    final cached = await read(bucket, key, url: url);
    if (cached != null) return cached;

    final future = _inflight.putIfAbsent(
      url,
      () => _downloadObject(bucket, url, priority, onProgress).whenComplete(() {
        _inflight.remove(url);
      }),
    );
    final bytes = await future;
    final object = await _objectFileFor(url);
    await _ensureReference(bucket, key, object);
    return bytes;
  }

  static DownloadChannel _channelOf(String bucket) => switch (bucket) {
        emojiBucket => DownloadChannel.small,
        stickerOriginalBucket => DownloadChannel.sticker,
        _ => DownloadChannel.content,
      };

  static void bump(String bucket, String url) =>
      DioHttpClient.bumpPending(_channelOf(bucket), url);

  static void sink(String bucket, String url) =>
      DioHttpClient.sinkPending(_channelOf(bucket), url);

  static Future<Uint8List> _downloadObject(
    String bucket,
    String url,
    DownloadPriority priority,
    void Function(int received, int? total)? onProgress,
  ) async {
    final bytes = await DioHttpClient().fetchBytes(
      Uri.parse(url),
      channel: _channelOf(bucket),
      priority: priority,
      onProgress: onProgress,
    );
    if (bytes.isEmpty) {
      throw HttpException(
        'BlobImageCache: empty body for $url',
        uri: Uri.parse(url),
      );
    }
    await _writeObject(url, bytes);
    return bytes;
  }

  /// 需要 File 语义的调用方得到共享 object 文件，而不是 bucket 副本。
  static Future<File> getFile(
    String bucket,
    String url, {
    String? cacheKey,
    void Function(int received, int? total)? onProgress,
  }) async {
    await fetch(
      bucket,
      url,
      cacheKey: cacheKey,
      onProgress: onProgress,
    );
    return _objectFileFor(url);
  }

  /// 仅查缓存是否存在，不下载；命中时顺便确保当前逻辑引用存在。
  static Future<bool> contains(
    String bucket,
    String url, {
    String? cacheKey,
  }) async {
    final key = cacheKey ?? url;
    var object = await _objectFileFor(url);
    try {
      if (await object.exists()) {
        await _ensureReference(bucket, key, object);
        return true;
      }
    } catch (_) {}

    object = await _migrateLegacyCopies(bucket, key, url) ?? object;
    try {
      return await object.exists();
    } catch (_) {
      return false;
    }
  }

  /// 预取：共享在途下载由 [fetch] 自动合并，不能因“另一个 bucket 正在
  /// 下载”就提前 return，否则当前 bucket 的逻辑引用会丢失。
  static Future<void> precache(
    String bucket,
    String url, {
    String? cacheKey,
  }) async {
    try {
      if (await contains(bucket, url, cacheKey: cacheKey)) return;
      await fetch(bucket, url, cacheKey: cacheKey);
    } catch (e) {
      debugPrint('[BlobImageCache] precache 失败 $url: $e');
    }
  }

  /// 扫描并执行 bucket 保留期/容量策略，然后回收无引用共享对象。
  static Future<void> sweep(SharedPreferences prefs) async {
    const stampKey = 'blob_image_cache_last_sweep';
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = prefs.getInt(stampKey) ?? 0;
    if (now - last < const Duration(hours: 24).inMilliseconds) return;
    await prefs.setInt(stampKey, now);

    final root = await _ensureRoot();
    final rootPath = root.path;
    final retention = Map<String, Duration>.of(buckets);
    final byteLimits = Map<String, int>.of(bucketByteLimits);

    try {
      final deleted = await Isolate.run(() {
        var count = 0;
        final nowTime = DateTime.now();
        final objectsPath = '$rootPath/$objectDirName';
        final refsPath = '$rootPath/$referenceDirName';

        for (final policy in retention.entries) {
          final refDir = Directory('$refsPath/${policy.key}');
          final aliveRefs = <_CacheRefStat>[];

          if (refDir.existsSync()) {
            for (final entity in refDir.listSync(followLinks: false)) {
              if (entity is! File) continue;
              try {
                final stat = entity.statSync();
                final age = nowTime.difference(stat.modified);
                if (_isTempPath(entity.path)) {
                  if (age > const Duration(days: 1)) {
                    entity.deleteSync();
                    count++;
                  }
                  continue;
                }
                if (age > policy.value) {
                  entity.deleteSync();
                  count++;
                  continue;
                }
                final target = entity.readAsStringSync().trim();
                if (!_isSafeObjectName(target)) {
                  entity.deleteSync();
                  count++;
                  continue;
                }
                final object = File('$objectsPath/$target');
                if (!object.existsSync()) {
                  entity.deleteSync();
                  count++;
                  continue;
                }
                final objectStat = object.statSync();
                aliveRefs.add(
                  _CacheRefStat(
                    path: entity.path,
                    target: target,
                    mtime: stat.modified,
                    size: objectStat.size,
                  ),
                );
              } catch (_) {}
            }
          }

          // bucket 容量按“唯一对象”计，不让同 URL 的多个别名重复挤占配额。
          final grouped = <String, List<_CacheRefStat>>{};
          for (final ref in aliveRefs) {
            (grouped[ref.target] ??= <_CacheRefStat>[]).add(ref);
          }
          final limit = byteLimits[policy.key];
          if (limit != null) {
            var refBytes = 0;
            final groups = <({String target, DateTime mtime, int size})>[];
            for (final entry in grouped.entries) {
              var newest = entry.value.first.mtime;
              for (final ref in entry.value.skip(1)) {
                if (ref.mtime.isAfter(newest)) newest = ref.mtime;
              }
              final size = entry.value.first.size;
              refBytes += size;
              groups.add((target: entry.key, mtime: newest, size: size));
            }
            groups.sort((a, b) => a.mtime.compareTo(b.mtime));
            for (final group in groups) {
              if (refBytes <= limit) break;
              for (final ref in grouped[group.target]!) {
                try {
                  final file = File(ref.path);
                  if (file.existsSync()) {
                    file.deleteSync();
                    count++;
                  }
                } catch (_) {}
              }
              refBytes -= group.size;
            }
          }

          // v10 前旧 bucket payload 继续按原策略淘汰。容量上限会扣除新
          // 引用已经占用的逻辑空间，避免迁移窗口出现 2 倍配额。
          final legacyDir = Directory('$rootPath/${policy.key}');
          if (!legacyDir.existsSync()) continue;
          final legacyAlive = <({String path, DateTime mtime, int size})>[];
          for (final entity in legacyDir.listSync(followLinks: false)) {
            if (entity is! File) continue;
            try {
              final stat = entity.statSync();
              final age = nowTime.difference(stat.modified);
              if (age > policy.value ||
                  (_isTempPath(entity.path) &&
                      age > const Duration(days: 1))) {
                entity.deleteSync();
                count++;
              } else if (!_isTempPath(entity.path)) {
                legacyAlive.add(
                  (path: entity.path, mtime: stat.modified, size: stat.size),
                );
              }
            } catch (_) {}
          }

          if (limit == null) continue;
          final survivingTargets = <String>{};
          for (final entry in grouped.entries) {
            if (entry.value.any((r) => File(r.path).existsSync())) {
              survivingTargets.add(entry.key);
            }
          }
          var refBytes = 0;
          for (final target in survivingTargets) {
            final refs = grouped[target];
            if (refs != null && refs.isNotEmpty) refBytes += refs.first.size;
          }
          var legacyBudget = limit - refBytes;
          if (legacyBudget < 0) legacyBudget = 0;
          var legacyBytes =
              legacyAlive.fold<int>(0, (sum, item) => sum + item.size);
          if (legacyBytes <= legacyBudget) continue;
          legacyAlive.sort((a, b) => a.mtime.compareTo(b.mtime));
          for (final item in legacyAlive) {
            if (legacyBytes <= legacyBudget) break;
            try {
              File(item.path).deleteSync();
              legacyBytes -= item.size;
              count++;
            } catch (_) {}
          }
        }

        // 最终从所有 ref（包括未来新增的未知 bucket）收集存活 object。
        final liveTargets = <String>{};
        final refsRoot = Directory(refsPath);
        if (refsRoot.existsSync()) {
          for (final entity
              in refsRoot.listSync(recursive: true, followLinks: false)) {
            if (entity is! File || _isTempPath(entity.path)) continue;
            try {
              final target = entity.readAsStringSync().trim();
              if (_isSafeObjectName(target)) liveTargets.add(target);
            } catch (_) {}
          }
        }

        final objectDir = Directory(objectsPath);
        if (objectDir.existsSync()) {
          for (final entity in objectDir.listSync(followLinks: false)) {
            if (entity is! File) continue;
            try {
              final stat = entity.statSync();
              final age = nowTime.difference(stat.modified);
              if (_isTempPath(entity.path)) {
                if (age > const Duration(days: 1)) {
                  entity.deleteSync();
                  count++;
                }
                continue;
              }
              final name = p.basename(entity.path);
              // 给“object 已落盘、ref 尚未写完”的极短窗口留 1 天保护。
              if (!liveTargets.contains(name) &&
                  age > const Duration(days: 1)) {
                entity.deleteSync();
                count++;
              }
            } catch (_) {}
          }
        }
        return count;
      });
      if (deleted > 0) {
        debugPrint('[BlobImageCache] sweep 删除 $deleted 个过期/超限项');
      }
    } catch (e) {
      debugPrint('[BlobImageCache] sweep 失败: $e');
    }
  }

  static Set<String> _readReferenceTargetsSync(Directory root) {
    final targets = <String>{};
    try {
      if (!root.existsSync()) return targets;
      for (final entity
          in root.listSync(recursive: true, followLinks: false)) {
        if (entity is! File || _isTempPath(entity.path)) continue;
        try {
          final target = entity.readAsStringSync().trim();
          if (_isSafeObjectName(target)) targets.add(target);
        } catch (_) {}
      }
    } catch (_) {}
    return targets;
  }

  static Future<void> _deleteUnreferencedTargets(Set<String> candidates) async {
    if (candidates.isEmpty) return;
    final root = await _ensureRoot();
    final liveTargets = _readReferenceTargetsSync(
      Directory('${root.path}/$referenceDirName'),
    );
    final protected = _inflight.keys.map(objectNameForUrl).toSet();

    for (final target in candidates) {
      if (liveTargets.contains(target) || protected.contains(target)) continue;
      try {
        final file = File('${root.path}/$objectDirName/$target');
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// 清空单个 bucket：只删逻辑引用和旧布局副本。
  ///
  /// 删除前收集它引用的 object，删除后只回收不再被其它 bucket 引用的
  /// 那部分，因此分类清理天然支持共享副本。
  static Future<void> clearBucket(String bucket) async {
    final root = await _ensureRoot();
    final refDir = Directory('${root.path}/$referenceDirName/$bucket');
    final legacyDir = Directory('${root.path}/$bucket');
    final candidates = _readReferenceTargetsSync(refDir);

    try {
      if (await refDir.exists()) await refDir.delete(recursive: true);
      if (await legacyDir.exists()) await legacyDir.delete(recursive: true);
    } catch (e) {
      debugPrint('[BlobImageCache] clearBucket $bucket 失败: $e');
    }
    _referenceTargets.removeWhere((path, _) => path.startsWith(refDir.path));
    await _deleteUnreferencedTargets(candidates);
  }

  /// 清空全部 blob 缓存。
  static Future<void> clearAll() async {
    final root = await _ensureRoot();
    try {
      if (await root.exists()) await root.delete(recursive: true);
      await root.create(recursive: true);
    } catch (e) {
      debugPrint('[BlobImageCache] clearAll 失败: $e');
    }
    _referenceTargets.clear();
  }

  /// 获取共享缓存统计。目录扫描放 isolate，避免数据管理页打开时阻塞 UI。
  static Future<BlobImageCacheUsage> getUsage() async {
    final root = await _ensureRoot();
    final rootPath = root.path;
    final knownBuckets = buckets.keys.toList(growable: false);

    final result = await Isolate.run(() {
      var diskBytes = 0;
      var payloadBytes = 0;
      var logicalBytes = 0;
      var objectCount = 0;
      var referenceCount = 0;
      var sharedObjectCount = 0;
      var deduplicatedBytes = 0;
      final bucketBytes = <String, int>{
        for (final bucket in knownBuckets) bucket: 0,
      };
      final objectSizes = <String, int>{};
      final refCounts = <String, int>{};
      final bucketTargets = <String, Set<String>>{};

      final objectDir = Directory('$rootPath/$objectDirName');
      if (objectDir.existsSync()) {
        for (final entity in objectDir.listSync(followLinks: false)) {
          if (entity is! File) continue;
          try {
            final stat = entity.statSync();
            diskBytes += stat.size;
            if (_isTempPath(entity.path)) continue;
            final name = p.basename(entity.path);
            objectSizes[name] = stat.size;
            payloadBytes += stat.size;
            objectCount++;
          } catch (_) {}
        }
      }

      final refsRoot = Directory('$rootPath/$referenceDirName');
      if (refsRoot.existsSync()) {
        for (final bucketDir in refsRoot.listSync(followLinks: false)) {
          if (bucketDir is! Directory) continue;
          final bucket = p.basename(bucketDir.path);
          final targets = bucketTargets.putIfAbsent(bucket, () => <String>{});
          for (final entity in bucketDir.listSync(followLinks: false)) {
            if (entity is! File) continue;
            try {
              final stat = entity.statSync();
              diskBytes += stat.size;
              if (_isTempPath(entity.path)) continue;
              final target = entity.readAsStringSync().trim();
              final size = objectSizes[target];
              if (!_isSafeObjectName(target) || size == null) continue;
              referenceCount++;
              logicalBytes += size;
              refCounts[target] = (refCounts[target] ?? 0) + 1;
              targets.add(target);
            } catch (_) {}
          }
        }
      }

      for (final entry in bucketTargets.entries) {
        var total = 0;
        for (final target in entry.value) {
          total += objectSizes[target] ?? 0;
        }
        bucketBytes[entry.key] = (bucketBytes[entry.key] ?? 0) + total;
      }

      for (final entry in refCounts.entries) {
        if (entry.value <= 1) continue;
        final size = objectSizes[entry.key] ?? 0;
        sharedObjectCount++;
        deduplicatedBytes += size * (entry.value - 1);
      }

      // 旧 per-bucket 布局仍是真实 payload，迁移前照常计入。
      for (final bucket in knownBuckets) {
        final legacyDir = Directory('$rootPath/$bucket');
        if (!legacyDir.existsSync()) continue;
        for (final entity in legacyDir.listSync(followLinks: false)) {
          if (entity is! File) continue;
          try {
            final stat = entity.statSync();
            diskBytes += stat.size;
            if (_isTempPath(entity.path)) continue;
            payloadBytes += stat.size;
            logicalBytes += stat.size;
            objectCount++;
            bucketBytes[bucket] = (bucketBytes[bucket] ?? 0) + stat.size;
          } catch (_) {}
        }
      }

      return (
        diskBytes: diskBytes,
        payloadBytes: payloadBytes,
        logicalBytes: logicalBytes,
        deduplicatedBytes: deduplicatedBytes,
        objectCount: objectCount,
        referenceCount: referenceCount,
        sharedObjectCount: sharedObjectCount,
        bucketBytes: bucketBytes,
      );
    });

    return BlobImageCacheUsage(
      diskBytes: result.diskBytes,
      payloadBytes: result.payloadBytes,
      logicalBytes: result.logicalBytes,
      deduplicatedBytes: result.deduplicatedBytes,
      objectCount: result.objectCount,
      referenceCount: result.referenceCount,
      sharedObjectCount: result.sharedObjectCount,
      bucketBytes: Map<String, int>.unmodifiable(result.bucketBytes),
    );
  }
}

/// [BlobImageCache] 的 ImageProvider 门面。
@immutable
class BlobImageProvider extends ImageProvider<BlobImageProvider> {
  const BlobImageProvider(
    this.url, {
    required this.bucket,
    this.cacheKey,
    this.scale = 1.0,
    this.priority = DownloadPriority.normal,
  });

  final String url;
  final String bucket;

  /// 可选逻辑 key。不同 key 可以共享同一 URL 的磁盘 object。
  final String? cacheKey;
  final double scale;

  /// 调度提示，不参与图片内容身份。
  final DownloadPriority priority;

  @override
  Future<BlobImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<BlobImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    BlobImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode, chunkEvents),
      chunkEvents: chunkEvents.stream,
      scale: key.scale,
      debugLabel: 'BlobImageProvider(${key.url})',
      informationCollector: () => [
        DiagnosticsProperty<String>('URL', key.url),
        DiagnosticsProperty<String>('Bucket', key.bucket),
        if (key.cacheKey != null)
          DiagnosticsProperty<String>('Cache key', key.cacheKey!),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    BlobImageProvider key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunkEvents,
  ) async {
    try {
      final bytes = await BlobImageCache.fetch(
        key.bucket,
        key.url,
        cacheKey: key.cacheKey,
        priority: key.priority,
        onProgress: (received, total) {
          if (chunkEvents.isClosed) return;
          chunkEvents.add(
            ImageChunkEvent(
              cumulativeBytesLoaded: received,
              expectedTotalBytes: total,
            ),
          );
        },
      );
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return await decode(buffer);
    } catch (e) {
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    } finally {
      unawaited(chunkEvents.close());
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is BlobImageProvider &&
        other.url == url &&
        other.bucket == bucket &&
        other.cacheKey == cacheKey &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(url, bucket, cacheKey, scale);

  @override
  String toString() =>
      'BlobImageProvider("$url", bucket: $bucket, cacheKey: $cacheKey)';
}
