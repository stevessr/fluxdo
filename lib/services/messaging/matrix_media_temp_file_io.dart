import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> saveMatrixMediaStreamToTemp({
  required Stream<List<int>> stream,
  required String filename,
  required String uniqueKey,
}) async {
  final temp = await getTemporaryDirectory();
  final safeName = _safeFilename(filename);
  final safeKey = uniqueKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final path = p.join(temp.path, 'fluxdo-matrix-$safeKey-$safeName');
  final file = File(path);
  final sink = file.openWrite(mode: FileMode.writeOnly);
  var closed = false;
  try {
    await for (final chunk in stream) {
      sink.add(chunk);
    }
    await sink.flush();
    await sink.close();
    closed = true;
    return path;
  } catch (_) {
    if (!closed) {
      await sink.close();
    }
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup of an incomplete temporary attachment.
    }
    rethrow;
  }
}

String _safeFilename(String value) {
  final base = p.basename(value.trim());
  final cleaned = base.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
  return cleaned.isEmpty || cleaned == '.' || cleaned == '..'
      ? 'attachment'
      : cleaned;
}
