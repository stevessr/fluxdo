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
  final bool starred;
  final bool following;
  final Map<String, dynamic>? userChatChannelMembership;
  final bool? userCanAddMembers;

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
    this.starred = false,
    this.following = false,
    this.userChatChannelMembership,
    this.userCanAddMembers,
  });

  bool get canAddMembers {
    if (chatableType == 'DirectMessage' || chatableType == 'DirectMessageChannel') {
      return true;
    }
    return userCanAddMembers == true ||
        (userChatChannelMembership?['can_add_members'] as bool? ?? false) ||
        (meta?['can_add_members'] as bool? ?? false);
  }

  factory ChatChannel.fromJson(Map<String, dynamic> json) {
    final membership = json['user_chat_channel_membership'] is Map
        ? Map<String, dynamic>.from(json['user_chat_channel_membership'] as Map)
        : (json['current_user_membership'] is Map
            ? Map<String, dynamic>.from(json['current_user_membership'] as Map)
            : null);

    final isStarred = (json['starred'] as bool?) ??
        (membership?['starred'] as bool?) ??
        false;
    final isFollowing = (json['following'] as bool?) ??
        (membership?['following'] as bool?) ??
        (membership != null ? (membership['following'] as bool? ?? true) : false);

    final canAdd = (json['allow_user_add'] as bool?) ??
        (json['user_can_add_members'] as bool?) ??
        (json['can_modify_members'] as bool?);

    return ChatChannel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString(),
      slug: json['slug']?.toString(),
      chatableType: json['chatable_type']?.toString(),
      chatableId: (json['chatable_id'] as num?)?.toInt(),
      chatableUrl: json['chatable_url']?.toString(),
      description: json['description']?.toString(),
      lastMessageSentAt: json['last_message_sent_at'] != null
          ? TimeUtils.parseUtcTime(json['last_message_sent_at']?.toString())
          : null,
      lastMessage: json['last_message'] is Map
          ? ChatMessage.fromJson(
              Map<String, dynamic>.from(json['last_message'] as Map))
          : null,
      lastReadMessageId: (json['last_read_message_id'] as num?)?.toInt(),
      membersCount: (json['members_count'] as num?)?.toInt(),
      muted: (json['muted'] as bool?) ?? (membership?['muted'] as bool?) ?? false,
      mutedUntil: json['muted_until'] != null
          ? TimeUtils.parseUtcTime(json['muted_until']?.toString())
          : null,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      unreadMentions: (json['unread_mentions'] as num?)?.toInt() ?? 0,
      meta: json['meta'] is Map
          ? Map<String, dynamic>.from(json['meta'] as Map)
          : null,
      starred: isStarred,
      following: isFollowing,
      userChatChannelMembership: membership,
      userCanAddMembers: canAdd,
    );
  }
}