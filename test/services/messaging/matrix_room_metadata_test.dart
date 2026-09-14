import 'package:fluxdo/services/messaging/matrix_room_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefers explicit room name over alias and heroes', () {
    final metadata = resolveMatrixRoomMetadata(
      roomId: '!room:example.org',
      roomData: <String, dynamic>{
        'summary': <String, dynamic>{
          'm.heroes': <String>['@hero:example.org'],
        },
        'state': <String, dynamic>{
          'events': <Map<String, dynamic>>[
            _state('m.room.canonical_alias', <String, dynamic>{
              'alias': '#alias:example.org',
            }),
            _state('m.room.name', <String, dynamic>{'name': 'Named room'}),
          ],
        },
      },
    );

    expect(metadata.name, 'Named room');
  });

  test('uses canonical alias when there is no explicit name', () {
    final metadata = resolveMatrixRoomMetadata(
      roomId: '!room:example.org',
      roomData: <String, dynamic>{
        'state': <String, dynamic>{
          'events': <Map<String, dynamic>>[
            _state('m.room.canonical_alias', <String, dynamic>{
              'alias': '#alias:example.org',
            }),
          ],
        },
      },
    );

    expect(metadata.name, '#alias:example.org');
  });

  test('derives unnamed DM title from sync heroes without member requests', () {
    final metadata = resolveMatrixRoomMetadata(
      roomId: '!room:example.org',
      roomData: <String, dynamic>{
        'summary': <String, dynamic>{
          'm.heroes': <String>[
            '@alice:example.org',
            '@bob:example.org',
          ],
        },
      },
    );

    expect(metadata.name, 'alice, bob');
  });

  test('preserves useful previous name when incremental sync omits metadata', () {
    final metadata = resolveMatrixRoomMetadata(
      roomId: '!room:example.org',
      roomData: const <String, dynamic>{},
      previousName: 'Previous name',
    );

    expect(metadata.name, 'Previous name');
  });

  test('tracks encryption and never downgrades previous encrypted state', () {
    final first = resolveMatrixRoomMetadata(
      roomId: '!room:example.org',
      roomData: <String, dynamic>{
        'state': <String, dynamic>{
          'events': <Map<String, dynamic>>[
            _state('m.room.encryption', <String, dynamic>{
              'algorithm': 'm.megolm.v1.aes-sha2',
            }),
          ],
        },
      },
    );
    final incremental = resolveMatrixRoomMetadata(
      roomId: '!room:example.org',
      roomData: const <String, dynamic>{},
      previousEncrypted: first.encrypted,
    );

    expect(first.encrypted, isTrue);
    expect(incremental.encrypted, isTrue);
  });
}

Map<String, dynamic> _state(String type, Map<String, dynamic> content) =>
    <String, dynamic>{'type': type, 'content': content};
