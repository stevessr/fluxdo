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

  test('text edit uses m.replace with canonical m.new_content', () {
    final content = buildMatrixTextReplacementContent(
      '  corrected text  ',
      targetEventId: r'$target',
    );

    expect(content, <String, dynamic>{
      'msgtype': 'm.text',
      'body': '* corrected text',
      'm.new_content': <String, dynamic>{
        'msgtype': 'm.text',
        'body': 'corrected text',
      },
      'm.relates_to': <String, dynamic>{
        'rel_type': 'm.replace',
        'event_id': r'$target',
      },
    });
  });

  test('text edit rejects empty replacement targets and bodies', () {
    expect(
      () => buildMatrixTextReplacementContent(' ', targetEventId: r'$target'),
      throwsArgumentError,
    );
    expect(
      () => buildMatrixTextReplacementContent('hello', targetEventId: ' '),
      throwsArgumentError,
    );
  });

  test('image media content keeps metadata and thread relation', () {
    final content = buildMatrixMediaMessageContent(
      contentUri: 'mxc://example.org/media',
      filename: 'photo.png',
      contentType: 'image/png',
      size: 1234,
      threadRootEventId: r'$root',
      replyToEventId: r'$latest',
      threadFallback: true,
    );

    expect(content['msgtype'], 'm.image');
    expect(content['body'], 'photo.png');
    expect(content['filename'], 'photo.png');
    expect(content['url'], 'mxc://example.org/media');
    expect(content['info'], <String, dynamic>{
      'mimetype': 'image/png',
      'size': 1234,
    });
    expect(content['m.relates_to'], <String, dynamic>{
      'rel_type': 'm.thread',
      'event_id': r'$root',
      'm.in_reply_to': <String, dynamic>{'event_id': r'$latest'},
      'is_falling_back': true,
    });
  });

  test('generic media sanitizes empty filename and negative size', () {
    final content = buildMatrixMediaMessageContent(
      contentUri: 'mxc://example.org/file',
      filename: '   ',
      contentType: '',
      size: -10,
    );

    expect(content['msgtype'], 'm.file');
    expect(content['body'], 'attachment');
    expect(content['info'], <String, dynamic>{
      'mimetype': 'application/octet-stream',
      'size': 0,
    });
  });
}
