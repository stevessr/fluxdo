/// Models for Discourse's built-in `voice` core plugin.
///
/// The wire format mirrors `Voice::RoomSerializer` and the join response
/// introduced by discourse/discourse#43044. Keep the media-specific payloads
/// intentionally transport-agnostic here: the media layer consumes the raw
/// ICE/LiveKit configuration without coupling API parsing to a concrete SDK.
class VoiceParticipant {
  final int id;
  final String username;
  final String? name;
  final String? avatarTemplate;
  final String role;
  final bool muted;
  final bool deafened;
  final bool videoOn;
  final bool screenSharing;
  final bool watchingVideo;
  final bool transcribing;
  final String? idleState;
  final double? handRaisedAt;

  const VoiceParticipant({
    required this.id,
    required this.username,
    this.name,
    this.avatarTemplate,
    this.role = 'participant',
    this.muted = false,
    this.deafened = false,
    this.videoOn = false,
    this.screenSharing = false,
    this.watchingVideo = false,
    this.transcribing = false,
    this.idleState,
    this.handRaisedAt,
  });

  factory VoiceParticipant.fromJson(Map<String, dynamic> json) {
    return VoiceParticipant(
      id: _asInt(json['id']) ?? 0,
      username: json['username']?.toString() ?? '',
      name: json['name']?.toString(),
      avatarTemplate: json['avatar_template']?.toString(),
      role: json['role']?.toString() ?? 'participant',
      muted: _asBool(json['is_muted']),
      deafened: _asBool(json['is_deafened']),
      videoOn: _asBool(json['is_video_on']),
      screenSharing: _asBool(json['is_screen_sharing']),
      watchingVideo: _asBool(json['watching_video']),
      transcribing: _asBool(json['is_transcribing']),
      idleState: json['idle_state']?.toString(),
      handRaisedAt: _asDouble(json['hand_raised_at']),
    );
  }
}

class VoiceRoomMembership {
  final int? id;
  final int? userId;
  final String? role;

  const VoiceRoomMembership({this.id, this.userId, this.role});

  factory VoiceRoomMembership.fromJson(Map<String, dynamic> json) {
    return VoiceRoomMembership(
      id: _asInt(json['id']),
      userId: _asInt(json['user_id']),
      // Serializer exposes both the enum integer (`role`) and stable name.
      role: json['role_name']?.toString() ?? json['role']?.toString(),
    );
  }
}

