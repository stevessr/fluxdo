import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'messaging/matrix_message_content.dart';
import 'messaging/matrix_room_metadata.dart';
import 'messaging/matrix_timeline_event_cache.dart';
import 'messaging/matrix_timeline_reducer.dart';

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
  static const _timelineReducer = MatrixTimelineReducer();

  final Dio _dio;
  final FlutterSecureStorage _secureStorage;

  MatrixSession? _session;
  String? _syncToken;
  final Map<String, MatrixRoomSummary> _roomCache =
      <String, MatrixRoomSummary>{};

  /// Raw history already loaded for recently used rooms. Keeping relation
  /// events across page boundaries means an edit/reaction fetched on a newer
  /// page can still be applied when its target message is fetched later from
  /// older history, while the bounded cache prevents unbounded growth.
  final MatrixTimelineEventCache _timelineEventCache =
      MatrixTimelineEventCache();

  /// Dedicated bounded cache for relation pages used by thread views. Keeping
  /// it separate prevents recursive relation events from polluting the room's
  /// main timeline cache.
  final MatrixTimelineEventCache _threadEventCache = MatrixTimelineEventCache(
    maxRooms: 8,
    maxEventsPerRoom: 800,
  );

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
  Future<List<MatrixRoomSummary>> loadRooms({bool forceFull = false}) async {
    final current = _requireSession();
    if (forceFull) _resetSyncState();

    final filter = jsonEncode(<String, dynamic>{
      'room': <String, dynamic>{
        'state': <String, dynamic>{
          'types': <String>[
            'm.room.name',
            'm.room.canonical_alias',
            'm.room.encryption',
          ],
        },
        'timeline': <String, dynamic>{'limit': 12},
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
        final timeline = _asMap(roomData['timeline']);
        final timelineEvents = _asList(timeline['events']);
        final unread = _asMap(roomData['unread_notifications']);

        final metadata = resolveMatrixRoomMetadata(
          roomId: roomId,
          roomData: roomData,
          previousName: previous?.name,
          previousEncrypted: previous?.encrypted ?? false,
        );

        MatrixMessage? lastMessage = previous?.lastMessage;
        if (timelineEvents.isNotEmpty) {
          final reduced = _timelineReducer.reduce(timelineEvents);
          final visible = reduced.where((message) => !message.isThreadReply);
          if (visible.isNotEmpty) {
            lastMessage = MatrixMessage.fromReduced(visible.last);
          }
        }

        final hasUnreadCount = unread.containsKey('notification_count');
        _roomCache[roomId] = MatrixRoomSummary(
          roomId: roomId,
          name: metadata.name,
          lastMessage: lastMessage,
          unreadCount: hasUnreadCount
              ? _asInt(unread['notification_count'])
              : previous?.unreadCount ?? 0,
          encrypted: metadata.encrypted,
        );
      }

      for (final roomId in left.keys) {
        _roomCache.remove(roomId);
        _timelineEventCache.removeRoom(roomId);
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

  /// Loads room history while accumulating relation events across pages.
  /// Thread replies are intentionally hidden from the main timeline and are
  /// exposed through [loadThreadPage] instead.
  Future<MatrixMessagePage> loadMessagePage(
    String roomId, {
    int limit = 50,
    String? from,
  }) async {
    final current = _requireSession();
    final encodedRoomId = Uri.encodeComponent(roomId);

    try {
      final response = await _dio.get<dynamic>(
        '${current.homeserver}/_matrix/client/v3/rooms/$encodedRoomId/messages',
        queryParameters: <String, dynamic>{
          'dir': 'b',
          'limit': limit.clamp(1, 100),
          if (from != null && from.isNotEmpty) 'from': from,
        },
        options: _authorizedOptions(current),
      );
      final data = _asMap(response.data);
      final chunk = _asList(data['chunk']);
      _timelineEventCache.addAll(roomId, chunk);

      final reduced = _timelineReducer
          .reduce(_timelineEventCache.eventsFor(roomId))
          .where((message) => !message.isThreadReply);
      final end = data['end'];

      return MatrixMessagePage(
        messages: reduced
            .map(MatrixMessage.fromReduced)
            .toList(growable: false),
        endToken: end is String && end.isNotEmpty ? end : null,
      );
    } on DioException catch (error) {
      throw MatrixClientException(_matrixErrorMessage(error));
    }
  }

  /// Loads one page of recursive relations under a thread root.
  ///
  /// Matrix explicitly advises clients not to filter the relations endpoint by
  /// `rel_type=m.thread` when rebuilding a thread, because that would omit edits
  /// and reactions attached to threaded events. We therefore request recursive
  /// relations without a rel_type and filter the closure locally.
  Future<MatrixThreadPage> loadThreadPage(
    String roomId,
    String threadRootEventId, {
    int limit = 50,
    String? from,
  }) async {
    final current = _requireSession();
    if (threadRootEventId.isEmpty) {
      throw const MatrixClientException('Thread root event id is required.');
    }
    final encodedRoomId = Uri.encodeComponent(roomId);
    final encodedRootId = Uri.encodeComponent(threadRootEventId);
    final cacheKey = '$roomId\u0000$threadRootEventId';

    try {
      final response = await _dio.get<dynamic>(
        '${current.homeserver}/_matrix/client/v1/rooms/$encodedRoomId/'
        'relations/$encodedRootId',
        queryParameters: <String, dynamic>{
          'dir': 'b',
          'limit': limit.clamp(1, 100),
          'recurse': true,
          if (from != null && from.isNotEmpty) 'from': from,
        },
        options: _authorizedOptions(current),
      );
      final data = _asMap(response.data);
      _threadEventCache.addAll(cacheKey, _asList(data['chunk']));
      final relations = _threadRelationsForRoot(
        threadRootEventId,
        _threadEventCache.eventsFor(cacheKey),
      );
      final reduced = _timelineReducer
          .reduce(relations)
          .where((message) => message.threadRootEventId == threadRootEventId)
          .map(MatrixMessage.fromReduced)
          .toList(growable: false);
      final next = data['next_batch'];
      return MatrixThreadPage(
        messages: reduced,
        nextToken: next is String && next.isNotEmpty ? next : null,
      );
    } on DioException catch (error) {
      throw MatrixClientException(_matrixErrorMessage(error));
    }
  }

  Future<List<MatrixMessage>> loadMessages(
    String roomId, {
    int limit = 50,
  }) async {
    final page = await loadMessagePage(roomId, limit: limit);
    return page.messages;
  }

  /// Releases raw room timeline relation state once its page is closed.
  void releaseTimeline(String roomId) {
    _timelineEventCache.removeRoom(roomId);
  }

  void releaseThread(String roomId, String threadRootEventId) {
    _threadEventCache.removeRoom('$roomId\u0000$threadRootEventId');
  }

  Future<void> sendText(
    String roomId,
    String body, {
    String? replyToEventId,
    String? threadRootEventId,
    bool threadFallback = false,
  }) async {
    final current = _requireSession();
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;

    final encodedRoomId = Uri.encodeComponent(roomId);
    final transactionId = _newTransactionId();

    try {
      await _dio.put<void>(
        '${current.homeserver}/_matrix/client/v3/rooms/'
        '$encodedRoomId/send/m.room.message/$transactionId',
        data: buildMatrixTextMessageContent(
          trimmed,
          replyToEventId: replyToEventId,
          threadRootEventId: threadRootEventId,
          threadFallback: threadFallback,
        ),
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
    _timelineEventCache.clear();
    _threadEventCache.clear();
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

  static List<Map<String, dynamic>> _threadRelationsForRoot(
    String rootEventId,
    Iterable<dynamic> rawEvents,
  ) {
    final events = rawEvents
        .map(_asMap)
        .where((event) => event.isNotEmpty)
        .toList(growable: false);
    final includedIds = <String>{};
    final included = <Map<String, dynamic>>[];

    for (final event in events) {
      final content = _asMap(event['content']);
      final relation = _asMap(content['m.relates_to']);
      if (relation['rel_type'] == 'm.thread' &&
          relation['event_id'] == rootEventId) {
        included.add(event);
        final eventId = event['event_id'];
        if (eventId is String && eventId.isNotEmpty) includedIds.add(eventId);
      }
    }

    var changed = true;
    while (changed) {
      changed = false;
      for (final event in events) {
        final eventId = event['event_id'];
        if (eventId is String && includedIds.contains(eventId)) continue;
        final targetId = _relationTarget(event);
        if (targetId == null || !includedIds.contains(targetId)) continue;
        included.add(event);
        if (eventId is String && eventId.isNotEmpty) includedIds.add(eventId);
        changed = true;
      }
    }
    return included;
  }

  static String? _relationTarget(Map<String, dynamic> event) {
    if (event['type'] == 'm.room.redaction') {
      final content = _asMap(event['content']);
      final target = event['redacts'] ?? content['redacts'];
      return target is String && target.isNotEmpty ? target : null;
    }
    final relation = _asMap(_asMap(event['content'])['m.relates_to']);
    final target = relation['event_id'];
    return target is String && target.isNotEmpty ? target : null;
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
    this.encrypted = false,
  });

  final String roomId;
  final String name;
  final MatrixMessage? lastMessage;
  final int unreadCount;
  final bool encrypted;
}

class MatrixMessagePage {
  const MatrixMessagePage({
    required this.messages,
    this.endToken,
  });

  final List<MatrixMessage> messages;
  final String? endToken;
}

class MatrixThreadPage {
  const MatrixThreadPage({
    required this.messages,
    this.nextToken,
  });

  final List<MatrixMessage> messages;
  final String? nextToken;
}

class MatrixMessage {
  const MatrixMessage({
    required this.eventId,
    required this.sender,
    required this.body,
    required this.timestamp,
    this.encrypted = false,
    this.msgType,
    this.edited = false,
    this.redacted = false,
    this.reactions = const <String, int>{},
    this.replyToEventId,
    this.threadRootEventId,
    this.threadCount = 0,
    this.mediaUri,
    this.filename,
    this.mimeType,
    this.mediaSize,
    this.thumbnailUri,
    this.width,
    this.height,
    this.durationMs,
  });

  factory MatrixMessage.fromReduced(MatrixReducedMessage message) {
    return MatrixMessage(
      eventId: message.eventId,
      sender: message.senderId,
      body: message.body,
      timestamp: message.timestamp,
      encrypted: message.encrypted,
      msgType: message.msgType,
      edited: message.edited,
      redacted: message.redacted,
      reactions: message.reactions,
      replyToEventId: message.replyToEventId,
      threadRootEventId: message.threadRootEventId,
      threadCount: message.threadCount,
      mediaUri: message.mediaUri,
      filename: message.filename,
      mimeType: message.mimeType,
      mediaSize: message.mediaSize,
      thumbnailUri: message.thumbnailUri,
      width: message.width,
      height: message.height,
      durationMs: message.durationMs,
    );
  }

  final String eventId;
  final String sender;
  final String body;
  final DateTime timestamp;
  final bool encrypted;
  final String? msgType;
  final bool edited;
  final bool redacted;
  final Map<String, int> reactions;
  final String? replyToEventId;
  final String? threadRootEventId;
  final int threadCount;
  final String? mediaUri;
  final String? filename;
  final String? mimeType;
  final int? mediaSize;
  final String? thumbnailUri;
  final int? width;
  final int? height;
  final int? durationMs;

  bool get isThreadReply => threadRootEventId != null;
  bool get hasMedia => mediaUri != null;
  bool get isImage => msgType == 'm.image';
}

class MatrixClientException implements Exception {
  const MatrixClientException(this.message);

  final String message;

  @override
  String toString() => message;
}
