import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/incoming_content.dart';

void main() {
  test('accepts share payloads and filters invalid files', () {
    final content = IncomingContent.fromMap({
      'action': 'share',
      'title': ' Title ',
      'text': 'a link',
      'files': [
        {'path': '/tmp/a.png', 'name': 'a.png', 'image': true},
        {'path': '', 'name': 'bad', 'image': true},
        {'name': 'missing path'},
      ],
    });
    expect(content?.action, 'share');
    expect(content?.title, 'Title');
    expect(content?.text, 'a link');
    expect(content?.attachments, hasLength(1));
    expect(content?.attachments.single.isImage, isTrue);
  });

  test('rejects unsolicited actions and malformed intents', () {
    expect(IncomingContent.fromMap({'action': 'delete'}), isNull);
    expect(IncomingContent.fromMap(null), isNull);
    expect(IncomingContent.fromMap({'action': 'search'})?.attachments, isEmpty);
  });
}
