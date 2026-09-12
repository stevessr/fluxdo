part of 'discourse_service.dart';

/// Discourse built-in Voice core plugin API.
///
/// Voice is a core plugin (discourse/discourse#43044), not a site-specific
/// customization. Capability is therefore gated by the server-provided
/// `voice_enabled` site setting and all endpoints live below `/voice`.
mixin _VoiceMixin on _DiscourseServiceBase {
  /// Whether the current Discourse site advertises the Voice core plugin.
  bool get isVoiceEnabled =>
      PreloadedDataService().siteSettingsSync?['voice_enabled'] == true;

  /// Public/persistent room directory.
  Future<VoiceRoomsResponse> getVoiceRooms() async {
    try {
      final response = await _dio.get('/voice/rooms');
      return VoiceRoomsResponse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// Current room snapshot. [room] can be a numeric id or slug.
  Future<VoiceRoom> getVoiceRoom(Object room) async {
    try {
      final response = await _dio.get('/voice/rooms/$room');
      final data = Map<String, dynamic>.from(response.data as Map);
      final rawRoom = data['room'];
      return VoiceRoom.fromJson(
        rawRoom is Map ? Map<String, dynamic>.from(rawRoom) : data,
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// Start an ephemeral direct call and ring [username].
  Future<VoiceRoom> startVoiceCall(String username) async {
    try {
      final response = await _dio.post(
        '/voice/calls',
        data: {'username': username},
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      final rawRoom = data['room'];
      return VoiceRoom.fromJson(
        rawRoom is Map ? Map<String, dynamic>.from(rawRoom) : data,
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// Join a room and obtain the server-attested participant session.
  ///
  /// The returned [VoiceJoinResponse.transport] is authoritative. `mesh`
  /// requires Voice signaling + WebRTC peers; `livekit` carries credentials
  /// for the SFU. Passing an existing [participantSessionId] makes retries
  /// idempotent when the server still considers that session live.
  Future<VoiceJoinResponse> joinVoiceRoom(
    Object room, {
    String? participantSessionId,
    String? invitedBy,
    bool skipStatus = false,
  }) async {
    try {
      final response = await _dio.post(
        '/voice/rooms/$room/join',
        data: {
          if (participantSessionId != null && participantSessionId.isNotEmpty)
            'participant_session_id': participantSessionId,
          if (invitedBy != null && invitedBy.isNotEmpty)
            'invited_by': invitedBy,
          if (skipStatus) 'skip_status': true,
        },
      );
      return VoiceJoinResponse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// Explicitly leave a room. A stale session is harmless server-side.
  Future<void> leaveVoiceRoom(
    Object room, {
    String? participantSessionId,
  }) async {
    try {
      await _dio.delete(
        '/voice/rooms/$room/leave',
        data: {
          if (participantSessionId != null && participantSessionId.isNotEmpty)
            'participant_session_id': participantSessionId,
        },
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// Refresh presence and the participant-session TTL.
  Future<void> heartbeatVoiceRoom(
    Object room, {
    required String participantSessionId,
    String? idleState,
  }) async {
    try {
      await _dio.post(
        '/voice/rooms/$room/heartbeat',
        data: {
          'participant_session_id': participantSessionId,
          if (idleState != null) 'idle_state': idleState,
        },
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// Fresh active roster, including Voice participant metadata.
  Future<List<VoiceParticipant>> getVoiceParticipants(Object room) async {
    try {
      final response = await _dio.get('/voice/rooms/$room/participants');
      final data = Map<String, dynamic>.from(response.data as Map);
      return (data['participants'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VoiceParticipant.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// Update participant media/UI state. Omitted fields are left untouched.
  Future<void> updateVoiceState(
    Object room, {
    required String participantSessionId,
    bool? muted,
    bool? deafened,
    bool? video,
    bool? screen,
    bool? watching,
    bool? transcribing,
  }) async {
    if (muted == null &&
        deafened == null &&
        video == null &&
        screen == null &&
        watching == null &&
        transcribing == null) {
      throw ArgumentError('Voice state update requires a changed field');
    }
    try {
      await _dio.post(
        '/voice/rooms/$room/state',
        data: {
          'participant_session_id': participantSessionId,
          if (muted != null) 'muted': muted,
          if (deafened != null) 'deafened': deafened,
          if (video != null) 'video': video,
          if (screen != null) 'screen': screen,
          if (watching != null) 'watching': watching,
          if (transcribing != null) 'transcribing': transcribing,
        },
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// Relay one validated mesh signaling payload through MessageBus.
  Future<void> sendVoiceSignal(
    Object room, {
    required String participantSessionId,
    required Map<String, dynamic> payload,
  }) async {
    try {
      await _dio.post(
        '/voice/rooms/$room/signal',
        data: {
          'participant_session_id': participantSessionId,
          'payload': payload,
        },
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// Refresh LiveKit credentials during reconnect. The response also rotates
  /// the participant session id, so callers must persist the returned value.
  Future<VoiceLiveKitCredentials> refreshVoiceLiveKitToken(Object room) async {
    try {
      final response = await _dio.post('/voice/rooms/$room/livekit_token');
      return VoiceLiveKitCredentials.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<void> requestVoiceToSpeak(
    Object room, {
    required String participantSessionId,
  }) async {
    try {
      await _dio.post(
        '/voice/rooms/$room/request_to_speak',
        data: {'participant_session_id': participantSessionId},
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// Withdraw the caller's hand, or dismiss [userId] when the server grants
  /// room-management permission. Dismissing another user does not require the
  /// manager to be an active participant, so [participantSessionId] is optional.
  Future<void> withdrawVoiceRequestToSpeak(
    Object room, {
    String? participantSessionId,
    int? userId,
  }) async {
    try {
      await _dio.delete(
        '/voice/rooms/$room/request_to_speak',
        data: {
          if (participantSessionId != null && participantSessionId.isNotEmpty)
            'participant_session_id': participantSessionId,
          if (userId != null) 'user_id': userId,
        },
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// Read the Voice-linked Chat session without mutating it.
  Future<Map<String, dynamic>> getVoiceChatSession(Object room) async {
    try {
      final response = await _dio.get('/voice/rooms/$room/chat_session');
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// Ensure the caller follows the linked channel and roll a stale session.
  Future<Map<String, dynamic>> ensureVoiceChatSession(Object room) async {
    try {
      final response = await _dio.post('/voice/rooms/$room/chat_session');
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// Send only the session-opening message. Once a thread exists, subsequent
  /// messages must use the normal Chat API, matching the server contract.
  Future<Map<String, dynamic>> sendVoiceOpeningChatMessage(
    Object room, {
    required String message,
  }) async {
    try {
      final response = await _dio.post(
        '/voice/rooms/$room/chat_message',
        data: {'message': message},
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<Map<String, dynamic>> startVoiceRecording(Object room) async {
    try {
      final response = await _dio.post('/voice/rooms/$room/recording');
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<void> stopVoiceRecording(Object room) async {
    try {
      await _dio.delete('/voice/rooms/$room/recording');
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }
}
