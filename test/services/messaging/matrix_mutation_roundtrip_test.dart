import 'package:fluxdo/services/messaging/matrix_message_content.dart';
import 'package:fluxdo/services/messaging/matrix_timeline_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const reducer = MatrixTimelineReducer();

  test('applies an edit until the original event is redacted', () {
    final original = <String, dynamic>{
      'type': 'm.room.message',
      'event_id': r'$message',
      'sender': '@alice:example.org',
      'origin_server_ts': 100,
      'content': <String, dynamic>{
        'msgtype': 'm.text',
        'body': 'original',
      },
    };
    final edit = <String, dynamic>{
      'type': 'm.room.message',
      'event_id': r'$edit',
      'sender': '@alice:example.org',
      'origin_server_ts': 200,
      'content': buildMatrixTextReplacementContent(
        'edited',
        targetEventId: r'$message',
      ),
    };

    final edited = reducer.reduce(<Map<String, dynamic>>[original, edit]);
    expect(edited, hasLength(1));
    expect(edited.single.body, 'edited');
    expect(edited.single.edited, isTrue);
    expect(edited.single.redacted, isFalse);

    final redaction = <String, dynamic>{
      'type': 'm.room.redaction',
      'event_id': r'$redaction',
      'sender': '@alice:example.org',
      'origin_server_ts': 300,
      'content': <String, dynamic>{'redacts': r'$message'},
    };
    final redacted = reducer.reduce(<Map<String, dynamic>>[
      original,
      edit,
      redaction,
    ]);

    expect(redacted, hasLength(1));
    expect(redacted.single.body, 'Message redacted');
    expect(redacted.single.edited, isFalse);
    expect(redacted.single.redacted, isTrue);
  });
}
