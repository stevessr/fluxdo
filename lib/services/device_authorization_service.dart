import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'auth_session.dart';
import 'user_api_key_service.dart';

/// Discourse User API Key device authorization (NOT OAuth device code).
///
/// A device grant never contains an OTP. Discourse explicitly rejects the
/// one_time_password scope for this endpoint. We request a short-lived write
/// key, use it exactly once to request an OTP, then revoke it. Sites which do
/// not allow write cannot provide cookie-based FluxDO login via this flow.
class DeviceAuthorizationService {
  DeviceAuthorizationService(this.dio, {Future<String> Function()? publicKeyProvider})
    : _publicKeyProvider = publicKeyProvider;

  final Dio dio;
  final Future<String> Function()? _publicKeyProvider;
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
    final publicKey = await (_publicKeyProvider?.call() ?? _keys.ensurePublicKeyPem());
    if (!AuthSession().isValid(generation)) {
      throw StateError('登录会话已变化，请重新开始');
    }

    // Each request uses a distinct client_id. Authorization cannot revoke
    // the client key used by the existing system-browser login.
    final response = await dio.post<dynamic>(
      _deviceEndpoint,
      data: {
        'application_name': 'FluxDO Device Login',
        'client_id': const Uuid().v4(),
        'scopes': 'write',
        'nonce': nonce,
        'public_key': publicKey,
        'padding': 'pkcs1',
        // Do not leave a long-lived write key if the app exits after approval.
        'expires_in_seconds': '600',
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
        !RegExp(r'^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}
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
    );
  }

  Future<DeviceAuthorizationPoll> poll(DeviceAuthorizationRequest request) async {
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

  /// Returns an OTP ready for LoginTokenRedeemer, without persisting the
  /// temporary write key or overwriting a different account's API key.
  Future<String> exchangeForOtp(
    DeviceAuthorizationRequest request,
    String encryptedPayload,
  ) async {
    if (!AuthSession().isValid(request.generation)) {
      throw StateError('登录会话已变化');
    }
    final decrypted = await _keys.decryptDeviceAuthorizationPayload(
      encryptedPayload,
      expectedNonce: request.nonce,
    );
    if (!AuthSession().isValid(request.generation)) {
      throw StateError('登录会话已变化');
    }
    final apiKey = decrypted?['key']?.toString() ?? '';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(apiKey)) {
      throw const FormatException('设备授权内容无效或 nonce 不匹配');
    }
    try {
      final otp = await _keys.requestOtp(
        dio,
        requestGeneration: request.generation,
        overrideApiKey: apiKey,
      );
      if (otp == null || otp.isEmpty) {
        throw StateError('站点未允许此设备 API Key 签发登录 OTP');
      }
      return otp;
    } finally {
      // The short expiry also bounds exposure if revocation fails.
      await _keys.revokeKey(dio, apiKey);
    }
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
  });

  final String deviceCode;
  final String userCode;
  final Uri verificationUri;
  final Uri verificationUriWithRequest;
  final String nonce;
  final DateTime expiresAt;
  final Duration pollInterval;
  final int generation;
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
).hasMatch(userCode) ||
        !safe(verification) ||
        !safe(verificationWithRequest) ||
        !RegExp(r'^[-_A-Za-z0-9]{8}
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
      pollInterval: Duration(seconds: interval.clamp(5, 60)),
      generation: generation,
    );
  }

  Future<DeviceAuthorizationPoll> poll(DeviceAuthorizationRequest request) async {
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

  /// Returns an OTP ready for LoginTokenRedeemer, without persisting the
  /// temporary write key or overwriting a different account's API key.
  Future<String> exchangeForOtp(
    DeviceAuthorizationRequest request,
    String encryptedPayload,
  ) async {
    if (!AuthSession().isValid(request.generation)) {
      throw StateError('登录会话已变化');
    }
    final decrypted = await _keys.decryptDeviceAuthorizationPayload(
      encryptedPayload,
      expectedNonce: request.nonce,
    );
    if (!AuthSession().isValid(request.generation)) {
      throw StateError('登录会话已变化');
    }
    final apiKey = decrypted?['key']?.toString() ?? '';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(apiKey)) {
      throw const FormatException('设备授权内容无效或 nonce 不匹配');
    }
    try {
      final otp = await _keys.requestOtp(
        dio,
        requestGeneration: request.generation,
        overrideApiKey: apiKey,
      );
      if (otp == null || otp.isEmpty) {
        throw StateError('站点未允许此设备 API Key 签发登录 OTP');
      }
      return otp;
    } finally {
      // The short expiry also bounds exposure if revocation fails.
      await _keys.revokeKey(dio, apiKey);
    }
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
  });

  final String deviceCode;
  final String userCode;
  final Uri verificationUri;
  final Uri verificationUriWithRequest;
  final String nonce;
  final DateTime expiresAt;
  final Duration pollInterval;
  final int generation;
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
).hasMatch(
          verificationWithRequest?.queryParameters['request'] ?? '',
        )) {
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
      pollInterval: Duration(seconds: interval.clamp(5, 60)),
      generation: generation,
    );
  }

  Future<DeviceAuthorizationPoll> poll(DeviceAuthorizationRequest request) async {
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

  /// Returns an OTP ready for LoginTokenRedeemer, without persisting the
  /// temporary write key or overwriting a different account's API key.
  Future<String> exchangeForOtp(
    DeviceAuthorizationRequest request,
    String encryptedPayload,
  ) async {
    if (!AuthSession().isValid(request.generation)) {
      throw StateError('登录会话已变化');
    }
    final decrypted = await _keys.decryptDeviceAuthorizationPayload(
      encryptedPayload,
      expectedNonce: request.nonce,
    );
    if (!AuthSession().isValid(request.generation)) {
      throw StateError('登录会话已变化');
    }
    final apiKey = decrypted?['key']?.toString() ?? '';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(apiKey)) {
      throw const FormatException('设备授权内容无效或 nonce 不匹配');
    }
    try {
      final otp = await _keys.requestOtp(
        dio,
        requestGeneration: request.generation,
        overrideApiKey: apiKey,
      );
      if (otp == null || otp.isEmpty) {
        throw StateError('站点未允许此设备 API Key 签发登录 OTP');
      }
      return otp;
    } finally {
      // The short expiry also bounds exposure if revocation fails.
      await _keys.revokeKey(dio, apiKey);
    }
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
  });

  final String deviceCode;
  final String userCode;
  final Uri verificationUri;
  final Uri verificationUriWithRequest;
  final String nonce;
  final DateTime expiresAt;
  final Duration pollInterval;
  final int generation;
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
