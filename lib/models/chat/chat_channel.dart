import '../../utils/time_utils.dart';
import 'chat_message.dart';
import 'chat_user.dart';

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
  final String? emoji;
  final bool threadingEnabled;
  final int? retentionDays;
  final int? retentionHours;
  final String? notificationLevel;
  final List<ChatUser>? dmUsers;

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
    this.emoji,
    this.threadingEnabled = false,
    this.retentionDays,
    this.retentionHours,
    this.notificationLevel,
    this.dmUsers,
  });

  bool get canAddMembers {
    if (chatableType == 'DirectMessage' || chatableType == 'DirectMessageChannel') {
      return true;
    }
    return userCanAddMembers == true ||
        (userChatChannelMembership?['can_add_members'] as bool? ?? false) ||
        (meta?['can_add_members'] as bool? ?? false);
  }

  /// 获取 DM 频道的对方用户
  ChatUser? getDmTargetUser(int? currentUserId) {
    if (chatableType != 'DirectMessage' && chatableType != 'DirectMessageChannel') {
      return null;
    }
    // 1. 从 dmUsers 中寻找非当前用户
    if (dmUsers != null && dmUsers!.isNotEmpty) {
      for (final u in dmUsers!) {
        if (currentUserId == null || u.id != currentUserId) {
          return u;
        }
      }
    }
    // 2. 从 lastMessage 中寻找非当前用户
    if (lastMessage?.user != null &&
        (currentUserId == null || lastMessage!.user!.id != currentUserId)) {
      return lastMessage!.user;
    }
    return lastMessage?.user;
  }

  /// 格式化显示历史消息保留时长
  String get retentionDisplay {
    final days = retentionDays ??
        (meta?['retention_days'] as num?)?.toInt() ??
        (meta?['auto_delete_days'] as num?)?.toInt() ??
        (meta?['auto_archive_duration_days'] as num?)?.toInt();
    if (days != null && days > 0) return '$days 天';

    final hours = retentionHours ??
        (meta?['retention_hours'] as num?)?.toInt() ??
        (meta?['auto_delete_hours'] as num?)?.toInt() ??
        (meta?['auto_archive_duration_hours'] as num?)?.toInt();
    if (hours != null && hours > 0) return '$hours 小时';

    return '永久保留';
  }

  /// 内部工具：解析保留时长
  static (int? days, int? hours) _parseRetentionValues(Map<String, dynamic> json) {
    int? parsedDays;
    int? parsedHours;

    void parseValue(dynamic val, {bool defaultIsHours = false}) {
      if (val == null || parsedDays != null || parsedHours != null) return;
      if (val is num) {
        final n = val.toInt();
        if (n > 0) {
          if (defaultIsHours) {
            parsedHours = n;
          } else {
            parsedDays = n;
          }
        }
      } else if (val is String) {
        final str = val.trim().toLowerCase();
        if (str == 'never' || str == 'none' || str == '0' || str.isEmpty) return;
        final match = RegExp(r'^(\d+)_?(day|days|hour|hours|year|years)?$').firstMatch(str);
        if (match != null) {
          final numVal = int.tryParse(match.group(1) ?? '');
          final unit = match.group(2);
          if (numVal != null && numVal > 0) {
            if (unit == 'hour' || unit == 'hours' || defaultIsHours) {
              parsedHours = numVal;
            } else if (unit == 'year' || unit == 'years') {
              parsedDays = numVal * 365;
            } else {
              parsedDays = numVal;
            }
          }
        } else {
          final n = int.tryParse(str);
          if (n != null && n > 0) {
            if (defaultIsHours) {
              parsedHours = n;
            } else {
              parsedDays = n;
            }
          }
        }
      }
    }

    final metaObj = json['meta'] is Map ? Map<String, dynamic>.from(json['meta'] as Map) : null;
    final chatableObj = json['chatable'] is Map ? Map<String, dynamic>.from(json['chatable'] as Map) : null;

    // 天数解析
    parseValue(json['retention_days']);
    parseValue(metaObj?['retention_days']);
    parseValue(chatableObj?['retention_days']);
    parseValue(json['auto_delete_days']);
    parseValue(metaObj?['auto_delete_days']);
    parseValue(json['auto_archive_duration_days']);
    parseValue(metaObj?['auto_archive_duration_days']);

    // 字符串偏好设置解析 (e.g. "90_days", "24_hours")
    parseValue(json['auto_delete_preference']);
    parseValue(metaObj?['auto_delete_preference']);
    parseValue(chatableObj?['auto_delete_preference']);

    // 小时数解析
    parseValue(json['retention_hours'], defaultIsHours: true);
    parseValue(metaObj?['retention_hours'], defaultIsHours: true);
    parseValue(chatableObj?['retention_hours'], defaultIsHours: true);
    parseValue(json['auto_delete_hours'], defaultIsHours: true);
    parseValue(metaObj?['auto_delete_hours'], defaultIsHours: true);
    parseValue(json['auto_archive_duration_hours'], defaultIsHours: true);
    return (parsedDays, parsedHours);
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

    final emojiVal = json['emoji']?.toString() ??
        json['icon']?.toString() ??
        (json['meta'] is Map ? (json['meta']['emoji']?.toString()) : null);

    final threading = (json['threading_enabled'] as bool?) ??
        (json['allow_threading'] as bool?) ??
        (json['meta'] is Map ? (json['meta']['threading_enabled'] as bool?) : null) ??
        false;

    final notifLevel = (membership?['notification_level'] as String?) ??
        (json['notification_level'] as String?);

    final (rDays, rHours) = _parseRetentionValues(json);

    List<ChatUser>? parsedDmUsers;
    final chatableObj = json['chatable'] is Map ? json['chatable'] as Map : null;
    final usersList = json['users'] ??
        json['target_users'] ??
        json['members'] ??
        (chatableObj?['users'] ?? chatableObj?['members'] ?? chatableObj?['target_users']);
    if (usersList is List) {
      parsedDmUsers = usersList
          .whereType<Map>()
          .map((u) => ChatUser.fromJson(Map<String, dynamic>.from(u)))
          .toList();
    }

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
      emoji: emojiVal,
      threadingEnabled: threading,
      retentionDays: rDays,
      retentionHours: rHours,
      notificationLevel: notifLevel,
      dmUsers: parsedDmUsers,
    );
  }
}