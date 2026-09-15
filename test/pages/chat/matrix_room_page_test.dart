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
      MaterialApp(home: MatrixRoomPage(client: client, room: room)),
    );
    await tester.pump();

    expect(client.loadPageCalls, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(client.releaseTimelineCalls, 1);
    expect(client.releasedRoomId, room.roomId);
  });

  testWidgets('pauses room polling while a thread route is visible', (
    tester,
  ) async {
    final client = _FakeMatrixClient(withThread: true);

    await tester.pumpWidget(
      MaterialApp(home: MatrixRoomPage(client: client, room: room)),
    );
    await tester.pump();
    expect(client.loadPageCalls, 1);

    await tester.tap(find.text('1 条线程回复'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Thread ·'), findsOneWidget);

    // The underlying room stays mounted while the Thread route is on top.
    // Even a background -> foreground transition must not restart its timer.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    // The room refresh interval is 20 seconds. Advancing beyond it while the
    // thread route is visible must not issue another room /messages request.
    await tester.pump(const Duration(seconds: 21));
    expect(client.loadPageCalls, 1);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pumpAndSettle();

    // Returning performs one immediate latest refresh and restarts the timer.
    expect(client.loadPageCalls, 2);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
  });
}

class _FakeMatrixClient extends matrix.MatrixClientService {
  _FakeMatrixClient({this.withThread = false});

  final bool withThread;
  int loadPageCalls = 0;
  int releaseTimelineCalls = 0;
  String? releasedRoomId;

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
    if (!withThread) {
      return const matrix.MatrixMessagePage(
        messages: <matrix.MatrixMessage>[],
      );
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
  }) async => const matrix.MatrixThreadPage(
    messages: <matrix.MatrixMessage>[],
  );

  @override
  void releaseTimeline(String roomId) {
    releaseTimelineCalls++;
    releasedRoomId = roomId;
  }

  @override
  void releaseThread(String roomId, String threadRootEventId) {}

  @override
  Future<void> setTyping(
    String roomId, {
    required bool typing,
    int timeoutMs = 30000,
  }) async {}
}
