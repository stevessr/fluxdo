import 'package:dio/dio.dart';

class MatrixIdentityProvider {
  const MatrixIdentityProvider({
    required this.id,
    required this.name,
    this.icon,
    this.brand,
  });

  final String id;
  final String name;
  final String? icon;
  final String? brand;
}

class MatrixLoginCapabilities {
  const MatrixLoginCapabilities({
    required this.supportsPassword,
    required this.supportsToken,
    required this.supportsSso,
    this.identityProviders = const <MatrixIdentityProvider>[],
  });

  final bool supportsPassword;
  final bool supportsToken;
  final bool supportsSso;
  final List<MatrixIdentityProvider> identityProviders;
}

class MatrixSsoTokenExchange {
  const MatrixSsoTokenExchange({
    required this.accessToken,
    this.userId,
    this.deviceId,
  });

  final String accessToken;
  final String? userId;
  final String? deviceId;
}

class MatrixSsoException implements Exception {
  const MatrixSsoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Small SSO-specific companion to the lightweight Matrix REST client.
///
/// It deliberately owns only login-flow discovery, SSO redirect construction,
/// and one-time `m.login.token` exchange. Session verification/persistence stays
/// in the main client so SSO and access-token import converge on one storage
/// path.
class MatrixSsoService {
  MatrixSsoService({Dio? dio})
    : _dio = dio ?? Dio(),
      _ownsDio = dio == null;

  final Dio _dio;
  final bool _ownsDio;

  Future<MatrixLoginCapabilities> loadLoginCapabilities(
    String homeserver,
  ) async {
    final baseUrl = _normalizeBaseUrl(homeserver);
    try {
      final response = await _dio.get<dynamic>(
        '$baseUrl/_matrix/client/v3/login',
      );
      final root = _asMap(response.data);
      final flows = _asList(root['flows']);

      var password = false;
      var token = false;
      var sso = false;
      final providers = <MatrixIdentityProvider>[];
      final seenProviders = <String>{};

      for (final rawFlow in flows) {
        final flow = _asMap(rawFlow);
        switch (flow['type']) {
          case 'm.login.password':
            password = true;
          case 'm.login.token':
            token = true;
          case 'm.login.sso':
            sso = true;
            for (final rawProvider in _asList(flow['identity_providers'])) {
              final provider = _asMap(rawProvider);
              final id = provider['id'];
              final name = provider['name'];
              if (id is! String || id.isEmpty || seenProviders.contains(id)) {
                continue;
              }
              seenProviders.add(id);
              providers.add(
                MatrixIdentityProvider(
                  id: id,
                  name: name is String && name.isNotEmpty ? name : id,
                  icon: provider['icon'] as String?,
                  brand: provider['brand'] as String?,
                ),
              );
            }
        }
      }

      return MatrixLoginCapabilities(
        supportsPassword: password,
        supportsToken: token,
        supportsSso: sso,
        identityProviders: List<MatrixIdentityProvider>.unmodifiable(providers),
      );
    } on DioException catch (error) {
      throw MatrixSsoException(_matrixErrorMessage(error));
    }
  }

  Uri buildRedirectUri({
    required String homeserver,
    required Uri callbackUri,
    String? identityProviderId,
  }) {
    final baseUrl = _normalizeBaseUrl(homeserver);
    final base = Uri.parse(baseUrl);
    final suffix = identityProviderId == null || identityProviderId.isEmpty
        ? '/_matrix/client/v3/login/sso/redirect'
        : '/_matrix/client/v3/login/sso/redirect/'
              '${Uri.encodeComponent(identityProviderId)}';
    return base.replace(
      path: '${base.path}$suffix'.replaceAll('//', '/'),
      queryParameters: <String, String>{
        'redirectUrl': callbackUri.toString(),
      },
    );
  }

  Future<MatrixSsoTokenExchange> exchangeLoginToken({
    required String homeserver,
    required String loginToken,
  }) async {
    final token = loginToken.trim();
    if (token.isEmpty) {
      throw const MatrixSsoException('Matrix SSO 回调缺少 loginToken。');
    }

    final baseUrl = _normalizeBaseUrl(homeserver);
    try {
      final response = await _dio.post<dynamic>(
        '$baseUrl/_matrix/client/v3/login',
        data: <String, dynamic>{
          'type': 'm.login.token',
          'token': token,
          'initial_device_display_name': 'Fluxdo Experimental Matrix',
        },
      );
      final root = _asMap(response.data);
      final accessToken = root['access_token'];
      if (accessToken is! String || accessToken.isEmpty) {
        throw const MatrixSsoException(
          'Matrix SSO token exchange 未返回 access_token。',
        );
      }
      return MatrixSsoTokenExchange(
        accessToken: accessToken,
        userId: root['user_id'] as String?,
        deviceId: root['device_id'] as String?,
      );
    } on DioException catch (error) {
      throw MatrixSsoException(_matrixErrorMessage(error));
    }
  }

  void dispose() {
    if (_ownsDio) {
      _dio.close(force: true);
    }
  }

  static String _normalizeBaseUrl(String value) {
    var normalized = value.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      throw MatrixSsoException('无效的 homeserver URL：$value');
    }
    return normalized;
  }

  static String _matrixErrorMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final message = data['error'];
      final errcode = data['errcode'];
      if (message is String && message.isNotEmpty) {
        return errcode is String ? '$errcode: $message' : message;
      }
    }
    return error.message ?? 'Matrix SSO request failed.';
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static List<dynamic> _asList(dynamic value) =>
      value is List ? value : const <dynamic>[];
}
