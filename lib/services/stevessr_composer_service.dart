import 'dart:io';
import 'dart:isolate';

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

typedef StevessrUploadFile =
    Future<UploadResult> Function(String path, bool preserveImageFormat);
typedef StevessrTemporaryDirectory = Future<Directory> Function();

/// 从编辑器快捷入口打开 StevesSR，并把生成结果上传到站点。
abstract final class StevessrComposerService {
  // linux.do's 4 MiB image upload ceiling. Discourse rejects files at or
  // above its configured limit; this is unrelated to JPEG conversion savings.
  static const int maxGeneratorUploadBytes = 4 * 1024 * 1024;

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
  /// 透明 PNG 不能走 Discourse 默认的 PNG -> JPEG 质量转换，否则 alpha 会被
  /// flatten 成白底。这里不再为了躲避服务端转换而把图片强制重编码成 PNG、
  /// 更不会为了卡进 75 KiB 阈值而缩小分辨率；上传层会请求服务端保留原格式。
  ///
  /// 因此，生成器选中的格式、编码质量和像素尺寸都会原样进入上传链路。
  /// 如果服务端实例仍然无视“保留格式”请求并返回 JPEG，则直接拒绝插入，
  /// 避免静默得到白底或低清图片。
  static Future<StevessrUploadedImage> upload(StevessrExportedImage image) {
    return _upload(
      image,
      uploadFile: (path, preserveImageFormat) => DiscourseService().uploadImage(
        path,
        preserveImageFormat: preserveImageFormat,
      ),
      temporaryDirectory: getTemporaryDirectory,
    );
  }

  @visibleForTesting
  static Future<StevessrUploadedImage> uploadForTesting(
    StevessrExportedImage image, {
    required StevessrUploadFile uploadFile,
    required StevessrTemporaryDirectory temporaryDirectory,
  }) {
    return _upload(
      image,
      uploadFile: uploadFile,
      temporaryDirectory: temporaryDirectory,
    );
  }

  static Future<StevessrUploadedImage> _upload(
    StevessrExportedImage image, {
    required StevessrUploadFile uploadFile,
    required StevessrTemporaryDirectory temporaryDirectory,
  }) async {
    // Check the exported payload *before* decoding alpha or writing a file.
    // Never silently downscale/re-encode a user's chosen PNG/WebP/SVG.
    if (image.bytes.length >= maxGeneratorUploadBytes) {
      throw StateError(
        '图片大小已达到或超过 4 MB（linux.do 上传上限），'
        '请手动调整导出尺寸或格式后重试；不会自动降低画质。',
      );
    }

    final directory = await temporaryDirectory();
    final hasTransparency = await _hasTransparency(image);
    final file = await _writeTemporaryImage(directory, image);
    final upload = await uploadFile(file.path, hasTransparency);

    if (hasTransparency && _isJpegUpload(upload)) {
      throw StateError('服务端将透明图片转换为 JPEG，已取消插入以避免透明区域变白');
    }

    final url = upload.url;
    if (url != null) {
      DiscourseImageUtils.seedUploadUrl(upload.shortUrl, url);
    }
    return StevessrUploadedImage(path: file.path, upload: upload);
  }

  static Future<bool> _hasTransparency(StevessrExportedImage source) async {
    final extension = source.extension.toLowerCase();
    if (extension != 'png' && extension != 'webp') return false;

    return Isolate.run(() {
      final decoded = img.decodeImage(source.bytes);
      if (decoded == null || !decoded.hasAlpha) return false;
      return decoded.any((pixel) => pixel.aNormalized < 1.0);
    });
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
