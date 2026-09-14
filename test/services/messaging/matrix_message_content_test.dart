import 'package:fluxdo/services/messaging/matrix_message_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plain text has no relation', () {
    expect(buildMatrixTextMessageContent('hello'), <String, dynamic>{
      'msgtype': 'm.text',
      'body': 'hello',
    });
  });

  test('rich reply uses m.in_reply_to without rel_type', () {
    final content = buildMatrixTextMessageContent(
      'reply',
      replyToEventId: r'$target',
    );

    expect(content['m.relates_to'], <String, dynamic>{
      'm.in_reply_to': <String, dynamic>{'event_id': r'$target'},
    });
  });

  test('thread fallback points at root and most recent known target', () {
    final content = buildMatrixTextMessageContent(
      'thread',
      threadRootEventId: r'$root',
      replyToEventId: r'$latest',
      threadFallback: true,
    );

    expect(content['m.relates_to'], <String, dynamic>{
      'rel_type': 'm.thread',
      'event_id': r'$root',
      'm.in_reply_to': <String, dynamic>{'event_id': r'$latest'},
      'is_falling_back': true,
    });
  });

  test('genuine reply inside thread does not set fallback flag', () {
    final content = buildMatrixTextMessageContent(
      'nested reply',
      threadRootEventId: r'$root',
      replyToEventId: r'$thread-event',
    );

    expect(content['m.relates_to'], <String, dynamic>{
      'rel_type': 'm.thread',
      'event_id': r'$root',
      'm.in_reply_to': <String, dynamic>{'event_id': r'$thread-event'},
    });
  });
}
