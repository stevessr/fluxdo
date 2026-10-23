import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/incoming_content.dart';

void main() {
  test('accepts share payloads and filters invalid files', () {
    final content = IncomingContent.fromMap({
      'action': 'share',
      'title': ' Title ',
      'text': 'a link',
      'files': [
        {'path': '/tmp/a.png', 'name': 'a.png', 'image': true, 'mimeType': 'image/png'},
        {'path': '', 'name': 'bad', 'image': true},
        {'name': 'missing path'},
      ],
    });
    expect(content?.action, 'share');
    expect(content?.title, 'Title');
    expect(content?.text, 'a link');
    expect(content?.attachments, hasLength(1));
    expect(content?.attachments.single.isImage, isTrue);
    expect(content?.attachments.single.mimeType, 'image/png');
  });

  test('rejects unsolicited actions and malformed intents', () {
    expect(IncomingContent.fromMap({'action': 'delete'}), isNull);
    expect(IncomingContent.fromMap(null), isNull);
    expect(IncomingContent.fromMap({'action': 'search'})?.attachments, isEmpty);
  });

  test('recognizes shared media using MIME or extension', () {
    final items = IncomingContent.fromMap({
      'action': 'share',
      'files': [
        {'path': '/cache/track.bin', 'name': 'recording.bin', 'mimeType': 'audio/mpeg', 'image': false},
        {'path': '/cache/clip.mp4', 'name': 'clip.mp4', 'mimeType': 'application/octet-stream', 'image': false},
        {'path': '/cache/photo.png', 'name': 'photo.png', 'mimeType': 'image/png', 'image': true},
      ],
      'skippedFiles': 2,
    })!;
    expect(items.skippedFiles, 2);
    expect(items.attachments[0].isAudio, isTrue);
    expect(items.attachments[1].isVideo, isTrue);
    expect(items.attachments[2].isVideo, isFalse);
    expect(items.attachments[2].isAudio, isFalse);
  });

  test('invalid skipped count is safely normalized', () {
    expect(IncomingContent.fromMap({'action': 'share', 'skippedFiles': -5})!.skippedFiles, 0);
    expect(IncomingContent.fromMap({'action': 'share', 'skippedFiles': 20000})!.skippedFiles, 1000);
    expect(IncomingContent.fromMap({'action': 'share', 'skippedFiles': 'bad'})!.skippedFiles, 0);
  });
}
