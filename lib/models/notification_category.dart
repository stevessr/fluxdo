import 'notification.dart';

/// Notification groupings exposed by the Discourse user menu.
///
/// Keep the type registry here rather than scattering numeric notification
/// ids through widgets. Non-`all` groups use Discourse's bounded
/// `recent=true&filter_by_types=...` API because the historical notifications
/// endpoint does not consistently apply type filters.
enum NotificationCategory {
  all,
  responses,
  likes,
  mentions,
  edits,
  links,
  messages,
  bookmarks,
  other;

  static const Set<NotificationType> _responseTypes = {
    NotificationType.replied,
    NotificationType.quoted,
  };

  static const Set<NotificationType> _likeTypes = {
    NotificationType.liked,
    NotificationType.likedConsolidated,
    NotificationType.reaction,
  };

  static const Set<NotificationType> _mentionTypes = {
    NotificationType.mentioned,
    NotificationType.groupMentioned,
  };

  static const Set<NotificationType> _editTypes = {
    NotificationType.edited,
  };

  static const Set<NotificationType> _linkTypes = {
    NotificationType.linked,
    NotificationType.linkedConsolidated,
  };

  static const Set<NotificationType> _messageTypes = {
    NotificationType.privateMessage,
    NotificationType.groupMessageSummary,
  };

  static const Set<NotificationType> _bookmarkTypes = {
    NotificationType.bookmarkReminder,
  };

  static const Set<NotificationType> _classifiedTypes = {
    ..._responseTypes,
    ..._likeTypes,
    ..._mentionTypes,
    ..._editTypes,
    ..._linkTypes,
    ..._messageTypes,
    ..._bookmarkTypes,
  };

  /// Discourse notification type names accepted by `filter_by_types`.
  ///
  /// `other` intentionally returns null. Plugins can add notification types at
  /// runtime, so that category fetches one bounded recent page and applies the
  /// complement locally rather than pretending the client has a complete
  /// server type registry.
  List<String>? get serverFilterTypeNames => switch (this) {
    NotificationCategory.all => null,
    NotificationCategory.responses => const ['replied', 'quoted'],
    NotificationCategory.likes => const [
      'liked',
      'liked_consolidated',
      'reaction',
    ],
    NotificationCategory.mentions => const ['mentioned', 'group_mentioned'],
    NotificationCategory.edits => const ['edited'],
    NotificationCategory.links => const ['linked', 'linked_consolidated'],
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
      NotificationCategory.responses => _responseTypes.contains(type),
      NotificationCategory.likes => _likeTypes.contains(type),
      NotificationCategory.mentions => _mentionTypes.contains(type),
      NotificationCategory.edits => _editTypes.contains(type),
      NotificationCategory.links => _linkTypes.contains(type),
      NotificationCategory.messages => _messageTypes.contains(type),
      NotificationCategory.bookmarks => _bookmarkTypes.contains(type),
      NotificationCategory.other => !_classifiedTypes.contains(type),
    };
  }
}
