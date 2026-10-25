import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/notification.dart';
import 'package:fluxdo/models/notification_category.dart';

DiscourseNotification notificationOf(NotificationType type, {int id = 1}) {
  return DiscourseNotification.fromJson({
    'id': id,
    'user_id': 1,
    'notification_type': type.id,
    'read': false,
    'created_at': '2026-08-31T00:00:00.000Z',
    'data': <String, dynamic>{},
  });
}

void main() {
  test('notification tabs use the updated Discourse user-menu order', () {
    expect(NotificationCategory.values, [
      NotificationCategory.all,
      NotificationCategory.replies,
      NotificationCategory.mentions,
      NotificationCategory.likes,
      NotificationCategory.messages,
      NotificationCategory.bookmarks,
      NotificationCategory.assigned,
      NotificationCategory.chat,
      NotificationCategory.other,
    ]);
  });

  test('assigned tab maps to the native assigned notification type', () {
    expect(NotificationCategory.assigned.serverFilterTypeNames, ['assigned']);
    expect(
      NotificationCategory.assigned.matches(
        notificationOf(NotificationType.assignedTopic),
      ),
      isTrue,
    );
    expect(
      NotificationCategory.other.matches(
        notificationOf(NotificationType.assignedTopic),
      ),
      isFalse,
    );
  });

  test('chat tab follows the official Discourse chat type grouping', () {
    expect(NotificationCategory.chat.serverFilterTypeNames, [
      'chat_mention',
      'chat_message',
      'chat_invitation',
      'chat_quoted',
      'chat_watched_thread',
    ]);
    for (final type in [
      NotificationType.chatMention,
      NotificationType.chatMessage,
      NotificationType.chatInvitation,
      NotificationType.chatQuotedPost,
      NotificationType.chatWatchedThread,
    ]) {
      expect(NotificationCategory.chat.matches(notificationOf(type)), isTrue);
      expect(NotificationCategory.other.matches(notificationOf(type)), isFalse);
      expect(
        NotificationCategory.mentions.matches(notificationOf(type)),
        isFalse,
      );
    }
    // Legacy chat_group_mention is obsolete upstream, not in their chat tab.
    expect(
      NotificationCategory.chat.matches(
        notificationOf(NotificationType.chatGroupMention),
      ),
      isFalse,
    );
  });

  test('mentions uses exactly the Discourse mentioned server filter', () {
    expect(NotificationCategory.mentions.serverFilterTypeNames, ['mentioned']);
    expect(
      NotificationCategory.mentions.matches(
        notificationOf(NotificationType.mentioned),
      ),
      isTrue,
    );
    for (final type in [
      NotificationType.groupMentioned,
      NotificationType.replied,
      NotificationType.quoted,
      NotificationType.chatMention,
    ]) {
      expect(
        NotificationCategory.mentions.matches(notificationOf(type)),
        isFalse,
        reason: '$type should not leak into the mentioned-only tab',
      );
    }
    // Mentions and replies are separate (the former combined tab is gone).
    expect(
      NotificationCategory.replies.matches(
        notificationOf(NotificationType.mentioned),
      ),
      isFalse,
    );
  });

  test('replies excludes mentions and matches reply-type notifications', () {
    expect(NotificationCategory.replies.serverFilterTypeNames, [
      'posted',
      'quoted',
      'replied',
    ]);
    for (final type in [
      NotificationType.posted,
      NotificationType.quoted,
      NotificationType.replied,
    ]) {
      expect(
        NotificationCategory.replies.matches(notificationOf(type)),
        isTrue,
        reason: '$type must be in replies',
      );
      expect(
        NotificationCategory.mentions.matches(notificationOf(type)),
        isFalse,
      );
    }
    for (final type in [
      NotificationType.mentioned,
      NotificationType.groupMentioned,
      NotificationType.chatMention,
    ]) {
      expect(
        NotificationCategory.replies.matches(notificationOf(type)),
        isFalse,
        reason: '$type is not a reply',
      );
    }
  });

  test('likes matches liked, consolidated likes and reactions', () {
    for (final type in [
      NotificationType.liked,
      NotificationType.likedConsolidated,
      NotificationType.reaction,
    ]) {
      expect(NotificationCategory.likes.matches(notificationOf(type)), isTrue);
    }
  });

  test('messages and bookmarks match the upstream groups', () {
    expect(
      NotificationCategory.messages.matches(
        notificationOf(NotificationType.privateMessage),
      ),
      isTrue,
    );
    expect(
      NotificationCategory.messages.matches(
        notificationOf(NotificationType.groupMessageSummary),
      ),
      isTrue,
    );
    expect(
      NotificationCategory.bookmarks.matches(
        notificationOf(NotificationType.bookmarkReminder),
      ),
      isTrue,
    );
  });

  test('other excludes all explicitly grouped notification types', () {
    expect(
      NotificationCategory.other.matches(
        notificationOf(NotificationType.grantedBadge),
      ),
      isTrue,
    );
    expect(
      NotificationCategory.other.matches(
        notificationOf(NotificationType.replied),
      ),
      isFalse,
    );
    expect(
      NotificationCategory.other.matches(
        notificationOf(NotificationType.mentioned),
      ),
      isFalse,
    );
    // Group mentions are still accessible through Other rather than lost.
    expect(
      NotificationCategory.other.matches(
        notificationOf(NotificationType.groupMentioned),
      ),
      isTrue,
    );
  });

  test('accepted solution remains custom and appears in Other', () {
    final solved = DiscourseNotification.fromJson({
      'id': 99,
      'user_id': 1,
      'notification_type': NotificationType.custom.id,
      'read': false,
      'created_at': '2026-08-31T00:00:00.000Z',
      'topic_id': 42,
      'post_number': 7,
      'data': {
        'message': 'solved.accepted_notification',
        'title': 'solved.notification.title',
      },
    });

    expect(solved.isAcceptedSolutionNotification, isTrue);
    expect(NotificationCategory.other.matches(solved), isTrue);
    expect(solved.postNumber, 7);
  });
}
