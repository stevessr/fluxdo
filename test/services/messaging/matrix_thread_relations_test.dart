import 'package:fluxdo/services/messaging/matrix_thread_relations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps thread messages and relation descendants but not root reactions', () {
    final events = <Map<String, dynamic>>[
      _threadMessage(r'$t1', r'$root', 'one'),
      _reaction(r'$r1', r'$t1'),
      _edit(r'$e1', r'$t1'),
      _redaction(r'$redactReaction', r'$r1'),
      _reaction(r'$rootReaction', r'$root'),
      _threadMessage(r'$otherThread', r'$otherRoot', 'other'),
    ];

    final filtered = filterMatrixThreadRelations(r'$root', events);
    final ids = filtered.map((event) => event['event_id']).toSet();

    expect(
      ids,
      <String>{r'$t1', r'$r1', r'$e1', r'$redactReaction'},
    );
  });

  test('returns an empty closure when the root has no thread children', () {
    final filtered = filterMatrixThreadRelations(r'$root', <Map<String, dynamic>>[
      _reaction(r'$rootReaction', r'$root'),
    ]);
    expect(filtered, isEmpty);
  });
}

Map<String, dynamic> _threadMessage(
  String eventId,
  String root,
  String body,
) => <String, dynamic>{
  'type': 'm.room.message',
  'event_id': eventId,
  'sender': '@alice:example.org',
  'origin_server_ts': 1,
  'content': <String, dynamic>{
    'msgtype': 'm.text',
    'body': body,
    'm.relates_to': <String, dynamic>{
      'rel_type': 'm.thread',
      'event_id': root,
    },
  },
};

Map<String, dynamic> _reaction(String eventId, String target) =>
    <String, dynamic>{
      'type': 'm.reaction',
      'event_id': eventId,
      'sender': '@bob:example.org',
      'origin_server_ts': 2,
      'content': <String, dynamic>{
        'm.relates_to': <String, dynamic>{
          'rel_type': 'm.annotation',
          'event_id': target,
          'key': '👍',
        },
      },
    };

Map<String, dynamic> _edit(String eventId, String target) => <String, dynamic>{
  'type': 'm.room.message',
  'event_id': eventId,
  'sender': '@alice:example.org',
  'origin_server_ts': 3,
  'content': <String, dynamic>{
    'msgtype': 'm.text',
    'body': '* edited',
    'm.new_content': <String, dynamic>{'msgtype': 'm.text', 'body': 'edited'},
    'm.relates_to': <String, dynamic>{
      'rel_type': 'm.replace',
      'event_id': target,
    },
  },
};

Map<String, dynamic> _redaction(String eventId, String target) =>
    <String, dynamic>{
      'type': 'm.room.redaction',
      'event_id': eventId,
      'sender': '@mod:example.org',
      'origin_server_ts': 4,
      'redacts': target,
      'content': <String, dynamic>{},
    };
