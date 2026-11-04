import '../models/notification.dart';

/// 通知最终应打开的帖子位置。
class NotificationPostTarget {
  const NotificationPostTarget({required this.topicId, this.postNumber});

  final int topicId;
  final int? postNumber;
}

/// reaction 通知只有在顶层 topic/post 信息不完整时才需要按 post id 回查。
///
/// discourse-reactions 会把同一用户对多条帖子的 reaction 合并成一条
/// consolidated notification；这类通知的 topic_id / post_number 为 null，
/// 但 data.original_post_id 仍保留一个真实帖子 id。私信里连续 reaction
/// 很容易进入这个分支。
int? reactionFallbackPostId(DiscourseNotification notification) {
  if (notification.notificationType != NotificationType.reaction) return null;
  if (notification.topicId != null && notification.postNumber != null) {
    return null;
  }
  return int.tryParse(notification.data.originalPostId ?? '');
}

/// 从 /posts/{postId}.json 响应解析应用内导航需要的稳定位置。
NotificationPostTarget? parseNotificationPostTarget(dynamic responseData) {
  if (responseData is! Map) return null;

  final topicId = _asInt(responseData['topic_id']);
  if (topicId == null) return null;

  return NotificationPostTarget(
    topicId: topicId,
    postNumber: _asInt(responseData['post_number']),
  );
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
