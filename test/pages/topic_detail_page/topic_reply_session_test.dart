import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/topic_detail_page/controllers/topic_reply_session.dart';
import 'package:fluxdo/services/local_draft_store.dart';

void main() {
  TextEditingValue at(String text, [int? offset]) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: offset ?? text.length),
  );

  TopicReplySession activeSession() {
    final session = TopicReplySession(
      topicId: 1,
      localStore: LocalDraftStore(),
      confirmSwitch: (_, _) async => null,
    );
    session.activeNotifier.value = true;
    addTearDown(session.dispose);
    return session;
  }

  test('image upload tracks insertion point and blocks premature send', () async {
    final session = activeSession();
    session.text.value = at('before after', 6);
    final upload = Completer<String>();
    final pending = session.insertUploadedImage(() => upload.future);
    expect(session.uploadingImage, isTrue);
    var sent = false;
    await session.submit((_, _, _) async {
      sent = true;
      return true;
    });
    expect(sent, isFalse);
    session.close();
    expect(session.active, isTrue);
    session.text.value = at('Xbefore after', 13);
    upload.complete('![image](upload://example.png)');
    await pending;
    expect(session.text.text, 'Xbefore\n![image](upload://example.png)\n after');
    expect(session.uploadingImage, isFalse);
  });

  test('failed image upload releases sending guard without changing text', () async {
    final session = activeSession();
    session.text.value = at('draft');
    await expectLater(
      session.insertUploadedImage(() async => throw StateError('failed')),
      throwsStateError,
    );
    expect(session.uploadingImage, isFalse);
    expect(session.text.text, 'draft');
  });

  const quote = '[quote="a, post:2, topic:1"]\nhi\n[/quote]';

  test('空编辑器直接插入引用，后留空行，光标在其后', () {
    final v = TopicReplySession.withQuoteInserted(at(''), quote);
    expect(v.text, '$quote\n\n');
    expect(v.selection.baseOffset, v.text.length);
  });

  test('正文末尾插入时与正文隔一个空行', () {
    final v = TopicReplySession.withQuoteInserted(at('我觉得'), quote);
    expect(v.text, '我觉得\n\n$quote\n\n');
  });

  test('已有换行只补足到一个空行', () {
    expect(
      TopicReplySession.withQuoteInserted(at('我觉得\n'), quote).text,
      '我觉得\n\n$quote\n\n',
    );
    expect(
      TopicReplySession.withQuoteInserted(at('我觉得\n\n'), quote).text,
      '我觉得\n\n$quote\n\n',
    );
  });

  test('光标在中间时插在光标处，后文保留', () {
    final v = TopicReplySession.withQuoteInserted(at('前文后文', 2), quote);
    expect(v.text, '前文\n\n$quote\n\n后文');
    expect(v.selection.baseOffset, '前文\n\n$quote\n\n'.length);
  });

  test('引用自身多余的尾部空白被收掉', () {
    final v = TopicReplySession.withQuoteInserted(at(''), '$quote\n\n\n');
    expect(v.text, '$quote\n\n');
  });
}
