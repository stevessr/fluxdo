import 'package:dio/dio.dart';

import '../models/mini_app.dart';

/// Official Linux.do mini app directory. Sorting, searching and paging are
/// performed by the server; preserve its order rather than re-sorting locally.
class MiniAppDirectoryRepository {
  MiniAppDirectoryRepository({required Dio dio, required Uri site})
      : _dio = dio,
        _site = site;

  final Dio _dio;
  final Uri _site;

  static const directoryPath = '/mini-app-api/apps.json';
  static const sorts = ['hot', 'latest', 'rating', 'used'];

  Future<MiniAppDirectory> fetchPage(
    int page, {
    String sort = 'hot',
    String query = '',
  }) async {
    if (page < 0) throw ArgumentError.value(page, 'page');
    if (!sorts.contains(sort)) throw ArgumentError.value(sort, 'sort');
    final response = await _dio.get<Object?>(
      _site.resolve(directoryPath).toString(),
      queryParameters: {'sort': sort, 'q': query, 'page': page},
      options: Options(headers: {'Accept': 'application/json'}),
    );
    return MiniAppDirectory.parse(
      response.data,
      site: _site,
      requestedPage: page,
    );
  }
}
