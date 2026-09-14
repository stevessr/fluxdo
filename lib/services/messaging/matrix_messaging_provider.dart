import '../matrix_client_service.dart';
import 'messaging_provider.dart';

/// Adapts the lightweight Matrix REST client to Fluxdo's protocol-neutral
/// native timeline contract.
///
/// This is deliberately a thin mapping layer. When the Extera-backed Matrix SDK
/// implementation is ready, it can implement [MessagingProvider] directly and
/// replace this adapter without leaking Matrix SDK classes into shared chat UI.
class MatrixMessagingProvider implements MessagingProvider {
  MatrixMessagingProvider(this.client);

  final MatrixClientService client;

  @override
  MessagingTransport get transport => MessagingTransport.matrix;

  @override
  MessagingCapabilities get capabilities => const MessagingCapabilities(
    nativeTimeline: true,
    readReceipts: true,
    typing: true,
    reactions: true,
    // The REST reducer can render remote m.replace events, but the common
    // provider does not expose an edit-send operation yet. Keep this false so
    // shared UI does not advertise an unsupported action.
    edits: false,
    threads: false,
    media: false,
    e2ee: false,
  );

  @override
  bool get isSignedIn => client.isLoggedIn;

  @override
  String? get currentUserId => client.session?.userId;

  @override
  Future<List<MessagingConversation>> loadConversations({
    bool forceRefresh = false,
  }) async {
    final rooms = await client.loadRooms(forceFull: forceRefresh);
    return rooms
        .map(
          (room) => MessagingConversation(
            id: room.roomId,
            title: room.name,
            preview: room.lastMessage?.body,
            unreadCount: room.unreadCount,
            lastActivity: room.lastMessage?.timestamp,
            encrypted: room.encrypted,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<MessagingMessage>> loadMessages(
    String conversationId, {
    int limit = 50,
  }) async {
    final messages = await client.loadMessages(conversationId, limit: limit);
    return messages
        .map(
          (message) => MessagingMessage(
            id: message.eventId,
            senderId: message.sender,
            body: message.body,
            timestamp: message.timestamp,
            encrypted: message.encrypted,
            edited: message.edited,
            reactions: message.reactions,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> sendText(String conversationId, String body) =>
      client.sendText(conversationId, body);

  @override
  Future<void> markRead(String conversationId, String messageId) =>
      client.markRead(conversationId, messageId);

  @override
  Future<void> setTyping(
    String conversationId, {
    required bool typing,
  }) => client.setTyping(conversationId, typing: typing);

  @override
  Future<void> sendReaction(
    String conversationId,
    String messageId,
    String reaction,
  ) => client.sendReaction(conversationId, messageId, reaction);
}
