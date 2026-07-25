import '../../utils/time_utils.dart';
import 'chat_user.dart';

/// Chat 消息的回应（Reaction）数据模型
class ChatMessageReaction {
  final String emoji;
  final int count;
  final bool reacted;
  final List<ChatUser>? users;

  const ChatMessageReaction({
    required this.emoji,
    required this.count,
    this.reacted = false,
    this.users,
  });

  factory ChatMessageReaction.fromJson(Map<String, dynamic> json) {
    return ChatMessageReaction(
      emoji: json['emoji']?.toString() ?? json['id']?.toString() ?? '',
      count: (json['count'] as num?)?.toInt() ?? 1,
      reacted: json['reacted'] as bool? ?? json['user_reacted'] as bool? ?? false,
      users: (json['users'] as List?)
          ?.map((e) => ChatUser.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'emoji': emoji,
        'count': count,
        'reacted': reacted,
        if (users != null) 'users': users!.map((u) => u.toJson()).toList(),
      };
}

/// Chat 消息数据模型
class ChatMessage {
  final int id;
  final String message;
  final String? cooked;
  final DateTime createdAt;
  final int chatChannelId;
  final ChatUser? user;
  final int? inReplyToId;
  final int? threadId;
  final List<Map<String, dynamic>>? uploads;
  final List<ChatMessageReaction>? reactions;
  final bool edited;
  final bool deleted;
  final DateTime? deletedAt;
  final int? deletedById;
  final bool bookmarked;

  const ChatMessage({
    required this.id,
    required this.message,
    this.cooked,
    required this.createdAt,
    required this.chatChannelId,
    this.user,
    this.inReplyToId,
    this.threadId,
    this.uploads,
    this.reactions,
    this.edited = false,
    this.deleted = false,
    this.deletedAt,
    this.deletedById,
    this.bookmarked = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      message: json['message']?.toString() ?? '',
      cooked: json['cooked']?.toString(),
      createdAt: TimeUtils.parseUtcTime(json['created_at']?.toString()) ?? DateTime.now(),
      chatChannelId: (json['chat_channel_id'] as num?)?.toInt() ?? 0,
      user: json['user'] is Map
          ? ChatUser.fromJson(Map<String, dynamic>.from(json['user'] as Map))
          : null,
      inReplyToId: (json['in_reply_to_id'] as num?)?.toInt(),
      threadId: (json['thread_id'] as num?)?.toInt(),
      uploads: (json['uploads'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      reactions: (json['reactions'] as List?)
          ?.map((e) => ChatMessageReaction.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      edited: json['edited'] as bool? ?? false,
      deleted: json['deleted'] as bool? ?? false,
      deletedAt: json['deleted_at'] != null
          ? TimeUtils.parseUtcTime(json['deleted_at']?.toString())
          : null,
      deletedById: (json['deleted_by_id'] as num?)?.toInt(),
      bookmarked: (json['bookmarked'] as bool?) ?? (json['bookmark'] != null),
    );
  }

  ChatMessage copyWith({
    int? id,
    String? message,
    String? cooked,
    DateTime? createdAt,
    int? chatChannelId,
    ChatUser? user,
    int? inReplyToId,
    int? threadId,
    List<Map<String, dynamic>>? uploads,
    List<ChatMessageReaction>? reactions,
    bool? edited,
    bool? deleted,
    DateTime? deletedAt,
    int? deletedById,
    bool? bookmarked,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      message: message ?? this.message,
      cooked: cooked ?? this.cooked,
      createdAt: createdAt ?? this.createdAt,
      chatChannelId: chatChannelId ?? this.chatChannelId,
      user: user ?? this.user,
      inReplyToId: inReplyToId ?? this.inReplyToId,
      threadId: threadId ?? this.threadId,
      uploads: uploads ?? this.uploads,
      reactions: reactions ?? this.reactions,
      edited: edited ?? this.edited,
      deleted: deleted ?? this.deleted,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedById: deletedById ?? this.deletedById,
      bookmarked: bookmarked ?? this.bookmarked,
    );
  }
}