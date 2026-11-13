import 'package:dio/dio.dart';

import '../models/mini_app_runtime.dart';

/// Looks up the official production embed URL before mounting an app.
///
/// /launch returns short-lived runtime credentials and an encrypted package.
/// The website loader must request and consume those inside its own sandbox;
/// no launch token or package password enters native app state.
class MiniAppRuntimeRepository {
  MiniAppRuntimeRepository({required Dio dio, required Uri site})
      : _dio = dio,
        _site = site;

  final Dio _dio;
  final Uri _site;
  static final _validId = RegExp(r'^[a-zA-Z0-9_-]{1,128}$');

  Future<MiniAppRuntime> resolve(String appId) async {
    if (!_validId.hasMatch(appId)) {
      throw ArgumentError.value(appId, 'appId', 'Invalid mini app ID');
    }
    final url = _site.resolve(
      '/mini-app-api/production/${Uri.encodeComponent(appId)}/info',
    );
    final response = await _dio.get<Object?>(
      url.toString(),
      options: Options(headers: {'Accept': 'application/json'}),
    );
    return MiniAppRuntime.parse(response.data, site: _site, appId: appId);
  }
}
