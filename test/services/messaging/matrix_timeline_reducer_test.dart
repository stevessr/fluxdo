import 'package:fluxdo/services/messaging/matrix_timeline_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const reducer = MatrixTimelineReducer();

  test('hides relation events and applies the latest valid edit', () {
    final messages = reducer.reduce(<Map<String, dynamic>>[
      _message(r'$original', '@alice:example.org', 'old', 100),
      _edit(r'$edit1', r'$original', '@alice:example.org', 'first', 200),
      _edit(r'$edit2', r'$original', '@alice:example.org', 'latest', 300),
      _edit(r'$foreign', r'$original', '@mallory:example.org', 'bad', 400),
    ]);

    expect(messages, hasLength(1));
    expect(messages.single.eventId, r'$original');
    expect(messages.single.body, 'latest');
    expect(messages.single.edited, isTrue);
  });

  test('uses event id as deterministic edit tie breaker', () {
    final messages = reducer.reduce(<Map<String, dynamic>>[
      _message(r'$original', '@alice:example.org', 'old', 100),
      _edit(r'$aaa', r'$original', '@alice:example.org', 'first', 200),
      _edit(r'$bbb', r'$original', '@alice:example.org', 'second', 200),
    ]);

    expect(messages.single.body, 'second');
  });

  test('counts reactions once per sender and key', () {
    final messages = reducer.reduce(<Map<String, dynamic>>[
      _message(r'$message', '@alice:example.org', 'hello', 100),
      _reaction(r'$r1', r'$message', '@bob:example.org', '👍', 110),
      _reaction(r'$r2', r'$message', '@bob:example.org', '👍', 120),
      _reaction(r'$r3', r'$message', '@carol:example.org', '👍', 130),
      _reaction(r'$r4', r'$message', '@bob:example.org', '❤️', 140),
    ]);

    expect(messages.single.reactions, <String, int>{'👍': 2, '❤️': 1});
  });

  test('redaction removes a reaction from the local aggregate', () {
    final messages = reducer.reduce(<Map<String, dynamic>>[
      _message(r'$message', '@alice:example.org', 'hello', 100),
      _reaction(r'$r1', r'$message', '@bob:example.org', '👍', 110),
      _reaction(r'$r2', r'$message', '@carol:example.org', '👍', 120),
      _redaction(r'$redaction', r'$r1', 130),
    ]);

    expect(messages.single.reactions, <String, int>{'👍': 1});
  });

  test('redacted edit no longer replaces the message', () {
    final messages = reducer.reduce(<Map<String, dynamic>>[
      _message(r'$message', '@alice:example.org', 'hello', 100),
      _edit(r'$edit', r'$message', '@alice:example.org', 'edited', 110),
      _redaction(r'$redaction', r'$edit', 120),
    ]);

    expect(messages.single.body, 'hello');
    expect(messages.single.edited, isFalse);
  });

  test('keeps a redacted message position but strips relations', () {
    final messages = reducer.reduce(<Map<String, dynamic>>[
      _message(r'$message', '@alice:example.org', 'hello', 100),
      _reaction(r'$reaction', r'$message', '@bob:example.org', '👍', 110),
      _redaction(r'$redaction', r'$message', 120),
    ]);

    expect(messages, hasLength(1));
    expect(messages.single.redacted, isTrue);
    expect(messages.single.body, 'Message redacted');
    expect(messages.single.reactions, isEmpty);
  });

  test('consumes bundled m.replace when the edit is outside the chunk', () {
    final original = _message(r'$message', '@alice:example.org', 'old', 100);
    original['unsigned'] = <String, dynamic>{
      'm.relations': <String, dynamic>{
        'm.replace': _edit(
          r'$bundled',
          r'$message',
          '@alice:example.org',
          'bundled edit',
          200,
        ),
      },
    };

    final messages = reducer.reduce(<Map<String, dynamic>>[original]);

    expect(messages.single.body, 'bundled edit');
    expect(messages.single.edited, isTrue);
  });

  test('keeps encrypted events explicit and sorts messages chronologically', () {
    final messages = reducer.reduce(<Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'm.room.encrypted',
        'event_id': r'$encrypted',
        'sender': '@alice:example.org',
        'origin_server_ts': 300,
        'content': <String, dynamic>{},
      },
      _message(r'$message', '@bob:example.org', 'plain', 100),
    ]);

    expect(messages.map((message) => message.eventId), <String>[
      r'$message',
      r'$encrypted',
    ]);
    expect(messages.last.encrypted, isTrue);
  });
}

Map<String, dynamic> _message(
  String eventId,
  String sender,
  String body,
  int timestamp,
) => <String, dynamic>{
  'type': 'm.room.message',
  'event_id': eventId,
  'sender': sender,
  'origin_server_ts': timestamp,
  'content': <String, dynamic>{'msgtype': 'm.text', 'body': body},
};

Map<String, dynamic> _edit(
  String eventId,
  String target,
  String sender,
  String body,
  int timestamp,
) => <String, dynamic>{
  'type': 'm.room.message',
  'event_id': eventId,
  'sender': sender,
  'origin_server_ts': timestamp,
  'content': <String, dynamic>{
    'msgtype': 'm.text',
    'body': '* $body',
    'm.new_content': <String, dynamic>{'msgtype': 'm.text', 'body': body},
    'm.relates_to': <String, dynamic>{
      'rel_type': 'm.replace',
      'event_id': target,
    },
  },
};

Map<String, dynamic> _reaction(
  String eventId,
  String target,
  String sender,
  String key,
  int timestamp,
) => <String, dynamic>{
  'type': 'm.reaction',
  'event_id': eventId,
  'sender': sender,
  'origin_server_ts': timestamp,
  'content': <String, dynamic>{
    'm.relates_to': <String, dynamic>{
      'rel_type': 'm.annotation',
      'event_id': target,
      'key': key,
    },
  },
};

Map<String, dynamic> _redaction(
  String eventId,
  String target,
  int timestamp,
) => <String, dynamic>{
  'type': 'm.room.redaction',
  'event_id': eventId,
  'sender': '@moderator:example.org',
  'origin_server_ts': timestamp,
  'content': <String, dynamic>{'redacts': target},
};
