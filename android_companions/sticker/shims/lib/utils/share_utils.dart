import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Companion-local sharing. Never connects to FluxDO accounts or storage.
class ShareOutcome {
  const ShareOutcome({required this.shared, this.finalPath});
  final bool shared;
  final String? finalPath;
}

abstract final class ShareUtils {
  static bool get canShareFiles => true;

  static Future<File> createOutboxFile(String name) async {
    final directory = await getTemporaryDirectory();
    final destination = Directory('${directory.path}/exports');
    await destination.create(recursive: true);
    return File('${destination.path}/${name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}');
  }

  static Future<ShareOutcome> shareFile(XFile file, {String? subject}) async {
    await SharePlus.instance.share(ShareParams(files: [file], subject: subject));
    return const ShareOutcome(shared: true);
  }

  static Future<ShareOutcome> saveFileAs(XFile file) async {
    final content = await file.readAsBytes();
    final name = file.name.isEmpty ? 'stevessr' : file.name;
    final saved = await FilePicker.platform.saveFile(
      dialogTitle: '保存图片',
      fileName: name,
      bytes: content,
    );
    return ShareOutcome(shared: saved != null, finalPath: saved);
  }
}
