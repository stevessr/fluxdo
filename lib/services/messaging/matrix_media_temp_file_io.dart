import 'dart:convert';
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
  final safeKey = _stableKey(uniqueKey);
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
  } catch (error, stackTrace) {
    if (!closed) {
      try {
        await sink.close();
      } catch (_) {
        // Preserve the original network/filesystem failure below.
      }
    }
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup of an incomplete temporary attachment.
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
}

String _stableKey(String value) {
  // FNV-1a 64-bit keeps the temporary filename deterministic without retaining
  // an arbitrarily long or attacker-controlled Matrix event id in the path.
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

String _safeFilename(String value) {
  final base = p.basename(value.trim());
  final cleaned = base.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
  final normalized = cleaned.isEmpty || cleaned == '.' || cleaned == '..'
      ? 'attachment'
      : cleaned;

  const maxBytes = 160;
  if (utf8.encode(normalized).length <= maxBytes) return normalized;

  final extension = p.extension(normalized);
  final safeExtension = utf8.encode(extension).length <= 24 ? extension : '';
  final stem = safeExtension.isEmpty
      ? normalized
      : normalized.substring(0, normalized.length - safeExtension.length);
  final remainingBytes = maxBytes - utf8.encode(safeExtension).length;
  return '${_truncateUtf8(stem, remainingBytes)}$safeExtension';
}

String _truncateUtf8(String value, int maxBytes) {
  if (maxBytes <= 0) return '';
  final buffer = StringBuffer();
  var used = 0;
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    final size = utf8.encode(char).length;
    if (used + size > maxBytes) break;
    buffer.write(char);
    used += size;
  }
  return buffer.isEmpty ? 'attachment' : buffer.toString();
}
