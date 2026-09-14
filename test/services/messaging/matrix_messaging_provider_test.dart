import 'package:fluxdo/services/matrix_client_service.dart';
import 'package:fluxdo/services/messaging/matrix_messaging_provider.dart';
import 'package:fluxdo/services/messaging/messaging_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MatrixMessagingProvider', () {
    test('maps Matrix room and message models without leaking SDK types', () async {
      final client = _FakeMatrixClientService();
      final provider = MatrixMessagingProvider(client);

      final conversations = await provider.loadConversations();
      final messages = await provider.loadMessages('!room:example.org');

      expect(provider.transport, MessagingTransport.matrix);
      expect(provider.currentUserId, '@me:example.org');
      expect(provider.isSignedIn, isTrue);
      expect(provider.capabilities.nativeTimeline, isTrue);
      expect(provider.capabilities.reactions, isTrue);
      expect(provider.capabilities.e2ee, isFalse);

      expect(conversations, hasLength(1));
      expect(conversations.single.id, '!room:example.org');
      expect(conversations.single.title, 'Example Room');
      expect(conversations.single.preview, 'latest');
      expect(conversations.single.unreadCount, 3);

      expect(messages, hasLength(1));
      expect(messages.single.id, r'$event');
      expect(messages.single.senderId, '@alice:example.org');
      expect(messages.single.body, 'hello');
    });

    test('delegates common timeline actions to the REST client', () async {
      final client = _FakeMatrixClientService();
      final provider = MatrixMessagingProvider(client);

      await provider.sendText('!room:example.org', 'hi');
      await provider.markRead('!room:example.org', r'$event');
      await provider.setTyping('!room:example.org', typing: true);
      await provider.sendReaction('!room:example.org', r'$event', '👍');

      expect(client.sentText, ('!room:example.org', 'hi'));
      expect(client.readReceipt, ('!room:example.org', r'$event'));
      expect(client.typing, ('!room:example.org', true));
      expect(client.reaction, ('!room:example.org', r'$event', '👍'));
    });
  });
}

class _FakeMatrixClientService extends MatrixClientService {
  final MatrixSession _fakeSession = const MatrixSession(
    homeserver: 'https://example.org',
    accessToken: 'token',
    userId: '@me:example.org',
  );

  (String, String)? sentText;
  (String, String)? readReceipt;
  (String, bool)? typing;
  (String, String, String)? reaction;

  @override
  MatrixSession? get session => _fakeSession;

  @override
  bool get isLoggedIn => true;

  @override
  Future<List<MatrixRoomSummary>> loadRooms({bool forceFull = false}) async =>
      <MatrixRoomSummary>[
        MatrixRoomSummary(
          roomId: '!room:example.org',
          name: 'Example Room',
          unreadCount: 3,
          lastMessage: MatrixMessage(
            eventId: r'$latest',
            sender: '@alice:example.org',
            body: 'latest',
            timestamp: DateTime.fromMillisecondsSinceEpoch(20),
          ),
        ),
      ];

  @override
  Future<List<MatrixMessage>> loadMessages(
    String roomId, {
    int limit = 50,
  }) async =>
      <MatrixMessage>[
        MatrixMessage(
          eventId: r'$event',
          sender: '@alice:example.org',
          body: 'hello',
          timestamp: DateTime.fromMillisecondsSinceEpoch(10),
        ),
      ];

  @override
  Future<void> sendText(String roomId, String body) async {
    sentText = (roomId, body);
  }

  @override
  Future<void> markRead(String roomId, String eventId) async {
    readReceipt = (roomId, eventId);
  }

  @override
  Future<void> setTyping(
    String roomId, {
    required bool typing,
    int timeoutMs = 30000,
  }) async {
    this.typing = (roomId, typing);
  }

  @override
  Future<void> sendReaction(
    String roomId,
    String eventId,
    String key,
  ) async {
    reaction = (roomId, eventId, key);
  }
}
