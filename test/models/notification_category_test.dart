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
  test('responses matches only replied and quoted', () {
    for (final type in [NotificationType.replied, NotificationType.quoted]) {
      expect(
        NotificationCategory.responses.matches(notificationOf(type)),
        isTrue,
        reason: '$type must be in responses',
      );
    }
    expect(
      NotificationCategory.responses.matches(
        notificationOf(NotificationType.mentioned),
      ),
      isFalse,
    );
    expect(
      NotificationCategory.responses.matches(
        notificationOf(NotificationType.posted),
      ),
      isFalse,
    );
  });

  test('mentions matches direct and group mentions', () {
    expect(
      NotificationCategory.mentions.matches(
        notificationOf(NotificationType.mentioned),
      ),
      isTrue,
    );
    expect(
      NotificationCategory.mentions.matches(
        notificationOf(NotificationType.groupMentioned),
      ),
      isTrue,
    );
  });

  test('likes, edits and links match Discourse parity groups', () {
    for (final type in [
      NotificationType.liked,
      NotificationType.likedConsolidated,
      NotificationType.reaction,
    ]) {
      expect(NotificationCategory.likes.matches(notificationOf(type)), isTrue);
    }
    expect(
      NotificationCategory.edits.matches(
        notificationOf(NotificationType.edited),
      ),
      isTrue,
    );
    expect(
      NotificationCategory.links.matches(
        notificationOf(NotificationType.linked),
      ),
      isTrue,
    );
    expect(
      NotificationCategory.links.matches(
        notificationOf(NotificationType.linkedConsolidated),
      ),
      isTrue,
    );
  });

  test('server filters use names accepted by filter_by_types', () {
    expect(
      NotificationCategory.responses.serverFilterTypeNames,
      ['replied', 'quoted'],
    );
    expect(
      NotificationCategory.likes.serverFilterTypeNames,
      ['liked', 'liked_consolidated', 'reaction'],
    );
    expect(
      NotificationCategory.mentions.serverFilterTypeNames,
      ['mentioned', 'group_mentioned'],
    );
    expect(NotificationCategory.edits.serverFilterTypeNames, ['edited']);
    expect(
      NotificationCategory.links.serverFilterTypeNames,
      ['linked', 'linked_consolidated'],
    );
  });

  test('messages and bookmarks remain available as dedicated groups', () {
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

  test('other is the complement and keeps plugin/custom notifications', () {
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
        notificationOf(NotificationType.linkedConsolidated),
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
