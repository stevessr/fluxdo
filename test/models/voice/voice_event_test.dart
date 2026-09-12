import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/voice/voice_event.dart';

void main() {
  group('VoiceRoomEvent', () {
    test('parses participants snapshots', () {
      final event = VoiceRoomEvent.fromJson({
        'type': 'participants',
        'room_id': 42,
        'participants': [
          {
            'id': 7,
            'username': 'alice',
            'role': 'moderator',
            'is_muted': true,
          },
        ],
      });

      expect(event, isA<VoiceParticipantsEvent>());
      final participants = event as VoiceParticipantsEvent;
      expect(participants.roomId, 42);
      expect(participants.participants.single.username, 'alice');
      expect(participants.participants.single.muted, isTrue);
    });

    test('parses batched mesh signaling envelope', () {
      final event = VoiceRoomEvent.fromJson({
        'type': 'signal',
        'room_id': 42,
        'sender_id': 9,
        'sender': {'id': 9, 'username': 'bob'},
        'events': [
          {'type': 'offer', 'sdp': 'v=0...'},
          {
            'type': 'candidate',
            'candidate': 'candidate:1 1 UDP 1 127.0.0.1 9999 typ host',
          },
        ],
      });

      expect(event, isA<VoiceSignalEvent>());
      final signal = event as VoiceSignalEvent;
      expect(signal.senderId, 9);
      expect(signal.sender['username'], 'bob');
      expect(signal.events, hasLength(2));
      expect(signal.events.first['type'], 'offer');
    });

    test('parses kick, role and hand events', () {
      expect(
        VoiceRoomEvent.fromJson({'type': 'kicked', 'room_id': 4}),
        isA<VoiceKickedEvent>(),
      );

      final role = VoiceRoomEvent.fromJson({
        'type': 'role_change',
        'room_id': 4,
        'user_id': 12,
        'role': 'moderator',
      }) as VoiceRoleChangeEvent;
      expect(role.userId, 12);
      expect(role.role, 'moderator');

      final hand = VoiceRoomEvent.fromJson({
        'type': 'hand_raise',
        'room_id': 4,
        'user_id': 13,
        'raised': true,
        'raised_at': 123.25,
        'reason': 'raised',
      }) as VoiceHandRaiseEvent;
      expect(hand.raised, isTrue);
      expect(hand.raisedAt, 123.25);
    });

    test('preserves unknown events for forward compatibility', () {
      final event = VoiceRoomEvent.fromJson({
        'type': 'future_event',
        'room_id': 5,
        'payload': 1,
      });
      expect(event, isA<VoiceUnknownRoomEvent>());
      expect((event as VoiceUnknownRoomEvent).payload['payload'], 1);
    });
  });

  group('VoiceDirectoryEvent', () {
    test('parses created/updated/destroyed room payloads', () {
      for (final type in ['created', 'updated', 'destroyed']) {
        final event = VoiceDirectoryEvent.fromJson({
          'type': type,
          'room': {'id': 8, 'name': 'Room', 'slug': 'room'},
        });
        expect(event.type, type);
        expect(event.room.id, 8);
      }
    });
  });
}
