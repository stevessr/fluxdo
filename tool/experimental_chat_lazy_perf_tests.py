from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, got {count}')
    return text.replace(old, new, 1)

telegram_path = Path('test/services/messaging/telegram_web_policy_test.dart')
telegram = telegram_path.read_text()
telegram = replace_once(
    telegram,
    "    test('does not interfere with subframe/resource navigation', () {\n",
    "    test('keeps blob/data downloads inside the trusted WebView engine', () {\n"
    "      expect(\n"
    "        TelegramWebPolicy.shouldUseWebViewDownload(\n"
    "          Uri.parse('blob:https://web.telegram.org/id'),\n"
    "        ),\n"
    "        isTrue,\n"
    "      );\n"
    "      expect(\n"
    "        TelegramWebPolicy.shouldUseWebViewDownload(\n"
    "          Uri.parse('data:application/octet-stream;base64,AA=='),\n"
    "        ),\n"
    "        isTrue,\n"
    "      );\n"
    "      expect(\n"
    "        TelegramWebPolicy.shouldUseWebViewDownload(\n"
    "          Uri.parse('https://example.com/file.zip'),\n"
    "        ),\n"
    "        isFalse,\n"
    "      );\n"
    "    });\n\n"
    "    test('does not interfere with subframe/resource navigation', () {\n",
    'telegram download policy test',
)
telegram_path.write_text(telegram)

reducer_path = Path('test/services/messaging/matrix_timeline_reducer_test.dart')
reducer = reducer_path.read_text()
reducer = replace_once(
    reducer,
    "  test('keeps encrypted events explicit and sorts messages chronologically', () {\n",
    "  test('rejects MXC userinfo before media reaches transport', () {\n"
    "    final event = _imageMessage(r'$userinfo', 100);\n"
    "    final content = event['content'] as Map<String, dynamic>;\n"
    "    content['url'] = 'mxc://user@example.org/media123';\n\n"
    "    final messages = reducer.reduce(<Map<String, dynamic>>[event]);\n\n"
    "    expect(messages, hasLength(1));\n"
    "    expect(messages.single.hasMedia, isFalse);\n"
    "    expect(messages.single.mediaUri, isNull);\n"
    "  });\n\n"
    "  test('keeps encrypted events explicit and sorts messages chronologically', () {\n",
    'mxc userinfo reducer test',
)
reducer_path.write_text(reducer)

# Expand the room-page fake so a widget test can open a thread, advance virtual
# time beyond the refresh interval, and prove the underlying room stops polling.
room_path = Path('test/pages/chat/matrix_room_page_test.dart')
room_path.write_text(r'''import 'package:fluxdo/pages/chat/matrix_room_page.dart';
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
    await tester.pump();
    expect(find.textContaining('Thread ·'), findsOneWidget);

    // The room refresh interval is 20 seconds. Advancing beyond it while the
    // thread route is visible must not issue another room /messages request.
    await tester.pump(const Duration(seconds: 21));
    expect(client.loadPageCalls, 1);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pump();
    await tester.pump();

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
''')

print('Lazy-chat performance tests staged successfully')
