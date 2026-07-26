import '../../utils/time_utils.dart';
import 'chat_user.dart';

/// 消息串预览（对齐 Discourse Chat::ThreadPreviewSerializer）
class ChatThreadPreview {
  final int replyCount;
  final int? lastReplyId;
  final String? lastReplyExcerpt;
  final DateTime? lastReplyCreatedAt;
  final ChatUser? lastReplyUser;
  final int? participantCount;
  final List<ChatUser> participantUsers;

  const ChatThreadPreview({
    this.replyCount = 0,
    this.lastReplyId,
    this.lastReplyExcerpt,
    this.lastReplyCreatedAt,
    this.lastReplyUser,
    this.participantCount,
    this.participantUsers = const [],
  });

  factory ChatThreadPreview.fromJson(Map<String, dynamic> json) {
    return ChatThreadPreview(
      replyCount: (json['reply_count'] as num?)?.toInt() ?? 0,
      lastReplyId: (json['last_reply_id'] as num?)?.toInt(),
      lastReplyExcerpt: json['last_reply_excerpt']?.toString(),
      lastReplyCreatedAt:
          TimeUtils.parseUtcTime(json['last_reply_created_at']?.toString()),
      lastReplyUser: json['last_reply_user'] is Map
          ? ChatUser.fromJson(
              Map<String, dynamic>.from(json['last_reply_user'] as Map),
            )
          : null,
      participantCount: (json['participant_count'] as num?)?.toInt(),
      participantUsers: (json['participant_users'] as List?)
              ?.whereType<Map>()
              .map((e) => ChatUser.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
    );
  }
}

/// 消息串（对齐 Discourse Chat::ThreadSerializer）
class ChatThread {
  final int id;
  final String? title;
  final String? status;
  final int channelId;
  final int replyCount;
  final int? lastMessageId;
  final bool force;
  final ChatThreadPreview? preview;

  const ChatThread({
    required this.id,
    this.title,
    this.status,
    required this.channelId,
    this.replyCount = 0,
    this.lastMessageId,
    this.force = false,
    this.preview,
  });

  factory ChatThread.fromJson(Map<String, dynamic> json) {
    final previewJson = json['preview'];
    return ChatThread(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString(),
      status: json['status']?.toString(),
      channelId: (json['channel_id'] as num?)?.toInt() ?? 0,
      replyCount: (json['reply_count'] as num?)?.toInt() ??
          (previewJson is Map
              ? (previewJson['reply_count'] as num?)?.toInt()
              : null) ??
          0,
      lastMessageId: (json['last_message_id'] as num?)?.toInt(),
      force: json['force'] as bool? ?? false,
      preview: previewJson is Map
          ? ChatThreadPreview.fromJson(
              Map<String, dynamic>.from(previewJson),
            )
          : null,
    );
  }

  /// 指示器是否应显示（对齐 Discourse showThreadIndicator）
  bool get hasVisibleReplies {
    final count = preview?.replyCount ?? replyCount;
    return count > 0;
  }

  ChatThread copyWith({
    int? id,
    String? title,
    String? status,
    int? channelId,
    int? replyCount,
    int? lastMessageId,
    bool? force,
    ChatThreadPreview? preview,
  }) {
    return ChatThread(
      id: id ?? this.id,
      title: title ?? this.title,
      status: status ?? this.status,
      channelId: channelId ?? this.channelId,
      replyCount: replyCount ?? this.replyCount,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      force: force ?? this.force,
      preview: preview ?? this.preview,
    );
  }
}
