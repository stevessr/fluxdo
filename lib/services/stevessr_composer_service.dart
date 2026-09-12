import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../pages/stevessr_generator_page.dart';
import '../widgets/content/discourse_html_content/image_utils.dart';
import 'discourse/discourse_service.dart';
import 'stevessr_export_service.dart';

/// 已上传的 StevesSR 图片，供帖子编辑器和聊天附件共用。
class StevessrUploadedImage {
  const StevessrUploadedImage({required this.path, required this.upload});

  final String path;
  final UploadResult upload;
}

typedef StevessrUploadFile = Future<UploadResult> Function(String path);
typedef StevessrTemporaryDirectory = Future<Directory> Function();

/// 从编辑器快捷入口打开 StevesSR，并把生成结果上传到站点。
abstract final class StevessrComposerService {
  // Discourse UploadCreator 当前只会实际进行 PNG/WebP -> JPEG 质量转换，
  // 当源文件至少达到 75,000 bytes。留出余量，不贴着服务端阈值上传。
  static const int _transparentUploadMaxBytes = 72 * 1024;
  static const int _transparentRetryMaxBytes = 48 * 1024;
  static const int _minimumUploadDimension = 64;

  /// 打开生成器，点击「生成并插入」后上传图片并返回附件信息。
  /// 用户取消时返回 null。
  static Future<StevessrUploadedImage?> openAndUpload(BuildContext context) {
    return Navigator.of(context).push<StevessrUploadedImage>(
      MaterialPageRoute(
        builder: (pageContext) => StevessrGeneratorPage(
          onInsert: (image) async {
            final uploaded = await upload(image);
            if (pageContext.mounted) {
              Navigator.of(pageContext).pop(uploaded);
            }
          },
        ),
      ),
    );
  }

  /// 将生成结果写入临时文件并上传。
  ///
  /// Discourse 会根据站点隐藏的图片质量设置，把较大的 PNG 转成 JPEG；
  /// 该转换会用白色背景 flatten，透明像素因此会变白。对确实含 alpha 的
  /// raster 图片，仅对“上传副本”做 PNG 无损重编码并在必要时逐步缩放，
  /// 保证文件低于服务端 JPEG 转换的最小收益阈值。本地保存/分享仍使用原图。
  ///
  /// 如果服务端仍返回 JPEG（例如实例修改了上游阈值），再用更保守的体积
  /// 上限重试一次；第二次仍被转成 JPEG 时直接报错，绝不静默插入白底图。
  static Future<StevessrUploadedImage> upload(
    StevessrExportedImage image, {
    @visibleForTesting StevessrUploadFile? uploadFile,
    @visibleForTesting StevessrTemporaryDirectory? temporaryDirectory,
  }) async {
    final uploader = uploadFile ?? DiscourseService().uploadImage;
    final getDirectory = temporaryDirectory ?? getTemporaryDirectory;
    final directory = await getDirectory();

    var prepared = await _prepareTransparentRaster(
      image,
      maxBytes: _transparentUploadMaxBytes,
    );
    var file = await _writeTemporaryImage(directory, prepared.image);
    var upload = await uploader(file.path);

    if (prepared.hasTransparency && _isJpegUpload(upload)) {
      prepared = await _prepareTransparentRaster(
        image,
        maxBytes: _transparentRetryMaxBytes,
        forcePngReencode: true,
      );
      file = await _writeTemporaryImage(
        directory,
        prepared.image,
        suffix: '_alpha_retry',
      );
      upload = await uploader(file.path);

      if (_isJpegUpload(upload)) {
        throw StateError('服务端仍将透明图片转换为 JPEG，已取消插入以避免透明区域变白');
      }
    }

    final url = upload.url;
    if (url != null) {
      DiscourseImageUtils.seedUploadUrl(upload.shortUrl, url);
    }
    return StevessrUploadedImage(path: file.path, upload: upload);
  }

  @visibleForTesting
  static Future<StevessrExportedImage> prepareTransparentUploadForTesting(
    StevessrExportedImage image, {
    int maxBytes = _transparentUploadMaxBytes,
  }) async {
    final prepared = await _prepareTransparentRaster(
      image,
      maxBytes: maxBytes,
    );
    return prepared.image;
  }

  static Future<({StevessrExportedImage image, bool hasTransparency})>
  _prepareTransparentRaster(
    StevessrExportedImage source, {
    required int maxBytes,
    bool forcePngReencode = false,
  }) async {
    final extension = source.extension.toLowerCase();
    if (extension != 'png' && extension != 'webp') {
      return (image: source, hasTransparency: false);
    }

    final result = await Isolate.run(() {
      final decoded = img.decodeImage(source.bytes);
      if (decoded == null ||
          !decoded.hasAlpha ||
          !decoded.any((pixel) => pixel.aNormalized < 1.0)) {
        return (bytes: source.bytes, hasTransparency: false);
      }

      if (!forcePngReencode && source.bytes.length <= maxBytes) {
        return (bytes: source.bytes, hasTransparency: true);
      }

      var working = decoded;
      var encoded = Uint8List.fromList(img.encodePng(working));

      while (encoded.length > maxBytes &&
          (working.width > _minimumUploadDimension ||
              working.height > _minimumUploadDimension)) {
        final estimatedScale = math.sqrt(maxBytes / encoded.length) * 0.92;
        final scale = estimatedScale.clamp(0.50, 0.90).toDouble();
        final nextWidth = math.max(
          _minimumUploadDimension,
          (working.width * scale).floor(),
        );
        final nextHeight = math.max(
          _minimumUploadDimension,
          (working.height * scale).floor(),
        );

        if (nextWidth == working.width && nextHeight == working.height) break;

        working = img.copyResize(
          working,
          width: nextWidth,
          height: nextHeight,
          interpolation: img.Interpolation.linear,
        );
        encoded = Uint8List.fromList(img.encodePng(working));
      }

      if (encoded.length > maxBytes) {
        throw StateError('无法在保留透明度的同时生成可安全上传的 PNG');
      }

      return (bytes: encoded, hasTransparency: true);
    });

    if (!result.hasTransparency ||
        (!forcePngReencode && result.bytes.length == source.bytes.length)) {
      return (image: source, hasTransparency: result.hasTransparency);
    }

    return (
      image: StevessrExportedImage(
        bytes: result.bytes,
        extension: 'png',
        mimeType: 'image/png',
      ),
      hasTransparency: true,
    );
  }

  static Future<File> _writeTemporaryImage(
    Directory directory,
    StevessrExportedImage image, {
    String suffix = '',
  }) async {
    final filename =
        'stevessr_${DateTime.now().microsecondsSinceEpoch}$suffix.${image.extension}';
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(image.bytes, flush: true);
    return file;
  }

  static bool _isJpegUpload(UploadResult upload) {
    final extension = upload.extension?.toLowerCase().replaceFirst('.', '');
    if (extension == 'jpg' || extension == 'jpeg') return true;

    final filename = upload.originalFilename.toLowerCase();
    if (filename.endsWith('.jpg') || filename.endsWith('.jpeg')) return true;

    final url = upload.url?.toLowerCase();
    return url != null && (url.endsWith('.jpg') || url.endsWith('.jpeg'));
  }
}
