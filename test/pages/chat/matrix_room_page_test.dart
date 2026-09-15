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
}

class _FakeMatrixClient extends matrix.MatrixClientService {
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
    return const matrix.MatrixMessagePage(
      messages: <matrix.MatrixMessage>[],
    );
  }

  @override
  void releaseTimeline(String roomId) {
    releaseTimelineCalls++;
    releasedRoomId = roomId;
  }

  @override
  Future<void> setTyping(
    String roomId, {
    required bool typing,
    int timeoutMs = 30000,
  }) async {}
}
