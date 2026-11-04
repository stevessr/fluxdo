import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../blob_image_cache.dart';
import '../discourse_cache_manager.dart';

/// 图片缓存分类（Telegram Storage Usage 式明细的口径）。
enum ImageCacheCategory { content, emoji, avatar, sticker, external, other }

/// 图片缓存的 UI 统计快照。
///
/// [physicalBytes] 是实际磁盘占用；[breakdown] 是按用途计算的逻辑大小。
/// 同一 URL 被多个用途引用时，分类之和可以大于实际占用，这是共享缓存
/// 的预期结果；[deduplicatedBytes] 表示因此避免保存的重复 payload 大小。
class ImageCacheUsage {
  const ImageCacheUsage({
    required this.breakdown,
    required this.physicalBytes,
    required this.logicalBytes,
    required this.deduplicatedBytes,
    required this.objectCount,
    required this.referenceCount,
    required this.sharedObjectCount,
  });

  final Map<ImageCacheCategory, int> breakdown;
  final int physicalBytes;
  final int logicalBytes;
  final int deduplicatedBytes;
  final int objectCount;
  final int referenceCount;
  final int sharedObjectCount;
}

/// 缓存大小计算服务。
class CacheSizeService {
  /// 统计/删除口径：blob 缓存根目录 + legacy cache_manager 残留目录。
  static const _cacheKeys = [BlobImageCache.dirName, ...kLegacyImageCacheKeys];

  /// 获取共享图片缓存完整统计。
  ///
  /// Blob 主体统计已经在 isolate 中完成；这里只聚合旧 cache_manager
  /// 残留和迁移 `.trash`，让数据管理页可以一次请求拿到一致快照。
  static Future<ImageCacheUsage> getImageCacheUsage() async {
    final tempDir = await getTemporaryDirectory();
    final blobFuture = BlobImageCache.getUsage();
    final otherFuture = _getOtherImageCacheSize(tempDir);
    final results = await Future.wait([blobFuture, otherFuture]);
    final blob = results[0] as BlobImageCacheUsage;
    final other = results[1] as int;
    final b = blob.bucketBytes;

    final breakdown = <ImageCacheCategory, int>{
      ImageCacheCategory.content:
          (b[BlobImageCache.contentBucket] ?? 0) +
          (b[BlobImageCache.originalBucket] ?? 0),
      ImageCacheCategory.emoji: b[BlobImageCache.emojiBucket] ?? 0,
      ImageCacheCategory.avatar: b[BlobImageCache.avatarBucket] ?? 0,
      ImageCacheCategory.sticker:
          (b[BlobImageCache.stickerOriginalBucket] ?? 0) +
          (b[BlobImageCache.stickerThumbBucket] ?? 0),
      ImageCacheCategory.external: b[BlobImageCache.externalBucket] ?? 0,
      ImageCacheCategory.other: other,
    };

    return ImageCacheUsage(
      breakdown: Map<ImageCacheCategory, int>.unmodifiable(breakdown),
      physicalBytes: blob.diskBytes + other,
      logicalBytes: blob.logicalBytes + other,
      deduplicatedBytes: blob.deduplicatedBytes,
      objectCount: blob.objectCount,
      referenceCount: blob.referenceCount,
      sharedObjectCount: blob.sharedObjectCount,
    );
  }

  /// 计算图片缓存真实磁盘占用。
  static Future<int> getImageCacheSize() async =>
      (await getImageCacheUsage()).physicalBytes;

  /// 按分类统计图片缓存逻辑大小。
  ///
  /// 为旧调用方保留；共享 URL 可能被多个分类引用，因此这里的总和不再
  /// 等价于物理磁盘占用。需要展示总量时应使用 [getImageCacheUsage]。
  static Future<Map<ImageCacheCategory, int>> getImageCacheBreakdown() async =>
      (await getImageCacheUsage()).breakdown;

  static Future<int> _getOtherImageCacheSize(Directory tempDir) async {
    var total = 0;
    final t = tempDir.path;
    for (final key in kLegacyImageCacheKeys) {
      total += await _getDirectorySize(Directory('$t/$key'));
    }
    for (final dir in await _trashDirs(tempDir)) {
      total += await _getDirectorySize(dir);
    }
    return total;
  }

  /// 按分类清除图片缓存。
  static Future<void> clearImageCacheCategory(
    ImageCacheCategory category,
  ) async {
    final tempDir = await getTemporaryDirectory();

    Future<void> deleteDir(String key) async {
      final dir = Directory('${tempDir.path}/$key');
      if (await dir.exists()) await dir.delete(recursive: true);
    }

    switch (category) {
      case ImageCacheCategory.content:
        await BlobImageCache.clearBucket(BlobImageCache.contentBucket);
        await BlobImageCache.clearBucket(BlobImageCache.originalBucket);
      case ImageCacheCategory.emoji:
        await BlobImageCache.clearBucket(BlobImageCache.emojiBucket);
      case ImageCacheCategory.avatar:
        await BlobImageCache.clearBucket(BlobImageCache.avatarBucket);
      case ImageCacheCategory.sticker:
        await BlobImageCache.clearBucket(BlobImageCache.stickerOriginalBucket);
        await BlobImageCache.clearBucket(BlobImageCache.stickerThumbBucket);
      case ImageCacheCategory.external:
        await BlobImageCache.clearBucket(BlobImageCache.externalBucket);
      case ImageCacheCategory.other:
        for (final key in kLegacyImageCacheKeys) {
          await deleteDir(key);
        }
        for (final dir in await _trashDirs(tempDir)) {
          try {
            await dir.delete(recursive: true);
          } catch (_) {}
        }
    }
  }

  /// 计算 AI 聊天数据大小（SharedPreferences 中 ai_chat_ 开头的 key）。
  static Future<int> getAiChatDataSize(SharedPreferences prefs) async {
    int totalSize = 0;
    for (final key in prefs.getKeys()) {
      if (key.startsWith('ai_chat_')) {
        final value = prefs.get(key);
        if (value is String) {
          totalSize += value.length * 2;
        } else if (value is List<String>) {
          for (final item in value) {
            totalSize += item.length * 2;
          }
        }
      }
    }
    return totalSize;
  }

  /// 计算 Cookie 缓存大小（.cookies 目录）。
  static Future<int> getCookieCacheSize() async {
    final docDir = await getApplicationDocumentsDirectory();
    return _getDirectorySize(Directory('${docDir.path}/.cookies'));
  }

  /// 递归计算目录大小。
  static Future<int> _getDirectorySize(Directory dir) async {
    if (!await dir.exists()) return 0;
    int totalSize = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }

  /// 删除所有图片缓存目录。
  static Future<void> deleteImageCacheDirs() async {
    final tempDir = await getTemporaryDirectory();
    for (final key in _cacheKeys) {
      final dir = Directory('${tempDir.path}/$key');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
    for (final dir in await _trashDirs(tempDir)) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Temporary 下迁移产生的 `*.trash` 待删目录。
  static Future<List<Directory>> _trashDirs(Directory tempDir) async {
    final result = <Directory>[];
    try {
      await for (final entity in tempDir.list()) {
        if (entity is Directory && entity.path.endsWith('.trash')) {
          result.add(entity);
        }
      }
    } catch (_) {}
    return result;
  }

  /// 格式化字节为可读字符串。
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
