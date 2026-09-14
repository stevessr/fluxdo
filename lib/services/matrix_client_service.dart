import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Lightweight Matrix Client-Server API adapter used by the experimental chat
/// hub.
///
/// The adapter deliberately keeps the dependency surface small while the
/// branch validates the multi-protocol architecture. It supports unencrypted
/// rooms and exposes encrypted events as placeholders. Room refreshes use the
/// Matrix `/sync` next_batch token so subsequent refreshes only fetch deltas
/// instead of re-downloading the full joined-room state.
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
  String? _syncToken;
  final Map<String, MatrixRoomSummary> _roomCache =
      <String, MatrixRoomSummary>{};

  MatrixSession? get session => _session;
  bool get isLoggedIn => _session != null;

  Future<MatrixSession?> restoreSession() async {
    if (_session != null) return _session;

    final raw = await _secureStorage.read(key: _sessionStorageKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final restored = MatrixSession.fromJson(decoded);
      if (restored.homeserver.isEmpty ||
          restored.accessToken.isEmpty ||
          restored.userId.isEmpty) {
        throw const FormatException('Incomplete Matrix session');
      }
      _session = restored;
      _resetSyncState();
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
  ///
  /// [userId] is optional because `/account/whoami` can provide the canonical
  /// user ID. If supplied, it is verified against the token owner.
  Future<MatrixSession> loginWithAccessToken({
    required String homeserver,
    String? userId,
    required String accessToken,
  }) async {
    final baseUrl = _normalizeHomeserver(homeserver);
    final normalizedToken = accessToken.trim();
    if (normalizedToken.isEmpty) {
      throw const MatrixClientException('Access token is required.');
    }

    final provisional = MatrixSession(
      homeserver: baseUrl,
      accessToken: normalizedToken,
      userId: userId?.trim() ?? '',
    );

    try {
      final response = await _dio.get<dynamic>(
        '$baseUrl/_matrix/client/v3/account/whoami',
        options: _authorizedOptions(provisional),
      );
      final data = _asMap(response.data);
      final verifiedUserId = data['user_id'] as String?;
      if (verifiedUserId == null || verifiedUserId.isEmpty) {
        throw const MatrixClientException('Matrix token verification failed.');
      }
      if (provisional.userId.isNotEmpty &&
          verifiedUserId != provisional.userId) {
        throw MatrixClientException(
          'Token belongs to $verifiedUserId, not ${provisional.userId}.',
        );
      }

      final session = MatrixSession(
        homeserver: baseUrl,
        accessToken: normalizedToken,
        userId: verifiedUserId,
        deviceId: data['device_id'] as String?,
      );
      await _persistSession(session);
      return session;
    } on DioException catch (error) {
      throw MatrixClientException(_matrixErrorMessage(error));
    }
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
    _resetSyncState();
    await _secureStorage.delete(key: _sessionStorageKey);
  }

  /// Loads joined rooms using Matrix incremental sync.
  ///
  /// The first call requests the compact state needed by the room list. The
  /// returned `next_batch` token is retained in memory. Later calls pass it as
  /// `since`, merge only changed rooms into [_roomCache], and remove rooms that
  /// appear in the `leave` section. [forceFull] intentionally discards this
  /// state and starts a new initial sync.
  Future<List<MatrixRoomSummary>> loadRooms({bool forceFull = false}) async {
    final current = _requireSession();
    if (forceFull) _resetSyncState();

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
        'account_data': <String, dynamic>{'types': <String>[]},
      },
      'presence': <String, dynamic>{'types': <String>[]},
    });

    final queryParameters = <String, dynamic>{
      'timeout': 0,
      'filter': filter,
      if (_syncToken != null) 'since': _syncToken,
    };

    try {
      final response = await _dio.get<dynamic>(
        '${current.homeserver}/_matrix/client/v3/sync',
        queryParameters: queryParameters,
        options: _authorizedOptions(current),
      );
      final data = _asMap(response.data);
      final rooms = _asMap(data['rooms']);
      final joined = _asMap(rooms['join']);
      final left = _asMap(rooms['leave']);

      for (final entry in joined.entries) {
        final roomId = entry.key;
        final roomData = _asMap(entry.value);
        final previous = _roomCache[roomId];
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
            if (value is String && value.trim().isNotEmpty) {
              name = value.trim();
            }
          } else if (type == 'm.room.canonical_alias') {
            final value = content['alias'];
            if (value is String && value.trim().isNotEmpty) {
              alias = value.trim();
            }
          }
        }

        MatrixMessage? lastMessage = previous?.lastMessage;
        if (timelineEvents.isNotEmpty) {
          for (final rawEvent in timelineEvents.reversed) {
            final parsed = _parseMessage(
              _asMap(rawEvent),
              allowUnsupported: true,
            );
            if (parsed != null) {
              lastMessage = parsed;
              break;
            }
          }
        }

        final hasUnreadCount = unread.containsKey('notification_count');
        _roomCache[roomId] = MatrixRoomSummary(
          roomId: roomId,
          name: name ?? alias ?? previous?.name ?? roomId,
          lastMessage: lastMessage,
          unreadCount: hasUnreadCount
              ? _asInt(unread['notification_count'])
              : previous?.unreadCount ?? 0,
        );
      }

      for (final roomId in left.keys) {
        _roomCache.remove(roomId);
      }

      final nextBatch = data['next_batch'];
      if (nextBatch is String && nextBatch.isNotEmpty) {
        _syncToken = nextBatch;
      }

      final result = _roomCache.values.toList(growable: false)
        ..sort((a, b) {
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
    final transactionId = _newTransactionId();

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

  Future<void> sendReaction(
    String roomId,
    String eventId,
    String key,
  ) async {
    final current = _requireSession();
    final reaction = key.trim();
    if (reaction.isEmpty) return;

    final encodedRoomId = Uri.encodeComponent(roomId);
    final transactionId = _newTransactionId();

    try {
      await _dio.put<void>(
        '${current.homeserver}/_matrix/client/v3/rooms/'
        '$encodedRoomId/send/m.reaction/$transactionId',
        data: <String, dynamic>{
          'm.relates_to': <String, dynamic>{
            'rel_type': 'm.annotation',
            'event_id': eventId,
            'key': reaction,
          },
        },
        options: _authorizedOptions(current),
      );
    } on DioException catch (error) {
      throw MatrixClientException(_matrixErrorMessage(error));
    }
  }

  /// Sends a public read receipt for [eventId].
  Future<void> markRead(String roomId, String eventId) async {
    final current = _requireSession();
    if (eventId.isEmpty) return;

    final encodedRoomId = Uri.encodeComponent(roomId);
    final encodedEventId = Uri.encodeComponent(eventId);
    try {
      await _dio.post<void>(
        '${current.homeserver}/_matrix/client/v3/rooms/'
        '$encodedRoomId/receipt/m.read/$encodedEventId',
        data: const <String, dynamic>{},
        options: _authorizedOptions(current),
      );
    } on DioException catch (error) {
      throw MatrixClientException(_matrixErrorMessage(error));
    }
  }

  /// Updates the current user's typing state for a room.
  Future<void> setTyping(
    String roomId, {
    required bool typing,
    int timeoutMs = 30000,
  }) async {
    final current = _requireSession();
    final encodedRoomId = Uri.encodeComponent(roomId);
    final encodedUserId = Uri.encodeComponent(current.userId);

    try {
      await _dio.put<void>(
        '${current.homeserver}/_matrix/client/v3/rooms/'
        '$encodedRoomId/typing/$encodedUserId',
        data: <String, dynamic>{
          'typing': typing,
          if (typing) 'timeout': timeoutMs.clamp(1000, 120000),
        },
        options: _authorizedOptions(current),
      );
    } on DioException catch (error) {
      throw MatrixClientException(_matrixErrorMessage(error));
    }
  }

  Future<void> _persistSession(MatrixSession session) async {
    final changedAccount = _session?.homeserver != session.homeserver ||
        _session?.userId != session.userId;
    _session = session;
    if (changedAccount) _resetSyncState();
    await _secureStorage.write(
      key: _sessionStorageKey,
      value: jsonEncode(session.toJson()),
    );
  }

  void _resetSyncState() {
    _syncToken = null;
    _roomCache.clear();
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
        msgType: msgType,
      );
    }

    return MatrixMessage(
      eventId: eventId,
      sender: sender,
      body: msgType == 'm.emote' ? '* $body' : body,
      timestamp: timestamp,
      msgType: msgType,
    );
  }

  static String _newTransactionId() =>
      'fluxdo-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

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
    this.msgType,
  });

  final String eventId;
  final String sender;
  final String body;
  final DateTime timestamp;
  final bool encrypted;
  final String? msgType;
}

class MatrixClientException implements Exception {
  const MatrixClientException(this.message);

  final String message;

  @override
  String toString() => message;
}
