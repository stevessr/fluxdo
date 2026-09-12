import 'voice_room.dart';

/// Realtime events published by Discourse's built-in Voice core plugin.
///
/// Room events all share `/voice/rooms/:id`; directory mutations use
/// `/voice/rooms/index`. Keeping parsing here makes the transport/provider
/// layer independent from MessageBus' concrete client implementation.
sealed class VoiceRoomEvent {
  const VoiceRoomEvent({required this.roomId});

  final int roomId;

  factory VoiceRoomEvent.fromJson(Map<String, dynamic> json) {
    final roomId = _asInt(json['room_id']) ?? 0;
    switch (json['type']?.toString()) {
      case 'participants':
        return VoiceParticipantsEvent(
          roomId: roomId,
          participants: _mapList(json['participants'])
              .map(VoiceParticipant.fromJson)
              .toList(growable: false),
        );
      case 'signal':
        return VoiceSignalEvent(
          roomId: roomId,
          senderId: _asInt(json['sender_id']) ?? 0,
          sender: json['sender'] is Map
              ? Map<String, dynamic>.from(json['sender'] as Map)
              : const {},
          events: _mapList(json['events']),
        );
      case 'kicked':
        return VoiceKickedEvent(roomId: roomId);
      case 'role_change':
        return VoiceRoleChangeEvent(
          roomId: roomId,
          userId: _asInt(json['user_id']) ?? 0,
          role: json['role']?.toString() ?? 'participant',
        );
      case 'hand_raise':
        return VoiceHandRaiseEvent(
          roomId: roomId,
          userId: _asInt(json['user_id']) ?? 0,
          raised: _asBool(json['raised']),
          raisedAt: _asDouble(json['raised_at']),
          reason: json['reason']?.toString(),
        );
      case 'ringing':
        return VoiceRingingEvent(
          roomId: roomId,
          user: json['user'] is Map
              ? Map<String, dynamic>.from(json['user'] as Map)
              : const {},
          notifiedAt: _asInt(json['notified_at']),
        );
      default:
        return VoiceUnknownRoomEvent(roomId: roomId, payload: json);
    }
  }
}

final class VoiceParticipantsEvent extends VoiceRoomEvent {
  const VoiceParticipantsEvent({
    required super.roomId,
    required this.participants,
  });

  final List<VoiceParticipant> participants;
}

final class VoiceSignalEvent extends VoiceRoomEvent {
  const VoiceSignalEvent({
    required super.roomId,
    required this.senderId,
    required this.sender,
    required this.events,
  });

  final int senderId;
  final Map<String, dynamic> sender;
  final List<Map<String, dynamic>> events;
}

final class VoiceKickedEvent extends VoiceRoomEvent {
  const VoiceKickedEvent({required super.roomId});
}

final class VoiceRoleChangeEvent extends VoiceRoomEvent {
  const VoiceRoleChangeEvent({
    required super.roomId,
    required this.userId,
    required this.role,
  });

  final int userId;
  final String role;
}

final class VoiceHandRaiseEvent extends VoiceRoomEvent {
  const VoiceHandRaiseEvent({
    required super.roomId,
    required this.userId,
    required this.raised,
    this.raisedAt,
    this.reason,
  });

  final int userId;
  final bool raised;
  final double? raisedAt;
  final String? reason;
}

final class VoiceRingingEvent extends VoiceRoomEvent {
  const VoiceRingingEvent({
    required super.roomId,
    required this.user,
    this.notifiedAt,
  });

  final Map<String, dynamic> user;
  final int? notifiedAt;
}

final class VoiceUnknownRoomEvent extends VoiceRoomEvent {
  const VoiceUnknownRoomEvent({required super.roomId, required this.payload});

  final Map<String, dynamic> payload;
}

class VoiceDirectoryEvent {
  const VoiceDirectoryEvent({required this.type, required this.room});

  final String type;
  final VoiceRoom room;

  bool get isCreated => type == 'created';
  bool get isUpdated => type == 'updated';
  bool get isDestroyed => type == 'destroyed';

  factory VoiceDirectoryEvent.fromJson(Map<String, dynamic> json) {
    final rawRoom = json['room'];
    return VoiceDirectoryEvent(
      type: json['type']?.toString() ?? '',
      room: VoiceRoom.fromJson(
        rawRoom is Map ? Map<String, dynamic>.from(rawRoom) : const {},
      ),
    );
  }
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList(growable: false);
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
