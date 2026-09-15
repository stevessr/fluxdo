from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f'anchor not found in {path}: {old[:160]!r}')
    file.write_text(text.replace(old, new, 1))


replace_once(
    'lib/pages/chat/matrix_room_page.dart',
    '''  }) async {\n    if (_refreshingLatest) return;\n    _refreshingLatest = true;\n\n''',
    '''  }) async {\n    if (_refreshingLatest) return;\n\n    // This fetch is newer than every invalidation observed before it starts, so\n    // let it consume that pending signal. Any `/sync` delta that arrives while\n    // the request is in flight will set the flag again and be drained later.\n    _pendingTimelineRefresh = false;\n    _refreshingLatest = true;\n\n''',
)

replace_once(
    'test/pages/chat/matrix_room_page_test.dart',
    '''import 'package:fluxdo/pages/chat/matrix_room_page.dart';\n''',
    '''import 'dart:async';\n\nimport 'package:fluxdo/pages/chat/matrix_room_page.dart';\n''',
)

anchor = '''  testWidgets('coalesces room invalidations while a thread route is visible', (\n    tester,\n  ) async {\n'''
new_test = r'''  testWidgets('explicit post-send refresh consumes older pending invalidation', (
    tester,
  ) async {
    final client = _FakeMatrixClient(withOwnMessage: true);
    final sendGate = Completer<void>();
    client.sendGate = sendGate;

    await tester.pumpWidget(
      MaterialApp(
        home: MatrixRoomPage(client: client, room: room),
      ),
    );
    await tester.pump();
    expect(client.loadPageCalls, 1);

    await tester.enterText(find.byType(TextField).last, 'hello');
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    expect(client.sendCalls, 1);

    // The sync invalidation arrives while send is busy, so it must be pending.
    client.roomUpdates.publish(room.roomId);
    await tester.pump();
    expect(client.loadPageCalls, 1);

    // Finishing send performs its explicit latest fetch. That fetch should
    // consume the older pending invalidation instead of issuing another fetch.
    sendGate.complete();
    await tester.pumpAndSettle();
    expect(client.loadPageCalls, 2);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
  });

'''
replace_once('test/pages/chat/matrix_room_page_test.dart', anchor, new_test + anchor)

replace_once(
    'test/pages/chat/matrix_room_page_test.dart',
    '''  final List<String> edits = <String>[];\n  final List<String> redactions = <String>[];\n\n''',
    '''  final List<String> edits = <String>[];\n  final List<String> redactions = <String>[];\n  Completer<void>? sendGate;\n  int sendCalls = 0;\n\n''',
)

replace_once(
    'test/pages/chat/matrix_room_page_test.dart',
    '''  @override\n  Future<void> setTyping(\n''',
    '''  @override\n  Future<void> sendText(\n    String roomId,\n    String body, {\n    String? replyToEventId,\n    String? threadRootEventId,\n    bool threadFallback = false,\n  }) async {\n    sendCalls++;\n    final gate = sendGate;\n    if (gate != null) await gate.future;\n  }\n\n  @override\n  Future<void> setTyping(\n''',
)

print('Matrix room refresh coalescing patch applied successfully')
