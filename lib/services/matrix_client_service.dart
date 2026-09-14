import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal Matrix Client-Server API adapter used by the experimental chat hub.
///
/// This intentionally stays dependency-light so Matrix can be tested without
/// raising Fluxdo's Dart SDK constraint to match Extera's current Matrix SDK.
/// It supports unencrypted rooms only; encrypted events are surfaced as
/// placeholders instead of being silently discarded.
class MatrixClientService {
  MatrixClientService({
    Dio? dio,
    FlutterSecureStorage? secureStorage,
  }) : _dio = dio ?? Dio(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _sessionStorageKey = 'experimental_matrix_session_v1';

  final Dio _dio;
  final FlutterSecureStorage _secureStorage;

  MatrixSession? _session;

  MatrixSession? get session => _session;
  bool get isLoggedIn => _session != null;

  Future<MatrixSession?> restoreSession() async {
    if (_session != null) return _session;

    final raw = await _secureStorage.read(key: _sessionStorageKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      _session = MatrixSession.fromJson(decoded);
      return _session;
    } catch (_) {
      await _secureStorage.delete(key: _sessionStorageKey);
      return null;
    }
  }

  Future<MatrixSession> loginWithPassword({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    final baseUrl = _normalizeHomeserver(homeserver);

    try {
      final response = await _dio.post<dynamic>(
        '$baseUrl/_matrix/client/v3/login',
        data: <String, dynamic>{
          'type': 'm.login.password',
          'identifier': <String, dynamic>{
            'type': 'm.id.user',
            'user': username,
          },
          'password': password,
          'initial_device_display_name': 'Fluxdo Experimental Matrix',
        },
      );

      final data = _asMap(response.data);
      final accessToken = data['access_token'] as String?;
      final userId = data['user_id'] as String?;
      if (accessToken == null || userId == null) {
        throw const MatrixClientException('Matrix login returned no session.');
      }

      final session = MatrixSession(
        homeserver: baseUrl,
        accessToken: accessToken,
        userId: userId,
        deviceId: data['device_id'] as String?,
      );
      await _persistSession(session);
      return session;
    } on DioException catch (error) {
      throw MatrixClientException(_matrixErrorMessage(error));
    }
  }

  /// Saves an already-issued access token. This is useful for homeservers that
  /// disable password login and require SSO or external authentication.
  Future<MatrixSession> loginWithAccessToken({
    required String homeserver,
    required String userId,
    required String accessToken,
  }) async {
    final baseUrl = _normalizeHomeserver(homeserver);
    final candidate = MatrixSession(
      homeserver: baseUrl,
      accessToken: accessToken.trim(),
      userId: userId.trim(),
    );

    if (candidate.accessToken.isEmpty || candidate.userId.isEmpty) {
      throw const MatrixClientException('User ID and access token are required.');
    }

    // Verify the token before persisting it.
    try {
      final response = await _dio.get<dynamic>(
        '$baseUrl/_matrix/client/v3/account/whoami',
        options: _authorizedOptions(candidate),
      );
      final data = _asMap(response.data);
      final verifiedUserId = data['user_id'] as String?;
      if (verifiedUserId == null || verifiedUserId.isEmpty) {
        throw const MatrixClientException('Matrix token verification failed.');
      }
      if (verifiedUserId != candidate.userId) {
        throw MatrixClientException(
          'Token belongs to $verifiedUserId, not ${candidate.userId}.',
        );
      }
    } on DioException catch (error) {
      throw MatrixClientException(_matrixErrorMessage(error));
    }

    await _persistSession(candidate);
    return candidate;
  }

  Future<void> logout() async {
    final current = _session;
    if (current != null) {
      try {
        await _dio.post<void>(
          '${current.homeserver}/_matrix/client/v3/logout',
          options: _authorizedOptions(current),
        );
      } catch (_) {
        // Local logout should still succeed if the server is unreachable.
      }
    }

    _session = null;
    await _secureStorage.delete(key: _sessionStorageKey);
  }

  Future<List<MatrixRoomSummary>> loadRooms() async {
    final current = _requireSession();

    // A single /sync request returns room state and the latest event for every
    // joined room, avoiding one request per room.
    final filter = jsonEncode(<String, dynamic>{
      'room': <String, dynamic>{
        'state': <String, dynamic>{
          'types': <String>[
            'm.room.name',
            'm.room.canonical_alias',
          ],
        },
        'timeline': <String, dynamic>{'limit': 1},
        'ephemeral': <String, dynamic>{'types': <String>[]},
      },
      'presence': <String, dynamic>{'types': <String>[]},
    });

    try {
      final response = await _dio.get<dynamic>(
        '${current.homeserver}/_matrix/client/v3/sync',
        queryParameters: <String, dynamic>{
          'timeout': 0,
          'filter': filter,
        },
        options: _authorizedOptions(current),
      );
      final data = _asMap(response.data);
      final rooms = _asMap(data['rooms']);
      final joined = _asMap(rooms['join']);

      final result = <MatrixRoomSummary>[];
      for (final entry in joined.entries) {
        final roomId = entry.key;
        final roomData = _asMap(entry.value);
        final state = _asMap(roomData['state']);
        final stateEvents = _asList(state['events']);
        final timeline = _asMap(roomData['timeline']);
        final timelineEvents = _asList(timeline['events']);
        final unread = _asMap(roomData['unread_notifications']);

        String? name;
        String? alias;
        for (final rawEvent in stateEvents) {
          final event = _asMap(rawEvent);
          final type = event['type'];
          final content = _asMap(event['content']);
          if (type == 'm.room.name') {
            final value = content['name'];
            if (value is String && value.trim().isNotEmpty) name = value.trim();
          } else if (type == 'm.room.canonical_alias') {
            final value = content['alias'];
            if (value is String && value.trim().isNotEmpty) alias = value.trim();
          }
        }

        MatrixMessage? lastMessage;
        if (timelineEvents.isNotEmpty) {
          lastMessage = _parseMessage(
            _asMap(timelineEvents.last),
            allowUnsupported: true,
          );
        }

        result.add(
          MatrixRoomSummary(
            roomId: roomId,
            name: name ?? alias ?? roomId,
            lastMessage: lastMessage,
            unreadCount: _asInt(unread['notification_count']),
          ),
        );
      }

      result.sort((a, b) {
        final aTs = a.lastMessage?.timestamp.millisecondsSinceEpoch ?? 0;
        final bTs = b.lastMessage?.timestamp.millisecondsSinceEpoch ?? 0;
        return bTs.compareTo(aTs);
      });
      return result;
    } on DioException catch (error) {
      throw MatrixClientException(_matrixErrorMessage(error));
    }
  }

  Future<List<MatrixMessage>> loadMessages(
    String roomId, {
    int limit = 50,
  }) async {
    final current = _requireSession();
    final encodedRoomId = Uri.encodeComponent(roomId);

    try {
      final response = await _dio.get<dynamic>(
        '${current.homeserver}/_matrix/client/v3/rooms/$encodedRoomId/messages',
        queryParameters: <String, dynamic>{
          'dir': 'b',
          'limit': limit.clamp(1, 100),
        },
        options: _authorizedOptions(current),
      );
      final data = _asMap(response.data);
      final chunk = _asList(data['chunk']);
      final messages = <MatrixMessage>[];

      for (final rawEvent in chunk) {
        final parsed = _parseMessage(
          _asMap(rawEvent),
          allowUnsupported: false,
        );
        if (parsed != null) messages.add(parsed);
      }

      // /messages with dir=b returns newest first; the UI renders oldest first.
      return messages.reversed.toList(growable: false);
    } on DioException catch (error) {
      throw MatrixClientException(_matrixErrorMessage(error));
    }
  }

  Future<void> sendText(String roomId, String body) async {
    final current = _requireSession();
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;

    final encodedRoomId = Uri.encodeComponent(roomId);
    final transactionId =
        'fluxdo-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

    try {
      await _dio.put<void>(
        '${current.homeserver}/_matrix/client/v3/rooms/'
        '$encodedRoomId/send/m.room.message/$transactionId',
        data: <String, dynamic>{
          'msgtype': 'm.text',
          'body': trimmed,
        },
        options: _authorizedOptions(current),
      );
    } on DioException catch (error) {
      throw MatrixClientException(_matrixErrorMessage(error));
    }
  }

  Future<void> _persistSession(MatrixSession session) async {
    _session = session;
    await _secureStorage.write(
      key: _sessionStorageKey,
      value: jsonEncode(session.toJson()),
    );
  }

  MatrixSession _requireSession() {
    final current = _session;
    if (current == null) {
      throw const MatrixClientException('Matrix is not signed in.');
    }
    return current;
  }

  Options _authorizedOptions(MatrixSession session) {
    return Options(
      headers: <String, dynamic>{
        'Authorization': 'Bearer ${session.accessToken}',
      },
    );
  }

  MatrixMessage? _parseMessage(
    Map<String, dynamic> event, {
    required bool allowUnsupported,
  }) {
    final type = event['type'];
    final sender = event['sender'] as String? ?? 'unknown';
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      _asInt(event['origin_server_ts']),
    );
    final eventId = event['event_id'] as String? ??
        '${sender}_${timestamp.microsecondsSinceEpoch}';

    if (type == 'm.room.encrypted') {
      return MatrixMessage(
        eventId: eventId,
        sender: sender,
        body: 'Encrypted message (E2EE is not enabled in this experiment yet)',
        timestamp: timestamp,
        encrypted: true,
      );
    }

    if (type != 'm.room.message') {
      return allowUnsupported
          ? MatrixMessage(
              eventId: eventId,
              sender: sender,
              body: 'Room activity',
              timestamp: timestamp,
            )
          : null;
    }

    final content = _asMap(event['content']);
    final msgType = content['msgtype'] as String?;
    final body = content['body'] as String?;
    if (body == null || body.isEmpty) return null;

    if (msgType != 'm.text' && msgType != 'm.notice' && msgType != 'm.emote') {
      return MatrixMessage(
        eventId: eventId,
        sender: sender,
        body: allowUnsupported ? '[$msgType] $body' : body,
        timestamp: timestamp,
      );
    }

    return MatrixMessage(
      eventId: eventId,
      sender: sender,
      body: msgType == 'm.emote' ? '* $body' : body,
      timestamp: timestamp,
    );
  }

  static String _normalizeHomeserver(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty) {
      throw const MatrixClientException('Homeserver is required.');
    }
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'https://$normalized';
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
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
    return error.message ?? 'Matrix request failed.';
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static List<dynamic> _asList(dynamic value) {
    return value is List ? value : const <dynamic>[];
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class MatrixSession {
  const MatrixSession({
    required this.homeserver,
    required this.accessToken,
    required this.userId,
    this.deviceId,
  });

  final String homeserver;
  final String accessToken;
  final String userId;
  final String? deviceId;

  factory MatrixSession.fromJson(Map<String, dynamic> json) {
    return MatrixSession(
      homeserver: json['homeserver'] as String? ?? '',
      accessToken: json['accessToken'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      deviceId: json['deviceId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'homeserver': homeserver,
    'accessToken': accessToken,
    'userId': userId,
    if (deviceId != null) 'deviceId': deviceId,
  };
}

class MatrixRoomSummary {
  const MatrixRoomSummary({
    required this.roomId,
    required this.name,
    this.lastMessage,
    this.unreadCount = 0,
  });

  final String roomId;
  final String name;
  final MatrixMessage? lastMessage;
  final int unreadCount;
}

class MatrixMessage {
  const MatrixMessage({
    required this.eventId,
    required this.sender,
    required this.body,
    required this.timestamp,
    this.encrypted = false,
  });

  final String eventId;
  final String sender;
  final String body;
  final DateTime timestamp;
  final bool encrypted;
}

class MatrixClientException implements Exception {
  const MatrixClientException(this.message);

  final String message;

  @override
  String toString() => message;
}
