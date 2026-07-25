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

  /// Discourse 书签 ID（删除书签时需要）
  final int? bookmarkId;

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
    this.bookmarkId,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    // Discourse message serializer 在有书签时返回 bookmark 对象（含 id）
    final bookmarkObj =
        json['bookmark'] is Map ? Map<String, dynamic>.from(json['bookmark'] as Map) : null;
    final parsedBookmarkId = (bookmarkObj?['id'] as num?)?.toInt() ??
        (json['bookmark_id'] as num?)?.toInt();

    return ChatMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      message: json['message']?.toString() ?? '',
      cooked: json['cooked']?.toString(),
      createdAt: TimeUtils.parseUtcTime(json['created_at']?.toString()) ?? DateTime.now(),
      chatChannelId: (json['chat_channel_id'] as num?)?.toInt() ?? 0,
      user: json['user'] is Map
          ? ChatUser.fromJson(Map<String, dynamic>.from(json['user'] as Map))
          : null,
      // Discourse 序列化的是嵌套 in_reply_to 对象，不一定带顶层 in_reply_to_id
      inReplyToId: (json['in_reply_to_id'] as num?)?.toInt() ??
          (json['in_reply_to'] is Map
              ? (json['in_reply_to']['id'] as num?)?.toInt()
              : null),
      threadId: (json['thread_id'] as num?)?.toInt(),
      uploads: (json['uploads'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      reactions: (json['reactions'] as List?)
          ?.map((e) => ChatMessageReaction.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      edited: json['edited'] as bool? ?? false,
      // Discourse 用 deleted_at 表示删除，没有单独的 deleted 布尔字段
      deleted: json['deleted'] as bool? ?? json['deleted_at'] != null,
      deletedAt: json['deleted_at'] != null
          ? TimeUtils.parseUtcTime(json['deleted_at']?.toString())
          : null,
      deletedById: (json['deleted_by_id'] as num?)?.toInt(),
      bookmarked: (json['bookmarked'] as bool?) ??
          (bookmarkObj != null || parsedBookmarkId != null),
      bookmarkId: parsedBookmarkId,
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
    int? bookmarkId,
    bool clearBookmarkId = false,
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
      bookmarkId: clearBookmarkId ? null : (bookmarkId ?? this.bookmarkId),
    );
  }
}