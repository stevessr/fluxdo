import 'dart:async';

import 'package:fluxdo/pages/chat/matrix_room_page.dart';
import 'package:fluxdo/services/matrix_client_service.dart' as matrix;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const room = matrix.MatrixRoomSummary(
    roomId: '!room:example.org',
    name: 'Example Room',
  );

  testWidgets('loads room timeline on mount and releases it on dispose', (
    tester,
  ) async {
    final client = _FakeMatrixClient();

    await tester.pumpWidget(
      MaterialApp(
        home: MatrixRoomPage(client: client, room: room),
      ),
    );
    await tester.pump();

    expect(client.loadPageCalls, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(client.releaseTimelineCalls, 1);
    expect(client.releasedRoomId, room.roomId);
  });

  testWidgets('edits and redacts own plaintext text messages', (tester) async {
    final client = _FakeMatrixClient(withOwnMessage: true);

    await tester.pumpWidget(
      MaterialApp(
        home: MatrixRoomPage(client: client, room: room),
      ),
    );
    await tester.pump();

    await tester.longPress(find.text('my message'));
    await tester.pumpAndSettle();
    expect(find.text('编辑消息'), findsOneWidget);
    expect(find.text('撤回消息'), findsOneWidget);
    await tester.tap(find.text('编辑消息'));
    await tester.pumpAndSettle();
    final editDialog = find.byType(AlertDialog);
    final editField = find.descendant(
      of: editDialog,
      matching: find.byType(TextFormField),
    );
    await tester.enterText(editField, 'updated message');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(client.edits, <String>[r'$mine|updated message']);

    await tester.longPress(find.text('my message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤回消息'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认撤回'));
    await tester.pumpAndSettle();
    expect(client.redactions, <String>[r'$mine']);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
  });

  testWidgets('refreshes only for the current room sync invalidation', (
    tester,
  ) async {
    final client = _FakeMatrixClient();

    await tester.pumpWidget(
      MaterialApp(
        home: MatrixRoomPage(client: client, room: room),
      ),
    );
    await tester.pump();
    expect(client.loadPageCalls, 1);

    client.roomUpdates.publish('!other:example.org');
    await tester.pump();
    await tester.pump();
    expect(client.loadPageCalls, 1);

    client.roomUpdates.publish(room.roomId);
    await tester.pump();
    await tester.pump();
    expect(client.loadPageCalls, 2);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
  });

  testWidgets('explicit post-send refresh consumes older pending invalidation', (
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

  testWidgets('coalesces room invalidations while a thread route is visible', (
    tester,
  ) async {
    final client = _FakeMatrixClient(withThread: true);

    await tester.pumpWidget(
      MaterialApp(
        home: MatrixRoomPage(client: client, room: room),
      ),
    );
    await tester.pump();
    expect(client.loadPageCalls, 1);

    await tester.tap(find.text('1 条线程回复'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Thread ·'), findsOneWidget);

    client.roomUpdates.publish(room.roomId);
    client.roomUpdates.publish(room.roomId);
    await tester.pump();
    await tester.pump();
    expect(client.loadPageCalls, 1);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pumpAndSettle();

    // Multiple deltas while the thread was open collapse into one refresh.
    expect(client.loadPageCalls, 2);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
  });
}

class _FakeMatrixClient extends matrix.MatrixClientService {
  _FakeMatrixClient({this.withThread = false, this.withOwnMessage = false});

  final bool withThread;
  final bool withOwnMessage;
  int loadPageCalls = 0;
  int releaseTimelineCalls = 0;
  String? releasedRoomId;
  final List<String> edits = <String>[];
  final List<String> redactions = <String>[];
  Completer<void>? sendGate;
  int sendCalls = 0;

  @override
  matrix.MatrixSession? get session => const matrix.MatrixSession(
    homeserver: 'https://example.org',
    accessToken: 'token',
    userId: '@me:example.org',
  );

  @override
  Future<matrix.MatrixMessagePage> loadMessagePage(
    String roomId, {
    int limit = 50,
    String? from,
  }) async {
    loadPageCalls++;
    if (withOwnMessage) {
      return matrix.MatrixMessagePage(
        messages: <matrix.MatrixMessage>[
          matrix.MatrixMessage(
            eventId: r'$mine',
            sender: '@me:example.org',
            body: 'my message',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
            msgType: 'm.text',
          ),
        ],
      );
    }
    if (!withThread) {
      return const matrix.MatrixMessagePage(messages: <matrix.MatrixMessage>[]);
    }
    return matrix.MatrixMessagePage(
      messages: <matrix.MatrixMessage>[
        matrix.MatrixMessage(
          eventId: r'$root',
          sender: '@alice:example.org',
          body: 'thread root',
          timestamp: DateTime.fromMillisecondsSinceEpoch(100),
          threadCount: 1,
        ),
      ],
    );
  }

  @override
  Future<matrix.MatrixThreadPage> loadThreadPage(
    String roomId,
    String threadRootEventId, {
    int limit = 50,
    String? from,
  }) async => const matrix.MatrixThreadPage(messages: <matrix.MatrixMessage>[]);

  @override
  void releaseTimeline(String roomId) {
    releaseTimelineCalls++;
    releasedRoomId = roomId;
  }

  @override
  void releaseThread(String roomId, String threadRootEventId) {}

  @override
  Future<void> sendText(
    String roomId,
    String body, {
    String? replyToEventId,
    String? threadRootEventId,
    bool threadFallback = false,
  }) async {
    sendCalls++;
    final gate = sendGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> setTyping(
    String roomId, {
    required bool typing,
    int timeoutMs = 30000,
  }) async {}

  @override
  Future<void> editText(String roomId, String eventId, String body) async {
    edits.add('$eventId|$body');
  }

  @override
  Future<void> redactEvent(
    String roomId,
    String eventId, {
    String? reason,
  }) async {
    redactions.add(eventId);
  }
}
