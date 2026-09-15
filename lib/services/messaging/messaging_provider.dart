/// Common native-message semantics for the experimental multi-protocol chat
/// work.
///
/// The contract intentionally contains only operations that Matrix, Telegram
/// and Discourse can all reasonably map. Provider-specific login/account flows
/// stay outside this interface. This lets Fluxdo replace the lightweight Matrix
/// REST implementation with an Extera/matrix-sdk adapter later without making
/// the chat hub or shared message widgets depend on SDK types.
enum MessagingTransport { discourse, matrix, telegram }

class MessagingCapabilities {
  const MessagingCapabilities({
    required this.nativeTimeline,
    this.readReceipts = false,
    this.typing = false,
    this.reactions = false,
    this.edits = false,
    this.redactions = false,
    this.threads = false,
    this.media = false,
    this.e2ee = false,
  });

  final bool nativeTimeline;
  final bool readReceipts;
  final bool typing;
  final bool reactions;
  final bool edits;
  final bool redactions;
  final bool threads;
  final bool media;
  final bool e2ee;
}

class MessagingConversation {
  const MessagingConversation({
    required this.id,
    required this.title,
    this.preview,
    this.unreadCount = 0,
    this.lastActivity,
    this.encrypted = false,
  });

  final String id;
  final String title;
  final String? preview;
  final int unreadCount;
  final DateTime? lastActivity;
  final bool encrypted;
}

class MessagingMessage {
  const MessagingMessage({
    required this.id,
    required this.senderId,
    required this.body,
    required this.timestamp,
    this.encrypted = false,
    this.edited = false,
    this.reactions = const <String, int>{},
  });

  final String id;
  final String senderId;
  final String body;
  final DateTime timestamp;
  final bool encrypted;
  final bool edited;
  final Map<String, int> reactions;
}

/// Native timeline operations shared by protocol adapters.
abstract interface class MessagingProvider {
  MessagingTransport get transport;

  MessagingCapabilities get capabilities;

  bool get isSignedIn;

  String? get currentUserId;

  Future<List<MessagingConversation>> loadConversations({
    bool forceRefresh = false,
  });

  Future<List<MessagingMessage>> loadMessages(
    String conversationId, {
    int limit = 50,
  });

  Future<void> sendText(String conversationId, String body);

  Future<void> markRead(String conversationId, String messageId);

  Future<void> setTyping(String conversationId, {required bool typing});

  Future<void> sendReaction(
    String conversationId,
    String messageId,
    String reaction,
  );
}

/// Optional mutation surface for providers which can modify already-sent
/// messages. Keeping this separate avoids forcing protocols without equivalent
/// semantics to advertise fake implementations.
abstract interface class MessagingMutationProvider {
  Future<void> editText(String conversationId, String messageId, String body);

  Future<void> redactMessage(
    String conversationId,
    String messageId, {
    String? reason,
  });
}
