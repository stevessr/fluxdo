import 'notification.dart';

/// Notification groupings used by Discourse's user menu.
///
/// The historical `/notifications` endpoint cannot filter by type, so FluxDO
/// keeps the server-side read/unread filter and applies these semantic groups
/// locally while continuing to paginate through history.
enum NotificationCategory {
  all,
  replies,
  likes,
  messages,
  bookmarks,
  other;

  static const Set<NotificationType> _replyTypes = {
    NotificationType.mentioned,
    NotificationType.groupMentioned,
    NotificationType.posted,
    NotificationType.quoted,
    NotificationType.replied,
  };

  static const Set<NotificationType> _likeTypes = {
    NotificationType.liked,
    NotificationType.likedConsolidated,
    NotificationType.reaction,
  };

  static const Set<NotificationType> _messageTypes = {
    NotificationType.privateMessage,
    NotificationType.groupMessageSummary,
  };

  static const Set<NotificationType> _bookmarkTypes = {
    NotificationType.bookmarkReminder,
  };

  bool matches(DiscourseNotification notification) {
    final type = notification.notificationType;
    return switch (this) {
      NotificationCategory.all => true,
      NotificationCategory.replies => _replyTypes.contains(type),
      NotificationCategory.likes => _likeTypes.contains(type),
      NotificationCategory.messages => _messageTypes.contains(type),
      NotificationCategory.bookmarks => _bookmarkTypes.contains(type),
      NotificationCategory.other =>
        !_replyTypes.contains(type) &&
            !_likeTypes.contains(type) &&
            !_messageTypes.contains(type) &&
            !_bookmarkTypes.contains(type),
    };
  }
}
