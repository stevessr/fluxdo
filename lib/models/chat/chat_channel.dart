import '../../utils/time_utils.dart';
import 'chat_message.dart';

/// Chat 频道数据模型
class ChatChannel {
  final int id;
  final String? title;
  final String? slug;
  final String? chatableType;
  final int? chatableId;
  final String? chatableUrl;
  final String? description;
  final DateTime? lastMessageSentAt;
  final ChatMessage? lastMessage;
  final int? lastReadMessageId;
  final int? membersCount;
  final bool muted;
  final DateTime? mutedUntil;
  final int unreadCount;
  final int unreadMentions;
  final Map<String, dynamic>? meta;

  const ChatChannel({
    required this.id,
    this.title,
    this.slug,
    this.chatableType,
    this.chatableId,
    this.chatableUrl,
    this.description,
    this.lastMessageSentAt,
    this.lastMessage,
    this.lastReadMessageId,
    this.membersCount,
    this.muted = false,
    this.mutedUntil,
    this.unreadCount = 0,
    this.unreadMentions = 0,
    this.meta,
  });

  factory ChatChannel.fromJson(Map<String, dynamic> json) {
    return ChatChannel(
      id: json['id'] as int,
      title: json['title'] as String?,
      slug: json['slug'] as String?,
      chatableType: json['chatable_type'] as String?,
      chatableId: json['chatable_id'] as int?,
      chatableUrl: json['chatable_url'] as String?,
      description: json['description'] as String?,
      lastMessageSentAt: json['last_message_sent_at'] != null
          ? TimeUtils.parseUtcTime(json['last_message_sent_at'] as String)
          : null,
      lastMessage: json['last_message'] != null
          ? ChatMessage.fromJson(
              json['last_message'] as Map<String, dynamic>)
          : null,
      lastReadMessageId: json['last_read_message_id'] as int?,
      membersCount: json['members_count'] as int?,
      muted: json['muted'] as bool? ?? false,
      mutedUntil: json['muted_until'] != null
          ? TimeUtils.parseUtcTime(json['muted_until'] as String)
          : null,
      unreadCount: json['unread_count'] as int? ?? 0,
      unreadMentions: json['unread_mentions'] as int? ?? 0,
      meta: json['meta'] as Map<String, dynamic>?,
    );
  }
}