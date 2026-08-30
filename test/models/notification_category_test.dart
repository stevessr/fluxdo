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
  test('replies matches Discourse replies and mentions grouping', () {
    for (final type in [
      NotificationType.mentioned,
      NotificationType.groupMentioned,
      NotificationType.posted,
      NotificationType.quoted,
      NotificationType.replied,
    ]) {
      expect(
        NotificationCategory.replies.matches(notificationOf(type)),
        isTrue,
        reason: '$type must be in replies',
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
