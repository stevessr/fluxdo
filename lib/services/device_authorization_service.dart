import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'auth_session.dart';
import 'user_api_key_service.dart';

/// Discourse User API Key device authorization (NOT OAuth device code).
///
/// A device grant yields an encrypted User API Key, not a Cookie or OTP.
/// Native read-only API authorization must never be reported as a _t login.
class DeviceAuthorizationService {
  DeviceAuthorizationService(
    this.dio, {
    this.publicKeyProvider,
    this.clientIdProvider,
    this.payloadDecryptor,
    this.credentialSaver,
  });

  final Dio dio;
  final Future<String> Function()? publicKeyProvider;
  final Future<String> Function()? clientIdProvider;
  final Future<Map<String, dynamic>?> Function(String, String)?
  payloadDecryptor;
  final Future<void> Function(String, String, String, DateTime?)?
  credentialSaver;
  final UserApiKeyService _keys = UserApiKeyService();

  static const String _deviceEndpoint = '/user-api-key/device.json';
  static const String _pollEndpoint = '/user-api-key/device/poll.json';

  static const _options = <String, dynamic>{
    'skipAuthCheck': true,
    'skipCsrf': true,
    'skipSessionStateSync': true,
    'noRecovery': true,
  };

  Future<DeviceAuthorizationRequest> create() async {
    final generation = AuthSession().generation;
    final nonce = const Uuid().v4();
    final publicKey =
        await (publicKeyProvider?.call() ?? _keys.ensurePublicKeyPem());
    final clientId =
        await (clientIdProvider?.call() ?? _keys.ensureDeviceClientId());
    if (!AuthSession().isValid(generation)) {
      throw StateError('登录会话已变化，请重新开始');
    }

    // Stable device client ID is separate from browser and QR authorizations.
    // Subsequent approvals replace the previous short-lived device key.
    final response = await dio.post<dynamic>(
      _deviceEndpoint,
      data: {
        'application_name': 'FluxDO Device API',
        'client_id': clientId,
        'scopes': 'read',
        'nonce': nonce,
        'public_key': publicKey,
        'padding': 'pkcs1',
        // Request a renewable, bounded native API credential rather than OTP.
        'expires_in_seconds': '86400',
      },
      options: Options(
        contentType: Headers.jsonContentType,
        headers: const {'Accept': 'application/json'},
        extra: _options,
      ),
    );
    if (!AuthSession().isValid(generation)) {
      throw StateError('登录会话已变化，请重新开始');
    }
    final body = responseMap(response.data);
    final deviceCode = body['device_code']?.toString() ?? '';
    final userCode = body['user_code']?.toString() ?? '';
    final verification = Uri.tryParse(
      body['verification_uri']?.toString() ?? '',
    );
    final verificationWithRequest = Uri.tryParse(
      body['verification_uri_with_request']?.toString() ?? '',
    );

    // Only ever send users to the trusted Discourse site.
    bool safe(Uri? uri) =>
        uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'linux.do' &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        uri.fragment.isEmpty &&
        uri.path == '/user-api-key/activate';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(deviceCode) ||
        !RegExp(r'^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$').hasMatch(userCode) ||
        !safe(verification) ||
        !safe(verificationWithRequest) ||
        !RegExp(
          r'^[-_A-Za-z0-9]{8}$',
        ).hasMatch(verificationWithRequest?.queryParameters['request'] ?? '')) {
      throw const FormatException('服务端设备授权响应格式无效');
    }
    final expiresIn = int.tryParse(body['expires_in']?.toString() ?? '') ?? 0;
    final interval = int.tryParse(body['interval']?.toString() ?? '') ?? 0;
    if (expiresIn <= 0 || interval <= 0) {
      throw const FormatException('服务端未返回有效的授权时限');
    }
    return DeviceAuthorizationRequest(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: verification!,
      verificationUriWithRequest: verificationWithRequest!,
      nonce: nonce,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      pollInterval: Duration(seconds: interval < 5 ? 5 : interval),
      generation: generation,
      clientId: clientId,
    );
  }

  Future<DeviceAuthorizationPoll> poll(
    DeviceAuthorizationRequest request,
  ) async {
    if (!AuthSession().isValid(request.generation)) {
      throw StateError('登录会话已变化');
    }
    final response = await dio.post<dynamic>(
      _pollEndpoint,
      data: {'device_code': request.deviceCode},
      options: Options(
        contentType: Headers.jsonContentType,
        headers: const {'Accept': 'application/json'},
        extra: _options,
      ),
    );
    if (!AuthSession().isValid(request.generation)) {
      throw StateError('登录会话已变化');
    }
    return DeviceAuthorizationPoll.parse(responseMap(response.data));
  }

  /// Complete native DeviceAuth by decrypting and verifying a User API Key.
  /// No OTP exchange or _t session is attempted here.
  Future<DeviceAuthorizedIdentity> authorize(
    DeviceAuthorizationRequest request,
    String encryptedPayload,
  ) async {
    bool isCurrent() => AuthSession().isValid(request.generation);
    if (!isCurrent()) throw StateError('登录会话已变化');
    final decrypted =
        await (payloadDecryptor?.call(encryptedPayload, request.nonce) ??
            _keys.decryptDeviceAuthorizationPayload(
              encryptedPayload,
              expectedNonce: request.nonce,
            ));
    if (!isCurrent()) throw StateError('登录会话已变化');
    final apiKey = decrypted?['key']?.toString() ?? '';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(apiKey)) {
      throw const FormatException('设备授权内容无效或 nonce 不匹配');
    }
    // Do not let an already logged-in browser Cookie authenticate this call:
    // this request must prove that the freshly issued User API Key works.
    final response = await dio.get<dynamic>(
      '/session/current.json',
      options: Options(
        headers: {
          'User-Api-Key': apiKey,
          'User-Api-Client-Id': request.clientId,
          'Cookie': '',
        },
        extra: {..._options, 'skipCookieManager': true},
      ),
    );
    if (!isCurrent()) throw StateError('登录会话已变化');
    final user = responseMap(response.data)['current_user'];
    if (user is! Map ||
        user['username'] is! String ||
        (user['username'] as String).isEmpty) {
      throw const FormatException('站点没有确认设备 API Key 的用户身份');
    }
    final username = user['username'] as String;
    // Device credentials are stored in an isolated slot, not the browser
    // OTP/self-heal key slot. This does not publish a Cookie-based login.
    final expires = DateTime.tryParse(
      decrypted?['expires_at']?.toString() ?? '',
    );
    if (credentialSaver != null) {
      await credentialSaver!(apiKey, request.clientId, username, expires);
    } else {
      await _keys.persistDeviceAuthorization(
        apiKey: apiKey,
        clientId: request.clientId,
        username: username,
        expiresAt: expires,
      );
    }
    if (!isCurrent()) {
      if (credentialSaver == null) {
        await _keys.clearDeviceAuthorization(expectedKey: apiKey);
      }
      throw StateError('登录会话已变化');
    }
    return DeviceAuthorizedIdentity(username: username);
  }

  static Map<String, dynamic> responseMap(dynamic body) {
    if (body is Map) return Map<String, dynamic>.from(body);
    if (body is String) {
      final json = jsonDecode(body);
      if (json is Map) return Map<String, dynamic>.from(json);
    }
    throw const FormatException('设备授权接口没有返回 JSON');
  }
}

