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
    "  static const int defaultDownloadLimitBytes = 64 * 1024 * 1024;\n"
    "  static const int defaultFileDownloadLimitBytes = 512 * 1024 * 1024;\n"
    "  static const int defaultThumbnailLimitBytes = 12 * 1024 * 1024;\n",
    "  static const int defaultDownloadLimitBytes = 64 * 1024 * 1024;\n"
    "  static const int defaultFileDownloadLimitBytes = 512 * 1024 * 1024;\n"
    "  static const int defaultThumbnailLimitBytes = 12 * 1024 * 1024;\n"
    "  static const Duration mediaConfigCacheTtl = Duration(minutes: 5);\n",
    'media config TTL constant',
)
text = replace_once(
    text,
    "  final Map<String, Future<Uint8List>> _previewRequests =\n"
    "      <String, Future<Uint8List>>{};\n",
    "  final Map<String, Future<Uint8List>> _previewRequests =\n"
    "      <String, Future<Uint8List>>{};\n"
    "  DateTime? _mediaConfigFetchedAt;\n"
    "  int? _cachedMaxUploadBytes;\n"
    "  bool _hasMediaConfigCache = false;\n",
    'media config cache fields',
)
old = '''  Future<int?> maxUploadBytes() async {
    try {
      final response = await _dio.get<dynamic>(
        '${session.homeserver}/_matrix/client/v1/media/config',
        options: _authorizedOptions(),
      );
      final data = _asMap(response.data);
      final value = data['m.upload.size'];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    } on DioException catch (error) {
      throw MatrixMediaException(_matrixErrorMessage(error));
    }
  }
'''
new = '''  Future<int?> maxUploadBytes({bool forceRefresh = false}) async {
    final now = DateTime.now();
    final fetchedAt = _mediaConfigFetchedAt;
    if (!forceRefresh &&
        _hasMediaConfigCache &&
        fetchedAt != null &&
        now.difference(fetchedAt) < mediaConfigCacheTtl) {
      return _cachedMaxUploadBytes;
    }

    try {
      final response = await _dio.get<dynamic>(
        '${session.homeserver}/_matrix/client/v1/media/config',
        options: _authorizedOptions(),
      );
      final data = _asMap(response.data);
      final value = data['m.upload.size'];
      final parsed = switch (value) {
        int number => number,
        num number => number.toInt(),
        _ => int.tryParse(value?.toString() ?? ''),
      };
      _cachedMaxUploadBytes = parsed != null && parsed >= 0 ? parsed : null;
      _mediaConfigFetchedAt = now;
      _hasMediaConfigCache = true;
      return _cachedMaxUploadBytes;
    } on DioException catch (error) {
      // Do not cache transient network failures; the next upload may retry.
      throw MatrixMediaException(_matrixErrorMessage(error));
    }
  }
'''
text = replace_once(text, old, new, 'max upload cache')
text = replace_once(
    text,
    "  void dispose() {\n"
    "    _previewRequests.clear();\n"
    "    _previewCache.clear();\n",
    "  void dispose() {\n"
    "    _previewRequests.clear();\n"
    "    _previewCache.clear();\n"
    "    _mediaConfigFetchedAt = null;\n"
    "    _cachedMaxUploadBytes = null;\n"
    "    _hasMediaConfigCache = false;\n",
    'dispose media config cache',
)
path.write_text(text)
print('Matrix media config cache staged successfully')
