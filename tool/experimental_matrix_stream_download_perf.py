from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, got {count}')
    return text.replace(old, new, 1)

service_path = Path('lib/services/messaging/matrix_media_service.dart')
service = service_path.read_text()
service = replace_once(
    service,
    "class MatrixMediaUpload {\n",
    "class MatrixMediaDownload {\n"
    "  const MatrixMediaDownload({\n"
    "    required this.stream,\n"
    "    this.contentLength,\n"
    "  });\n\n"
    "  final Stream<List<int>> stream;\n"
    "  final int? contentLength;\n"
    "}\n\n"
    "class MatrixMediaUpload {\n",
    'media download model',
)
service = replace_once(
    service,
    "  static const int defaultDownloadLimitBytes = 64 * 1024 * 1024;\n"
    "  static const int defaultThumbnailLimitBytes = 12 * 1024 * 1024;\n",
    "  static const int defaultDownloadLimitBytes = 64 * 1024 * 1024;\n"
    "  static const int defaultFileDownloadLimitBytes = 512 * 1024 * 1024;\n"
    "  static const int defaultThumbnailLimitBytes = 12 * 1024 * 1024;\n",
    'file download limit',
)
service = replace_once(
    service,
    "  Future<Uint8List> downloadBytes(\n"
    "    String contentUri, {\n"
    "    int maxBytes = defaultDownloadLimitBytes,\n"
    "  }) {\n"
    "    return _downloadUriBytes(downloadUri(contentUri), maxBytes: maxBytes);\n"
    "  }\n",
    "  Future<MatrixMediaDownload> openDownload(\n"
    "    String contentUri, {\n"
    "    int maxBytes = defaultFileDownloadLimitBytes,\n"
    "  }) {\n"
    "    return _openUriDownload(downloadUri(contentUri), maxBytes: maxBytes);\n"
    "  }\n\n"
    "  Future<Uint8List> downloadBytes(\n"
    "    String contentUri, {\n"
    "    int maxBytes = defaultDownloadLimitBytes,\n"
    "  }) {\n"
    "    return _downloadUriBytes(downloadUri(contentUri), maxBytes: maxBytes);\n"
    "  }\n",
    'open download API',
)
start = service.find('  Future<Uint8List> _downloadUriBytes(')
end = service.find('  static MatrixMxcUri? parseMxcUri', start)
if start == -1 or end == -1 or end <= start:
    raise SystemExit('download implementation block not found')
new_download_impl = r'''  Future<MatrixMediaDownload> _openUriDownload(
    Uri uri, {
    required int maxBytes,
  }) async {
    if (maxBytes <= 0) {
      throw const MatrixMediaException('下载大小上限必须大于 0。');
    }
    try {
      final response = await _dio.get<ResponseBody>(
        uri.toString(),
        options: Options(
          headers: authorizationHeaders,
          responseType: ResponseType.stream,
        ),
      );
      final declaredLength = int.tryParse(
        response.headers.value(Headers.contentLengthHeader) ?? '',
      );
      if (declaredLength != null && declaredLength > maxBytes) {
        throw MatrixMediaException(
          'Matrix media 大小 $declaredLength bytes 超过客户端上限 $maxBytes bytes。',
        );
      }
      final body = response.data;
      if (body == null) {
        throw const MatrixMediaException('Matrix media download 返回空内容。');
      }

      Stream<List<int>> boundedStream() async* {
        var received = 0;
        try {
          await for (final chunk in body.stream) {
            received += chunk.length;
            if (received > maxBytes) {
              throw MatrixMediaException(
                'Matrix media 下载超过客户端上限 $maxBytes bytes，已中止。',
              );
            }
            yield chunk;
          }
        } on DioException catch (error) {
          throw MatrixMediaException(_matrixErrorMessage(error));
        }
      }

      return MatrixMediaDownload(
        stream: boundedStream(),
        contentLength: declaredLength,
      );
    } on DioException catch (error) {
      throw MatrixMediaException(_matrixErrorMessage(error));
    }
  }

  Future<Uint8List> _downloadUriBytes(
    Uri uri, {
    required int maxBytes,
  }) async {
    final download = await _openUriDownload(uri, maxBytes: maxBytes);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in download.stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

'''
service = service[:start] + new_download_impl + service[end:]
service_path.write_text(service)

# Conditional saver keeps dart:io out of Web while writing desktop/mobile
# attachments chunk-by-chunk to the temporary directory.
Path('lib/services/messaging/matrix_media_temp_file.dart').write_text(
    "export 'matrix_media_temp_file_stub.dart'\n"
    "    if (dart.library.io) 'matrix_media_temp_file_io.dart';\n"
)
Path('lib/services/messaging/matrix_media_temp_file_stub.dart').write_text(r'''Future<String> saveMatrixMediaStreamToTemp({
  required Stream<List<int>> stream,
  required String filename,
  required String uniqueKey,
}) async {
  throw UnsupportedError('Matrix temporary-file downloads are unavailable here.');
}
''')
Path('lib/services/messaging/matrix_media_temp_file_io.dart').write_text(r'''import 'dart:io';

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
''')

view_path = Path('lib/pages/chat/matrix_message_media_view.dart')
view = view_path.read_text()
view = replace_once(
    view,
    "import 'package:cross_file/cross_file.dart';\n",
    '',
    'remove XFile import',
)
view = replace_once(
    view,
    "import 'package:path/path.dart' as p;\n"
    "import 'package:path_provider/path_provider.dart';\n\n"
    "import '../../services/matrix_client_service.dart';\n"
    "import '../../services/messaging/matrix_media_service.dart';\n",
    "import '../../services/matrix_client_service.dart';\n"
    "import '../../services/messaging/matrix_media_service.dart';\n"
    "import '../../services/messaging/matrix_media_temp_file.dart';\n",
    'media view stream saver imports',
)
old_file_download = r'''      final bytes = await _media.downloadBytes(uri);
      final temp = await getTemporaryDirectory();
      final safeName = _safeFilename(widget.message.filename ?? widget.message.body);
      final path = p.join(temp.path, 'fluxdo-matrix-${widget.message.eventId.hashCode}-$safeName');
      final file = XFile.fromData(bytes, name: safeName);
      await file.saveTo(path);
      final result = await OpenFilex.open(path);
'''
new_file_download = r'''      final knownSize = widget.message.mediaSize;
      if (knownSize != null &&
          knownSize > MatrixMediaService.defaultFileDownloadLimitBytes) {
        throw MatrixMediaException(
          '附件 ${_formatBytes(knownSize)} 超过当前流式下载上限 '
          '${_formatBytes(MatrixMediaService.defaultFileDownloadLimitBytes)}。',
        );
      }
      final download = await _media.openDownload(
        uri,
        maxBytes: MatrixMediaService.defaultFileDownloadLimitBytes,
      );
      final path = await saveMatrixMediaStreamToTemp(
        stream: download.stream,
        filename: widget.message.filename ?? widget.message.body,
        uniqueKey: widget.message.eventId,
      );
      final result = await OpenFilex.open(path);
'''
view = replace_once(view, old_file_download, new_file_download, 'stream file download')
start = view.find('  static String _safeFilename(')
end = view.find('  @override\n  Widget build', start)
if start == -1 or end == -1 or end <= start:
    raise SystemExit('obsolete safe filename helper not found')
view = view[:start] + view[end:]
view_path.write_text(view)

print('Streamed Matrix attachment downloads staged successfully')
