import 'dart:io';

import 'package:flutter/material.dart';
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

/// 从编辑器快捷入口打开 StevesSR，并把生成结果上传到站点。
abstract final class StevessrComposerService {
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
  static Future<StevessrUploadedImage> upload(
    StevessrExportedImage image,
  ) async {
    final directory = await getTemporaryDirectory();
    final filename =
        'stevessr_${DateTime.now().microsecondsSinceEpoch}.${image.extension}';
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(image.bytes, flush: true);
    final upload = await DiscourseService().uploadImage(file.path);
    final url = upload.url;
    if (url != null) {
      DiscourseImageUtils.seedUploadUrl(upload.shortUrl, url);
    }
    return StevessrUploadedImage(path: file.path, upload: upload);
  }
}
