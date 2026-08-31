import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/notification.dart';
import 'package:fluxdo/utils/notification_post_target.dart';

void main() {
  group('reactionFallbackPostId', () {
    test('consolidated reaction uses original_post_id when topic target is absent', () {
      final notification = DiscourseNotification.fromJson({
        'id': 7731,
        'user_id': 88,
        'notification_type': 25,
        'read': true,
        'high_priority': false,
        'created_at': '2026-08-31T05:00:00.000Z',
        'post_number': null,
        'topic_id': null,
        'data': {
          'original_post_id': 843,
          'display_username': 'johnny',
          'consolidated': true,
          'count': 2,
        },
      });

      expect(reactionFallbackPostId(notification), 843);
    });

    test('complete reaction target does not trigger an extra lookup', () {
      final notification = DiscourseNotification.fromJson({
        'id': 1334,
        'user_id': 88,
        'notification_type': 25,
        'read': true,
        'high_priority': false,
        'created_at': '2026-08-31T05:00:00.000Z',
        'post_number': 12,
        'topic_id': 8432,
        'data': {'original_post_id': 3349},
      });

      expect(reactionFallbackPostId(notification), isNull);
    });

    test('missing post number also falls back to original_post_id', () {
      final notification = DiscourseNotification.fromJson({
        'id': 1335,
        'user_id': 88,
        'notification_type': 25,
        'read': false,
        'high_priority': false,
        'created_at': '2026-08-31T05:00:00.000Z',
        'post_number': null,
        'topic_id': 8432,
        'data': {'original_post_id': '3349'},
      });

      expect(reactionFallbackPostId(notification), 3349);
    });
  });

  group('parseNotificationPostTarget', () {
    test('parses the topic and exact post number returned by PostSerializer', () {
      final target = parseNotificationPostTarget({
        'id': 3349,
        'topic_id': 8432,
        'post_number': 12,
      });

      expect(target, isNotNull);
      expect(target!.topicId, 8432);
      expect(target.postNumber, 12);
    });

    test('requires a topic id', () {
      expect(parseNotificationPostTarget({'post_number': 12}), isNull);
    });
  });
}
