import '../../utils/time_utils.dart';
import 'chat_user.dart';

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
  final bool edited;
  final bool deleted;
  final DateTime? deletedAt;
  final int? deletedById;

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
    this.edited = false,
    this.deleted = false,
    this.deletedAt,
    this.deletedById,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int,
      message: json['message'] as String? ?? '',
      cooked: json['cooked'] as String?,
      createdAt: TimeUtils.parseUtcTime(json['created_at'] as String?),
      chatChannelId: json['chat_channel_id'] as int,
      user: json['user'] != null
          ? ChatUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      inReplyToId: json['in_reply_to_id'] as int?,
      threadId: json['thread_id'] as int?,
      uploads: (json['uploads'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      edited: json['edited'] as bool? ?? false,
      deleted: json['deleted'] as bool? ?? false,
      deletedAt: json['deleted_at'] != null
          ? TimeUtils.parseUtcTime(json['deleted_at'] as String)
          : null,
      deletedById: json['deleted_by_id'] as int?,
    );
  }
}