class DeviceAuthorizationRequest {
  const DeviceAuthorizationRequest({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriWithRequest,
    required this.nonce,
    required this.expiresAt,
    required this.pollInterval,
    required this.generation,
    required this.clientId,
  });

  final String deviceCode;
  final String userCode;
  final Uri verificationUri;
  final Uri verificationUriWithRequest;
  final String nonce;
  final DateTime expiresAt;
  final Duration pollInterval;
  final int generation;
  final String clientId;
}

class DeviceAuthorizedIdentity {
  const DeviceAuthorizedIdentity({required this.username});
  final String username;
}

enum DeviceAuthorizationStatus { pending, authorized, denied, expired }

class DeviceAuthorizationPoll {
  const DeviceAuthorizationPoll(this.status, {this.encryptedPayload});

  final DeviceAuthorizationStatus status;
  final String? encryptedPayload;

  static DeviceAuthorizationPoll parse(Map<String, dynamic> body) {
    switch (body['status']) {
      case 'authorization_pending':
        return const DeviceAuthorizationPoll(DeviceAuthorizationStatus.pending);
      case 'authorized':
        final payload = body['payload']?.toString() ?? '';
        if (payload.isEmpty) {
          throw const FormatException('设备授权成功但未返回加密 Key');
        }
        return DeviceAuthorizationPoll(
          DeviceAuthorizationStatus.authorized,
          encryptedPayload: payload,
        );
      case 'access_denied':
        return const DeviceAuthorizationPoll(DeviceAuthorizationStatus.denied);
      case 'expired_token':
        return const DeviceAuthorizationPoll(DeviceAuthorizationStatus.expired);
      default:
        throw const FormatException('设备授权返回了未知状态');
    }
  }
}
