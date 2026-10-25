import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'auth_session.dart';
import 'user_api_key_service.dart';

/// Discourse User API Key device authorization (NOT OAuth device code).
///
/// A grant yields an encrypted User API Key, not a Cookie or OTP.
/// For Cookie login request a short-lived write Key, mint an OTP through
/// Discourse's existing API and redeem it using UserApiKeyLoginFlow.
/// If the site forbids write, direct the user to browser authorization.
class DeviceAuthorizationService {
  DeviceAuthorizationService(
    this.dio, {
    this.publicKeyProvider,
    this.clientIdProvider,
    this.payloadDecryptor,
    this.credentialSaver,
    this.otpRequester,
    this.keyRevoker,
  });

  final Dio dio;
  final Future<String> Function()? publicKeyProvider;
  final Future<String> Function()? clientIdProvider;
  final Future<Map<String, dynamic>?> Function(String, String)?
  payloadDecryptor;
  final Future<void> Function(String, String, String, DateTime?)?
  credentialSaver;
  final Future<String?> Function(
    String apiKey,
    String clientId,
    int generation,
  )?
  otpRequester;
  final Future<bool> Function(String apiKey)? keyRevoker;
  final UserApiKeyService _keys = UserApiKeyService();

  static const String _deviceEndpoint = '/user-api-key/device.json';
  static const String _pollEndpoint = '/user-api-key/device/poll.json';

  static const _options = <String, dynamic>{
    'skipAuthCheck': true,
    'skipCsrf': true,
    'skipSessionStateSync': true,
    'noRecovery': true,
  };

  Future<DeviceAuthorizationRequest> create({
    DeviceAuthorizationMode mode = DeviceAuthorizationMode.cookieLogin,
  }) async {
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
    // Subsequent approvals replace the previous key for the same client.
    final response = await dio.post<dynamic>(
      _deviceEndpoint,
      data: {
        'application_name': 'FluxDO Device Login',
        'client_id': clientId,
        'scopes': mode == DeviceAuthorizationMode.cookieLogin
            ? 'write'
            : 'read',
        'nonce': nonce,
        'public_key': publicKey,
        'padding': 'pkcs1',
        // A write Key is only a short-lived OTP exchange credential.
        'expires_in_seconds': mode == DeviceAuthorizationMode.cookieLogin
            ? '600'
            : '86400',
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
      mode: mode,
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

  /// Verify the approved key against an isolated identity request, then
  /// exchange a write Key for an OTP. Read-only grants are stored separately.
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
    if (request.mode == DeviceAuthorizationMode.cookieLogin) {
      try {
        final otp =
            await (otpRequester?.call(
                  apiKey,
                  request.clientId,
                  request.generation,
                ) ??
                _keys.requestOtp(
                  dio,
                  requestGeneration: request.generation,
                  overrideApiKey: apiKey,
                  overrideClientId: request.clientId,
                ));
        if (!isCurrent()) throw StateError('登录会话已变化');
        if (otp == null || !RegExp(r'^[0-9a-f]+$').hasMatch(otp)) {
          throw const DeviceOtpUnavailableException();
        }
        return DeviceAuthorizedIdentity(username: username, otp: otp);
      } finally {
        // A temporary write Key is never retained beyond the OTP request.
        // OTP redemption is independent of the API Key after issuance.
        await (keyRevoker?.call(apiKey) ?? _keys.revokeKey(dio, apiKey));
      }
    }

    // Explicit API-only authorization, never confused with Cookie login.
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
    required this.mode,
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
  final DeviceAuthorizationMode mode;
}

enum DeviceAuthorizationMode { cookieLogin, readOnly }

class DeviceOtpUnavailableException implements Exception {
  const DeviceOtpUnavailableException();
  @override
  String toString() => '站点未允许临时设备 API Key 签发 OTP，无法直接创建 Cookie 会话';
}

class DeviceAuthorizedIdentity {
  const DeviceAuthorizedIdentity({required this.username, this.otp});
  final String username;

  /// Non-null only if the server granted write and successfully issued OTP.
  final String? otp;
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
