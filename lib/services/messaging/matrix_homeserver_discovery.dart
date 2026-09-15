import 'package:dio/dio.dart';

typedef MatrixDiscoveryGet = Future<MatrixDiscoveryResponse> Function(Uri uri);

enum MatrixHomeserverDiscoverySource {
  explicitUrl,
  wellKnown,
  directServerName,
}

class MatrixHomeserverDiscoveryResult {
  const MatrixHomeserverDiscoveryResult({
    required this.baseUrl,
    required this.source,
    required this.versions,
    this.serverName,
    this.identityServerBaseUrl,
  });

  final String baseUrl;
  final MatrixHomeserverDiscoverySource source;
  final List<String> versions;
  final String? serverName;
  final String? identityServerBaseUrl;
}

class MatrixDiscoveryResponse {
  const MatrixDiscoveryResponse({required this.statusCode, this.data});

  final int statusCode;
  final dynamic data;
}

class MatrixHomeserverDiscoveryException implements Exception {
  const MatrixHomeserverDiscoveryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Matrix Client-Server homeserver discovery used only during login.
///
/// The implementation follows the Matrix discovery flow:
/// 1. derive a server name from a Matrix ID/domain;
/// 2. fetch `https://hostname/.well-known/matrix/client`;
/// 3. validate a discovered `m.homeserver.base_url` with `/versions`.
///
/// A 404 means the well-known mechanism is absent. In that case Fluxdo tries a
/// direct HTTPS URL derived from the server name, but still validates it before
/// accepting it. Other malformed/non-success well-known responses are surfaced
/// instead of silently redirecting credentials to a guessed endpoint.
class MatrixHomeserverDiscoveryService {
  MatrixHomeserverDiscoveryService({Dio? dio})
    : this._withDio(dio ?? Dio(), ownsDio: dio == null);

  MatrixHomeserverDiscoveryService._withDio(
    Dio dio, {
    required bool ownsDio,
  }) : _get = _dioTransport(dio),
       _ownedDio = ownsDio ? dio : null;

  MatrixHomeserverDiscoveryService.withTransport(MatrixDiscoveryGet transport)
    : _get = transport,
      _ownedDio = null;

  final MatrixDiscoveryGet _get;
  final Dio? _ownedDio;

  Future<MatrixHomeserverDiscoveryResult> discover(String input) async {
    final normalized = input.trim();
    if (normalized.isEmpty) {
      throw const MatrixHomeserverDiscoveryException(
        'Matrix ID、服务器域名或 homeserver URL 不能为空。',
      );
    }

    final explicitUri = Uri.tryParse(normalized);
    if (explicitUri != null && explicitUri.hasScheme) {
      final baseUrl = normalizeBaseUrl(normalized);
      final versions = await _validateHomeserver(baseUrl);
      return MatrixHomeserverDiscoveryResult(
        baseUrl: baseUrl,
        source: MatrixHomeserverDiscoverySource.explicitUrl,
        versions: versions,
      );
    }

    final serverName = serverNameFromInput(normalized);
    if (serverName == null || serverName.isEmpty) {
      throw MatrixHomeserverDiscoveryException(
        '无法从“$normalized”解析 Matrix server name。',
      );
    }

    final parts = _parseServerName(serverName);
    final wellKnownUri = Uri(
      scheme: 'https',
      host: parts.host,
      path: '/.well-known/matrix/client',
    );
    final wellKnown = await _safeGet(wellKnownUri);

    if (wellKnown.statusCode == 200) {
      final root = _asMap(wellKnown.data);
      final homeserver = _asMap(root['m.homeserver']);
      final rawBaseUrl = homeserver['base_url'];
      if (rawBaseUrl is! String || rawBaseUrl.trim().isEmpty) {
        throw const MatrixHomeserverDiscoveryException(
          'Matrix .well-known 响应缺少 m.homeserver.base_url。',
        );
      }

      final baseUrl = normalizeBaseUrl(rawBaseUrl);
      final versions = await _validateHomeserver(baseUrl);
      final identityServer = _asMap(root['m.identity_server']);
      final rawIdentityUrl = identityServer['base_url'];
      String? identityServerBaseUrl;
      if (rawIdentityUrl is String && rawIdentityUrl.trim().isNotEmpty) {
        try {
          identityServerBaseUrl = normalizeBaseUrl(rawIdentityUrl);
        } catch (_) {
          // Identity server metadata is optional for Fluxdo's current login
          // path, so an invalid optional value must not poison homeserver login.
        }
      }

      return MatrixHomeserverDiscoveryResult(
        baseUrl: baseUrl,
        source: MatrixHomeserverDiscoverySource.wellKnown,
        versions: versions,
        serverName: serverName,
        identityServerBaseUrl: identityServerBaseUrl,
      );
    }

    if (wellKnown.statusCode != 404) {
      throw MatrixHomeserverDiscoveryException(
        'Matrix .well-known discovery 返回 HTTP ${wellKnown.statusCode}。',
      );
    }

    final directBaseUrl = _directBaseUrl(parts);
    final versions = await _validateHomeserver(directBaseUrl);
    return MatrixHomeserverDiscoveryResult(
      baseUrl: directBaseUrl,
      source: MatrixHomeserverDiscoverySource.directServerName,
      versions: versions,
      serverName: serverName,
    );
  }

