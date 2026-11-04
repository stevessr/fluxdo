import 'package:dio/dio.dart';

import '../models/mini_app.dart';

/// Fetches the site app directory through the shared authenticated Dio stack.
///
/// Prefer the directory endpoint. A legacy endpoint is only probed on a real
/// 404/405, not on 401/403/429, a Cloudflare challenge, or a network failure.
/// Remember a working endpoint across pages to avoid repeated failed probes.
class MiniAppDirectoryRepository {
  MiniAppDirectoryRepository({required Dio dio, required Uri site})
      : _dio = dio,
        _site = site;

  final Dio _dio;
  final Uri _site;

  static const _directoryPath = '/apps/directory.json';
  static const _legacyPath = '/apps.json';
  String _preferredPath = _directoryPath;

  Future<MiniAppDirectory> fetchPage(int page) async {
    if (page < 0) throw ArgumentError.value(page, 'page');
    try {
      return await _fetch(_preferredPath, page);
    } on DioException catch (error) {
      if (error.response?.statusCode != 404 &&
          error.response?.statusCode != 405) {
        rethrow;
      }
    }

    final alternative = _preferredPath == _directoryPath
        ? _legacyPath
        : _directoryPath;
    final directory = await _fetch(alternative, page);
    _preferredPath = alternative;
    return directory;
  }

  Future<MiniAppDirectory> _fetch(String path, int page) async {
    final response = await _dio.get<Object?>(
      _site.resolve(path).toString(),
      queryParameters: {'page': page},
      options: Options(headers: {'Accept': 'application/json'}),
    );
    return MiniAppDirectory.parse(
      response.data,
      site: _site,
      requestedPage: page,
    );
  }
}
