from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, got {count}')
    return text.replace(old, new, 1)

path = Path('lib/services/messaging/matrix_media_service.dart')
text = path.read_text()

text = replace_once(
    text,
    "import 'matrix_message_content.dart';\n",
    "import 'matrix_media_memory_cache.dart';\nimport 'matrix_message_content.dart';\n",
    'media cache import',
)

text = replace_once(
    text,
    "class MatrixMediaService {\n"
    "  MatrixMediaService({required this.session, Dio? dio}) : _dio = dio ?? Dio();\n\n"
    "  static const int defaultDownloadLimitBytes = 64 * 1024 * 1024;\n"
    "  static const int defaultThumbnailLimitBytes = 12 * 1024 * 1024;\n\n"
    "  final MatrixSession session;\n"
    "  final Dio _dio;\n",
    "class MatrixMediaService {\n"
    "  MatrixMediaService({\n"
    "    required this.session,\n"
    "    Dio? dio,\n"
    "    MatrixMediaMemoryCache? previewCache,\n"
    "  }) : _dio = dio ?? Dio(),\n"
    "       _ownsDio = dio == null,\n"
    "       _previewCache = previewCache ?? MatrixMediaMemoryCache();\n\n"
    "  static const int defaultDownloadLimitBytes = 64 * 1024 * 1024;\n"
    "  static const int defaultThumbnailLimitBytes = 12 * 1024 * 1024;\n\n"
    "  final MatrixSession session;\n"
    "  final Dio _dio;\n"
    "  final bool _ownsDio;\n"
    "  final MatrixMediaMemoryCache _previewCache;\n"
    "  final Map<String, Future<Uint8List>> _previewRequests =\n"
    "      <String, Future<Uint8List>>{};\n",
    'media service constructor',
)

text = replace_once(
    text,
    "  Future<Uint8List> downloadBytes(\n"
    "    String contentUri, {\n"
    "    int maxBytes = defaultDownloadLimitBytes,\n"
    "  }) {\n"
    "    return _downloadUriBytes(downloadUri(contentUri), maxBytes: maxBytes);\n"
    "  }\n\n"
    "  Future<Uint8List> downloadThumbnailBytes(\n"
    "    String contentUri, {\n"
    "    int width = 640,\n"
    "    int height = 640,\n"
    "    int maxBytes = defaultThumbnailLimitBytes,\n"
    "  }) {\n"
    "    return _downloadUriBytes(\n"
    "      thumbnailUri(contentUri, width: width, height: height),\n"
    "      maxBytes: maxBytes,\n"
    "    );\n"
    "  }\n",
    "  Future<Uint8List> downloadBytes(\n"
    "    String contentUri, {\n"
    "    int maxBytes = defaultDownloadLimitBytes,\n"
    "  }) {\n"
    "    return _downloadUriBytes(downloadUri(contentUri), maxBytes: maxBytes);\n"
    "  }\n\n"
    "  /// Downloads an already-generated Matrix preview object with bounded\n"
    "  /// LRU caching and in-flight request coalescing.\n"
    "  Future<Uint8List> downloadPreviewBytes(\n"
    "    String contentUri, {\n"
    "    int maxBytes = defaultThumbnailLimitBytes,\n"
    "  }) {\n"
    "    return _cachedPreview(\n"
    "      downloadUri(contentUri),\n"
    "      maxBytes: maxBytes,\n"
    "    );\n"
    "  }\n\n"
    "  Future<Uint8List> downloadThumbnailBytes(\n"
    "    String contentUri, {\n"
    "    int width = 640,\n"
    "    int height = 640,\n"
    "    int maxBytes = defaultThumbnailLimitBytes,\n"
    "  }) {\n"
    "    return _cachedPreview(\n"
    "      thumbnailUri(contentUri, width: width, height: height),\n"
    "      maxBytes: maxBytes,\n"
    "    );\n"
    "  }\n\n"
    "  Future<Uint8List> _cachedPreview(\n"
    "    Uri uri, {\n"
    "    required int maxBytes,\n"
    "  }) {\n"
    "    final key = '${uri.toString()}|limit=$maxBytes';\n"
    "    final cached = _previewCache.get(key);\n"
    "    if (cached != null) return Future<Uint8List>.value(cached);\n\n"
    "    final pending = _previewRequests[key];\n"
    "    if (pending != null) return pending;\n\n"
    "    late final Future<Uint8List> request;\n"
    "    request = _downloadUriBytes(uri, maxBytes: maxBytes)\n"
    "        .then((bytes) {\n"
    "          _previewCache.put(key, bytes);\n"
    "          return bytes;\n"
    "        })\n"
    "        .whenComplete(() {\n"
    "          if (identical(_previewRequests[key], request)) {\n"
    "            _previewRequests.remove(key);\n"
    "          }\n"
    "        });\n"
    "    _previewRequests[key] = request;\n"
    "    return request;\n"
    "  }\n",
    'cached preview methods',
)

text = replace_once(
    text,
    "  Options _authorizedOptions() => Options(\n"
    "    headers: <String, dynamic>{...authorizationHeaders},\n"
    "  );\n",
    "  void dispose() {\n"
    "    _previewRequests.clear();\n"
    "    _previewCache.clear();\n"
    "    if (_ownsDio) {\n"
    "      _dio.close(force: true);\n"
    "    }\n"
    "  }\n\n"
    "  Options _authorizedOptions() => Options(\n"
    "    headers: <String, dynamic>{...authorizationHeaders},\n"
    "  );\n",
    'media service dispose',
)

path.write_text(text)
print('Matrix media transport optimization applied successfully')