  void dispose() {
    _ownedDio?.close(force: true);
  }

  static String? serverNameFromInput(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;

    if (value.startsWith('@')) {
      final separator = value.indexOf(':');
      if (separator <= 1 || separator == value.length - 1) return null;
      return value.substring(separator + 1);
    }

    if (value.contains('/') || value.contains('://')) return null;
    return value;
  }

  static String normalizeBaseUrl(String input) {
    var value = input.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }

    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.hasFragment ||
        uri.hasQuery) {
      throw MatrixHomeserverDiscoveryException(
        '无效的 Matrix homeserver URL：$input',
      );
    }
    return value;
  }

  Future<List<String>> _validateHomeserver(String baseUrl) async {
    final uri = Uri.parse('$baseUrl/_matrix/client/versions');
    final response = await _safeGet(uri);
    if (response.statusCode != 200) {
      throw MatrixHomeserverDiscoveryException(
        'Homeserver 验证失败：${uri.origin} 返回 HTTP ${response.statusCode}。',
      );
    }

    final root = _asMap(response.data);
    final versions = _asList(root['versions']).whereType<String>().toList();
    if (versions.isEmpty) {
      throw const MatrixHomeserverDiscoveryException(
        'Homeserver /_matrix/client/versions 响应无有效 versions。',
      );
    }
    return List<String>.unmodifiable(versions);
  }

  Future<MatrixDiscoveryResponse> _safeGet(Uri uri) async {
    try {
      return await _get(uri);
    } on MatrixHomeserverDiscoveryException {
      rethrow;
    } catch (error) {
      throw MatrixHomeserverDiscoveryException(
        'Matrix discovery 请求失败（$uri）：$error',
      );
    }
  }

  static MatrixDiscoveryGet _dioTransport(Dio dio) {
    return (uri) async {
      try {
        final response = await dio.get<dynamic>(
          uri.toString(),
          options: Options(
            followRedirects: true,
            maxRedirects: 5,
            validateStatus: (_) => true,
            receiveTimeout: const Duration(seconds: 12),
            sendTimeout: const Duration(seconds: 12),
          ),
        );
        return MatrixDiscoveryResponse(
          statusCode: response.statusCode ?? 0,
          data: response.data,
        );
      } on DioException catch (error) {
        throw MatrixHomeserverDiscoveryException(
          error.message ?? 'Matrix discovery network error.',
        );
      }
    };
  }

  static _ServerNameParts _parseServerName(String serverName) {
    final value = serverName.trim();
    if (value.isEmpty) {
      throw const MatrixHomeserverDiscoveryException(
        'Matrix server name 不能为空。',
      );
    }

    if (value.startsWith('[')) {
      final bracket = value.indexOf(']');
      if (bracket <= 1) {
        throw MatrixHomeserverDiscoveryException(
          '无效的 Matrix IPv6 server name：$serverName',
        );
      }
      final host = value.substring(1, bracket);
      final suffix = value.substring(bracket + 1);
      int? port;
      if (suffix.isNotEmpty) {
        if (!suffix.startsWith(':')) {
          throw MatrixHomeserverDiscoveryException(
            '无效的 Matrix server name：$serverName',
          );
        }
        port = int.tryParse(suffix.substring(1));
        if (port == null || port < 1 || port > 65535) {
          throw MatrixHomeserverDiscoveryException(
            '无效的 Matrix server port：$serverName',
          );
        }
      }
      return _ServerNameParts(host: host, port: port);
    }

    final colonCount = ':'.allMatches(value).length;
    if (colonCount > 1) {
      throw MatrixHomeserverDiscoveryException(
        'IPv6 Matrix server name 必须使用 [address]:port 形式：$serverName',
      );
    }

    if (colonCount == 1) {
      final separator = value.lastIndexOf(':');
      final host = value.substring(0, separator);
      final port = int.tryParse(value.substring(separator + 1));
      if (host.isEmpty || port == null || port < 1 || port > 65535) {
        throw MatrixHomeserverDiscoveryException(
          '无效的 Matrix server name：$serverName',
        );
      }
      return _ServerNameParts(host: host, port: port);
    }

    return _ServerNameParts(host: value);
  }

  static String _directBaseUrl(_ServerNameParts parts) {
    return Uri(
      scheme: 'https',
      host: parts.host,
      port: parts.port,
    ).toString().replaceAll(RegExp(r'/$'), '');
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static List<dynamic> _asList(dynamic value) =>
      value is List ? value : const <dynamic>[];
}

class _ServerNameParts {
  const _ServerNameParts({required this.host, this.port});

  final String host;
  final int? port;
}
