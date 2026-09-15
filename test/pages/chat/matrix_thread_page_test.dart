import 'package:fluxdo/pages/chat/matrix_thread_page.dart';
import 'package:fluxdo/services/matrix_client_service.dart' as matrix;
import 'package:fluxdo/services/messaging/matrix_media_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const room = matrix.MatrixRoomSummary(
    roomId: '!room:example.org',
    name: 'Example Room',
  );
  final root = matrix.MatrixMessage(
    eventId: r'$root',
    sender: '@alice:example.org',
    body: 'root message',
    timestamp: DateTime.fromMillisecondsSinceEpoch(100),
    threadCount: 1,
  );

  testWidgets('loads thread immediately on first mount and releases on dispose', (
    tester,
  ) async {
    final client = _FakeMatrixClient();
    final media = MatrixMediaService(session: client.session!);

    await tester.pumpWidget(
      MaterialApp(
        home: MatrixThreadPage(
          client: client,
          room: room,
          root: root,
          mediaService: media,
        ),
      ),
    );
    await tester.pump();

    expect(client.loadThreadCalls, 1);
    expect(find.text('loaded thread reply'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(client.releaseThreadCalls, 1);
    media.dispose();
  });

  testWidgets('stops pagination when homeserver repeats next_batch token', (
    tester,
  ) async {
    final client = _FakeMatrixClient(repeatPaginationToken: true);
    final media = MatrixMediaService(session: client.session!);

    await tester.pumpWidget(
      MaterialApp(
        home: MatrixThreadPage(
          client: client,
          room: room,
          root: root,
          mediaService: media,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('加载更多关系'), findsOneWidget);
    await tester.tap(find.text('加载更多关系'));
    await tester.pump();

    expect(client.loadThreadCalls, 2);
    expect(find.text('加载更多关系'), findsNothing);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    media.dispose();
  });
}

class _FakeMatrixClient extends matrix.MatrixClientService {
  _FakeMatrixClient({this.repeatPaginationToken = false});

  final bool repeatPaginationToken;
  int loadThreadCalls = 0;
  int releaseThreadCalls = 0;

  @override
  matrix.MatrixSession? get session => const matrix.MatrixSession(
    homeserver: 'https://example.org',
    accessToken: 'token',
    userId: '@me:example.org',
  );

  @override
  Future<matrix.MatrixThreadPage> loadThreadPage(
    String roomId,
    String threadRootEventId, {
    int limit = 50,
    String? from,
  }) async {
    loadThreadCalls++;
    return matrix.MatrixThreadPage(
      messages: <matrix.MatrixMessage>[
        matrix.MatrixMessage(
          eventId: r'$reply',
          sender: '@bob:example.org',
          body: 'loaded thread reply',
          timestamp: DateTime.fromMillisecondsSinceEpoch(200),
          threadRootEventId: threadRootEventId,
        ),
      ],
      nextToken: repeatPaginationToken ? 'same-token' : null,
    );
  }

  @override
  void releaseThread(String roomId, String threadRootEventId) {
    releaseThreadCalls++;
  }

  @override
  Future<void> sendText(
    String roomId,
    String body, {
    String? replyToEventId,
    String? threadRootEventId,
    bool threadFallback = false,
  }) async {}
}
