import 'notification.dart';

/// Notification groupings used by Discourse's user menu.
///
/// Replies / likes / messages are fetched with Discourse's native
/// `recent=true&filter_by_types=...` user-menu API. Bookmarks are a special
/// case in Discourse: that tab contains real bookmark records as well as
/// bookmark-reminder notifications, so the full notifications page routes it
/// to FluxDO's dedicated bookmarks page instead of pretending reminders are
/// the bookmark list.
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

  /// Discourse notification type names accepted by `filter_by_types`.
  ///
  /// `other` intentionally returns null. Discourse builds that group from the
  /// site's dynamic notification-type registry (including plugins), which the
  /// historical notifications payload does not expose. For that tab FluxDO
  /// fetches one bounded recent page and applies [matches] locally; importantly
  /// it never walks the historical pagination to fill the category.
  List<String>? get serverFilterTypeNames => switch (this) {
    NotificationCategory.all => null,
    NotificationCategory.replies => const [
      'mentioned',
      'group_mentioned',
      'posted',
      'quoted',
      'replied',
    ],
    NotificationCategory.likes => const [
      'liked',
      'liked_consolidated',
      'reaction',
    ],
    NotificationCategory.messages => const [
      'private_message',
      'group_message_summary',
    ],
    NotificationCategory.bookmarks => const ['bookmark_reminder'],
    NotificationCategory.other => null,
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
