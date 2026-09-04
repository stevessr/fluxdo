import 'package:flutter/painting.dart';
import 'package:native_animated_image/native_animated_image.dart'
    show NativeAnimatedImageProvider;
import 'avif_image_provider.dart';
export 'avif_image_provider.dart' show AvifImageProvider;
import 'blob_image_cache.dart';
export 'blob_image_cache.dart' show BlobImageCache, BlobImageProvider;
import 'dio_http_client.dart' show DownloadPriority;
export 'dio_http_client.dart' show DownloadPriority;

/// 旧 flutter_cache_manager 时代的缓存 cacheKey(2026-07 全量退役,
/// 仅供迁移 v7/v8/v9 清理旧目录与 db 引用)。
///
/// 当时每个 key 同时是 sqlite 索引库文件名(ApplicationSupport/{key}.db)
/// 与缓存文件目录名(Temporary/{key}/)。现全部图片走 [BlobImageCache]
/// 零索引寻址。
const List<String> kLegacyImageCacheKeys = [
  'discourseImageCache',
  kLegacyEmojiCacheKey,
  'externalImageCache',
  'stickerImageCache',
];

/// 旧 emoji 缓存的 cacheKey(仅供迁移/清理引用)。
const String kLegacyEmojiCacheKey = 'emojiImageCache';

/// 检查 URL 是否指向 AVIF 图片
bool _isAvifUrl(String url) {
  try {
    final path = Uri.parse(url).path.toLowerCase();
    return path.endsWith('.avif');
  } catch (_) {
    return false;
  }
}

/// Discourse 头像通常位于 `/user_avatar/<host>/<username>/...`。
///
/// 头像是 UI 里透明像素最常见的一类图片；把这个识别集中在 provider
/// router 中，避免每个头像组件各自猜格式/路径。调用方显式传
/// [BlobImageCache.avatarBucket] 时不依赖 URL 形状，也会进入头像路径。
bool _isAvatarUrl(String url) {
  try {
    return Uri.parse(url).path.toLowerCase().contains('/user_avatar/');
  } catch (_) {
    return url.toLowerCase().contains('/user_avatar/');
  }
}

/// 检查 URL 是否指向需要走 native 解码器的动图(GIF / APNG / 动画 WebP)
///
/// 走 native_animated_image 的 Rust pipeline,绕开 Flutter Skia
/// multi_frame_codec 的 #85831 bug。
bool isNativeAnimatedUrl(String url) => _isNativeAnimatedUrl(url);

bool _isNativeAnimatedUrl(String url) {
  try {
    final path = Uri.parse(url).path.toLowerCase();
    // .gif 一定走 native(Skia 在某些 disposal 组合下会失败)
    // .apng / .webp 也走 native(后续 Rust 端补全解码器)
    return path.endsWith('.gif') ||
        path.endsWith('.apng') ||
        path.endsWith('.webp');
  } catch (_) {
    return false;
  }
}

/// 创建 Discourse 图片 Provider
///
/// 用于需要 ImageProvider 的场景（CircleAvatar、DecorationImage 等）
/// - AVIF URL → AvifImageProvider (flutter_avif libavif + dav1d)
/// - GIF / APNG / 动画 WebP → NativeAnimatedImageProvider (Rust pipeline,
///   绕 Skia multi_frame_codec 的 #85831 bug)
/// - **头像**动图例外：使用 [BlobImageProvider] 的标准 encoded-image codec。
///   native_animated_image 的 Rust 路径把 straight RGBA 原始像素交给
///   `decodeImageFromPixels`;在部分透明/半透明头像上会出现透明区被黑色
///   污染或黑边。标准 codec 从原始编码直接解码，alpha / premultiply
///   语义由 Flutter engine 统一处理，透明像素可正确透出下层 UI。
/// - 其他静态格式 → BlobImageProvider(content bucket,零 sqlite 寻址)
///
/// 头像例外只影响 avatar，不把正文动图重新暴露给旧的 GIF disposal bug；
/// [MultiFrameImageStreamCompleter] 仍会让 GIF/APNG/WebP 正常播放。
///
/// 需要限制解码尺寸时在外层包 decode-time 的 `ResizeImage(policy: fit)`。
ImageProvider discourseImageProvider(
  String url, {
  double scale = 1.0,
  String bucket = BlobImageCache.contentBucket,
  DownloadPriority priority = DownloadPriority.normal,
}) {
  // SmartAvatar 历史调用没有显式传 avatar bucket。按 Discourse 头像 URL
  // 自动纠正到全局 avatar bucket：既保证跨 profile 共用唯一头像缓存，
  // 也让下面的 alpha-safe 路由稳定生效。
  final effectiveBucket =
      bucket == BlobImageCache.contentBucket && _isAvatarUrl(url)
      ? BlobImageCache.avatarBucket
      : bucket;

  if (_isAvifUrl(url)) {
    return AvifImageProvider(url, scale: scale, bucket: effectiveBucket);
  }
  if (_isNativeAnimatedUrl(url)) {
    if (effectiveBucket == BlobImageCache.avatarBucket) {
      return BlobImageProvider(
        url,
        bucket: effectiveBucket,
        scale: scale,
        priority: priority,
      );
    }
    return NativeAnimatedImageProvider.fromBytesProvider(
      loader: () =>
          BlobImageCache.fetch(effectiveBucket, url, priority: priority),
      tag: url,
      scale: scale,
    );
  }
  return BlobImageProvider(
    url,
    bucket: effectiveBucket,
    scale: scale,
    priority: priority,
  );
}

/// 创建站点配置/装饰图片 Provider。
///
/// 群组 flair、站点配置中引用的图标/图片等都不属于账号会话状态。
/// 统一放进全局 [BlobImageCache.externalBucket]（30 天）而不是 7 天的正文
/// content bucket；缓存身份只由 URL + bucket 构成，账号切换时直接复用，
/// 也不会随着账号快照保存、迁移或清理。
ImageProvider siteAssetImageProvider(
  String url, {
  double scale = 1.0,
  DownloadPriority priority = DownloadPriority.normal,
}) {
  return discourseImageProvider(
    url,
    scale: scale,
    bucket: BlobImageCache.externalBucket,
    priority: priority,
  );
}

/// 创建 Emoji 图片 Provider
///
/// 走 [BlobImageCache](Telegram 式 MD5 确定性寻址,零 sqlite 索引)。
/// emoji 全集实测 100% 静态 PNG,单一路径即可;64px 目标尺寸走解码
/// 闸门的小图旁路,由引擎 worker 池并行解码。
ImageProvider emojiImageProvider(String url, {double scale = 1.0}) {
  return BlobImageProvider(
    url,
    bucket: BlobImageCache.emojiBucket,
    scale: scale,
  );
}

/// 创建表情包（Sticker）图片 Provider
///
/// 原文件走 stickerOriginal bucket;AVIF URL 自动使用 AvifImageProvider 解码
ImageProvider stickerImageProvider(String url, {double scale = 1.0}) {
  if (_isAvifUrl(url)) {
    return AvifImageProvider(
      url,
      scale: scale,
      bucket: BlobImageCache.stickerOriginalBucket,
    );
  }
  return BlobImageProvider(
    url,
    bucket: BlobImageCache.stickerOriginalBucket,
    scale: scale,
  );
}
