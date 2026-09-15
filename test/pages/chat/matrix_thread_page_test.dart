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
  const encryptedRoom = matrix.MatrixRoomSummary(
    roomId: '!encrypted:example.org',
    name: 'Encrypted Room',
    encrypted: true,
  );
  final root = matrix.MatrixMessage(
    eventId: r'$root',
    sender: '@alice:example.org',
    body: 'root message',
    timestamp: DateTime.fromMillisecondsSinceEpoch(100),
    threadCount: 1,
  );

  testWidgets('loads thread immediately, marks read and releases on dispose', (
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
    expect(client.readEventIds, <String>[r'$reply']);
    expect(find.text('loaded thread reply'), findsOneWidget);
    expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);

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

  testWidgets('sends typing once and clears it after idle timeout', (
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

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(client.typingStates, <bool>[true]);

    await tester.pump(const Duration(seconds: 6));
    expect(client.typingStates, <bool>[true, false]);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    media.dispose();
  });

  testWidgets('long press can react to a thread message', (tester) async {
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

    await tester.longPress(find.text('loaded thread reply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reaction'));
    await tester.pumpAndSettle();
    expect(find.text('👍'), findsOneWidget);
    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();

    expect(client.sentReactions, <String>[r'$reply|👍']);
    expect(client.loadThreadCalls, 2);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    media.dispose();
  });

  testWidgets('edits and redacts own thread replies', (tester) async {
    final client = _FakeMatrixClient(ownReply: true);
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

    await tester.longPress(find.text('loaded thread reply'));
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
    await tester.enterText(editField, 'updated thread reply');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(client.edits, <String>[r'$reply|updated thread reply']);

    await tester.longPress(find.text('loaded thread reply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤回消息'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认撤回'));
    await tester.pumpAndSettle();
    expect(client.redactions, <String>[r'$reply']);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    media.dispose();
  });

  testWidgets('sends text as a thread relation with a reply fallback', (
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

    await tester.enterText(find.byType(TextField), 'thread reply');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    expect(client.sentTexts, <String>[r'thread reply|$root|$reply|true']);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    media.dispose();
  });

  testWidgets(
    'keeps plaintext composer and attachment actions disabled for E2EE',
    (tester) async {
      final client = _FakeMatrixClient();
      final media = MatrixMediaService(session: client.session!);

      await tester.pumpWidget(
        MaterialApp(
          home: MatrixThreadPage(
            client: client,
            room: encryptedRoom,
            root: root,
            mediaService: media,
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('SDK crypto provider'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      final attachButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.attach_file_rounded),
      );
      expect(attachButton.onPressed, isNull);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();
      media.dispose();
    },
  );
}

class _FakeMatrixClient extends matrix.MatrixClientService {
  _FakeMatrixClient({
    this.repeatPaginationToken = false,
    this.ownReply = false,
  });

  final bool repeatPaginationToken;
  final bool ownReply;
  int loadThreadCalls = 0;
  int releaseThreadCalls = 0;
  final List<String> readEventIds = <String>[];
  final List<bool> typingStates = <bool>[];
  final List<String> sentReactions = <String>[];
  final List<String> sentTexts = <String>[];
  final List<String> edits = <String>[];
  final List<String> redactions = <String>[];

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
          sender: ownReply ? '@me:example.org' : '@bob:example.org',
          body: 'loaded thread reply',
          timestamp: DateTime.fromMillisecondsSinceEpoch(200),
          msgType: 'm.text',
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
  Future<void> markRead(String roomId, String eventId) async {
    readEventIds.add(eventId);
  }

  @override
  Future<void> setTyping(
    String roomId, {
    required bool typing,
    int timeoutMs = 30000,
  }) async {
    typingStates.add(typing);
  }

  @override
  Future<void> sendReaction(String roomId, String eventId, String key) async {
    sentReactions.add('$eventId|$key');
  }

  @override
  Future<void> sendText(
    String roomId,
    String body, {
    String? replyToEventId,
    String? threadRootEventId,
    bool threadFallback = false,
  }) async {
    sentTexts.add('$body|$threadRootEventId|$replyToEventId|$threadFallback');
  }

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
