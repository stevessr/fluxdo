import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import '../utils/share_utils.dart';

/// Only the cross-APK wire type remains in Android Core. No drawing,
/// character source, image encoder or renderer is reachable from this file.
class StevessrExportedImage {
  const StevessrExportedImage({
    required this.bytes,
    required this.extension,
    required this.mimeType,
    this.containsTransparency,
  });

  final Uint8List bytes;
  final String extension;
  final String mimeType;
  final bool? containsTransparency;
}

abstract final class StevessrExportService {
  static Future<bool> save(StevessrExportedImage image) async {
    final file = await ShareUtils.createOutboxFile(
      'stevessr.${image.extension}',
    );
    await file.writeAsBytes(image.bytes, flush: true);
    final outcome = await ShareUtils.saveFile(
      XFile(file.path, mimeType: image.mimeType),
    );
    return outcome.shared;
  }

  static Future<ShareOutcome> share(StevessrExportedImage image) async {
    final file = await ShareUtils.createOutboxFile(
      'stevessr.${image.extension}',
    );
    await file.writeAsBytes(image.bytes, flush: true);
    return ShareUtils.shareFile(
      XFile(file.path, mimeType: image.mimeType),
      subject: '表情包',
    );
  }
}
