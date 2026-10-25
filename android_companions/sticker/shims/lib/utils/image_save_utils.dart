import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:gal/gal.dart';

import 'share_utils.dart';

abstract final class ImageSaveUtils {
  static Future<bool> saveBytes(
    Uint8List bytes, {
    required String fileName,
  }) async {
    if (bytes.isEmpty) return false;
    // On Android preserve user's chosen encoded format. For unsupported
    // gallery formats, use the system document picker without re-encoding.
    final ext = fileName.split('.').last.toLowerCase();
    if (ext == 'png' || ext == 'jpg' || ext == 'jpeg') {
      try {
        await Gal.putImageBytes(bytes);
        return true;
      } catch (_) {
        // No gallery access or unsupported platform: fall back to SAF.
      }
    }
    final file = await ShareUtils.createOutboxFile(fileName);
    await file.writeAsBytes(bytes, flush: true);
    return (await ShareUtils.saveFileAs(XFile(file.path))).shared;
  }
}