class VoiceRoom {
  final int id;
  final String name;
  final String slug;
  final String? description;
  final String? cookedDescription;
  final String? descriptionExcerpt;
  final bool isPublic;
  final bool ephemeral;
  final String roomType;
  final int maxParticipants;
  final int memberCount;
  final int? messageBusLastId;
  final int? creatorId;
  final int? visitCount;
  final bool canManage;
  final bool canInvite;
  final bool videoEnabled;
  final bool videoAllowed;
  final bool chatAvailable;
  final int? chatChannelId;
  final int? chatIdleMinutes;
  final bool? livekitEnabled;
  final String? expectedTransport;
  final String? maxQualityProfile;
  final Map<String, dynamic>? recording;
  final VoiceRoomMembership? membership;
  final List<VoiceParticipant> activeParticipants;
  final List<Map<String, dynamic>> ringing;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const VoiceRoom({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.cookedDescription,
    this.descriptionExcerpt,
    this.isPublic = false,
    this.ephemeral = false,
    this.roomType = 'room',
    this.maxParticipants = 0,
    this.memberCount = 0,
    this.messageBusLastId,
    this.creatorId,
    this.visitCount,
    this.canManage = false,
    this.canInvite = false,
    this.videoEnabled = false,
    this.videoAllowed = false,
    this.chatAvailable = false,
    this.chatChannelId,
    this.chatIdleMinutes,
    this.livekitEnabled,
    this.expectedTransport,
    this.maxQualityProfile,
    this.recording,
    this.membership,
    this.activeParticipants = const [],
    this.ringing = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory VoiceRoom.fromJson(Map<String, dynamic> json) {
    final participants = (json['active_participants'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(VoiceParticipant.fromJson)
        .toList(growable: false);
    final membership = json['membership'];
    final rawRecording = json['recording'];

    return VoiceRoom(
      id: _asInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      description: json['description']?.toString(),
      cookedDescription: json['cooked_description']?.toString(),
      descriptionExcerpt: json['description_excerpt']?.toString(),
      isPublic: _asBool(json['public']),
      ephemeral: _asBool(json['ephemeral']),
      roomType: json['room_type']?.toString() ?? 'room',
      maxParticipants: _asInt(json['max_participants']) ?? 0,
      memberCount: _asInt(json['member_count']) ?? 0,
      messageBusLastId: _asInt(json['message_bus_last_id']),
      creatorId: _asInt(json['creator_id']),
      visitCount: _asInt(json['visit_count']),
      canManage: _asBool(json['can_manage']),
      canInvite: _asBool(json['can_invite']),
      videoEnabled: _asBool(json['video_enabled']),
      videoAllowed: _asBool(json['video_allowed']),
      chatAvailable: _asBool(json['chat_available']),
      chatChannelId: _asInt(json['chat_channel_id']),
      chatIdleMinutes: _asInt(json['chat_idle_minutes']),
      livekitEnabled: json.containsKey('livekit_enabled')
          ? _asBool(json['livekit_enabled'])
          : null,
      expectedTransport: json['expected_transport']?.toString(),
      maxQualityProfile: json['max_quality_profile']?.toString(),
      recording: rawRecording is Map
          ? Map<String, dynamic>.from(rawRecording)
          : null,
      membership: membership is Map
          ? VoiceRoomMembership.fromJson(Map<String, dynamic>.from(membership))
          : null,
      activeParticipants: participants,
      ringing: (json['ringing'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(growable: false),
      createdAt: _asDateTime(json['created_at']),
      updatedAt: _asDateTime(json['updated_at']),
    );
  }
}

class VoiceRoomsResponse {
  final List<VoiceRoom> rooms;
  final bool canCreateRoom;
  final int? indexMessageBusLastId;

  const VoiceRoomsResponse({
    required this.rooms,
    this.canCreateRoom = false,
    this.indexMessageBusLastId,
  });

  factory VoiceRoomsResponse.fromJson(Map<String, dynamic> json) {
    return VoiceRoomsResponse(
      rooms: (json['rooms'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VoiceRoom.fromJson)
          .toList(growable: false),
      canCreateRoom: _asBool(json['can_create_room']),
      indexMessageBusLastId: _asInt(json['index_message_bus_last_id']),
    );
  }
}

class VoiceJoinResponse {
  final String transport;
  final String participantSessionId;
  final VoiceRoom room;
  final Map<String, dynamic> ice;
  final VoiceLiveKitCredentials? livekit;

  const VoiceJoinResponse({
    required this.transport,
    required this.participantSessionId,
    required this.room,
    this.ice = const {},
    this.livekit,
  });

  bool get usesLiveKit => transport == 'livekit';
  bool get usesMesh => transport == 'mesh';

  factory VoiceJoinResponse.fromJson(Map<String, dynamic> json) {
    final rawRoom = json['room'];
    final rawIce = json['ice'];
    final rawLiveKit = json['livekit'];
    return VoiceJoinResponse(
      transport: json['transport']?.toString() ?? 'mesh',
      participantSessionId: json['participant_session_id']?.toString() ?? '',
      room: VoiceRoom.fromJson(
        rawRoom is Map ? Map<String, dynamic>.from(rawRoom) : const {},
      ),
      ice: rawIce is Map ? Map<String, dynamic>.from(rawIce) : const {},
      livekit: rawLiveKit is Map
          ? VoiceLiveKitCredentials.fromJson(
              Map<String, dynamic>.from(rawLiveKit),
            )
          : null,
    );
  }
}

class VoiceLiveKitCredentials {
  final String url;
  final String token;
  final String? participantSessionId;

  const VoiceLiveKitCredentials({
    required this.url,
    required this.token,
    this.participantSessionId,
  });

  factory VoiceLiveKitCredentials.fromJson(Map<String, dynamic> json) {
    return VoiceLiveKitCredentials(
      url: json['url']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      participantSessionId: json['participant_session_id']?.toString(),
    );
  }
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().toLowerCase();
  return text == 'true' || text == '1';
}

DateTime? _asDateTime(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}
