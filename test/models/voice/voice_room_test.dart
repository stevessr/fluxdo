import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/voice/voice_room.dart';

void main() {
  group('VoiceRoom', () {
    test('parses room serializer payload and participant metadata', () {
      final room = VoiceRoom.fromJson({
        'id': 42,
        'name': 'Core voice',
        'slug': 'core-voice',
        'description': 'A room',
        'public': true,
        'ephemeral': false,
        'room_type': 'stage',
        'max_participants': 25,
        'member_count': 7,
        'message_bus_last_id': 1234,
        'creator_id': 5,
        'can_manage': true,
        'can_invite': true,
        'video_enabled': true,
        'video_allowed': true,
        'chat_available': true,
        'chat_channel_id': 99,
        'expected_transport': 'livekit',
        'max_quality_profile': 'high',
        'recording': {'status': 'recording'},
        'membership': {
          'id': 3,
          'user_id': 5,
          'role': 1,
          'role_name': 'moderator',
        },
        'active_participants': [
          {
            'id': 5,
            'username': 'alice',
            'name': 'Alice',
            'avatar_template': '/user_avatar/{size}/1.png',
            'role': 'moderator',
            'is_muted': true,
            'is_video_on': true,
            'is_screen_sharing': false,
            'watching_video': true,
            'is_transcribing': false,
            'idle_state': 'active',
            'hand_raised_at': 123.5,
          },
        ],
      });

      expect(room.id, 42);
      expect(room.roomType, 'stage');
      expect(room.expectedTransport, 'livekit');
      expect(room.recording?['status'], 'recording');
      expect(room.membership?.role, 'moderator');
      expect(room.activeParticipants, hasLength(1));
      expect(room.activeParticipants.single.username, 'alice');
      expect(room.activeParticipants.single.muted, isTrue);
      expect(room.activeParticipants.single.videoOn, isTrue);
      expect(room.activeParticipants.single.handRaisedAt, 123.5);
    });

    test('keeps serializer-omitted manager-only fields nullable', () {
      final room = VoiceRoom.fromJson({
        'id': 1,
        'name': 'Public room',
        'slug': 'public-room',
      });

      expect(room.livekitEnabled, isNull);
      expect(room.chatChannelId, isNull);
      expect(room.recording, isNull);
      expect(room.activeParticipants, isEmpty);
    });
  });

  group('VoiceRoomsResponse', () {
    test('parses directory metadata', () {
      final response = VoiceRoomsResponse.fromJson({
        'rooms': [
          {'id': 1, 'name': 'One', 'slug': 'one'},
        ],
        'can_create_room': true,
        'index_message_bus_last_id': 9001,
      });

      expect(response.rooms.single.name, 'One');
      expect(response.canCreateRoom, isTrue);
      expect(response.indexMessageBusLastId, 9001);
    });
  });

  group('VoiceJoinResponse', () {
    test('parses mesh join payload', () {
      final response = VoiceJoinResponse.fromJson({
        'transport': 'mesh',
        'participant_session_id': 'session-1',
        'ice': {
          'iceServers': [
            {'urls': 'stun:example.test'},
          ],
        },
        'room': {'id': 2, 'name': 'Mesh', 'slug': 'mesh'},
      });

      expect(response.usesMesh, isTrue);
      expect(response.usesLiveKit, isFalse);
      expect(response.participantSessionId, 'session-1');
      expect(response.ice['iceServers'], isNotNull);
      expect(response.livekit, isNull);
    });

    test('parses livekit join and refreshed participant session', () {
      final response = VoiceJoinResponse.fromJson({
        'transport': 'livekit',
        'participant_session_id': 'session-2',
        'room': {'id': 3, 'name': 'SFU', 'slug': 'sfu'},
        'livekit': {
          'url': 'wss://livekit.example.test',
          'token': 'jwt-token',
        },
      });
      final refreshed = VoiceLiveKitCredentials.fromJson({
        'url': 'wss://livekit.example.test',
        'token': 'jwt-token-2',
        'participant_session_id': 'session-3',
      });

      expect(response.usesLiveKit, isTrue);
      expect(response.livekit?.token, 'jwt-token');
      expect(refreshed.participantSessionId, 'session-3');
    });
  });
}
