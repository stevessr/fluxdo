import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/notification.dart';

void main() {
  group('discourse-solved 通知', () {
    Map<String, dynamic> notificationJson({
      required int id,
      required dynamic data,
    }) {
      return {
        'id': id,
        'user_id': 1,
        'notification_type': 14,
        'read': false,
        'high_priority': true,
        'created_at': '2026-08-31T00:00:00.000Z',
        'topic_id': 42,
        'post_number': id,
        'data': data,
      };
    }

    test('从 JSON string payload 识别 accepted solution', () {
      final notification = DiscourseNotification.fromJson(
        notificationJson(
          id: 2,
          data:
              '{"message":"solved.accepted_notification","display_username":"alice","topic_title":"topic","title":"solved.notification.title"}',
        ),
      );

      expect(notification.notificationType, NotificationType.custom);
      expect(notification.data.message, 'solved.accepted_notification');
      expect(notification.data.titleKey, 'solved.notification.title');
      expect(notification.isAcceptedSolutionNotification, isTrue);
    });

    test('多条 solution 通知分别保留 solved 语义', () {
      final response = NotificationListResponse.fromJson({
        'notifications': [
          notificationJson(
            id: 2,
            data: {
              'message': 'solved.accepted_notification',
              'display_username': 'alice',
              'topic_title': 'topic A',
              'title': 'solved.notification.title',
            },
          ),
          notificationJson(
            id: 3,
            data: {
              'message': 'solved.accepted_notification',
              'display_username': 'bob',
              'topic_title': 'topic B',
              'title': 'solved.notification.title',
            },
          ),
        ],
        'total_rows_notifications': 2,
        'seen_notification_id': 0,
      });

      expect(response.notifications, hasLength(2));
      expect(
        response.notifications.every((n) => n.isAcceptedSolutionNotification),
        isTrue,
      );
      expect(response.notifications.map((n) => n.id), [2, 3]);
    });

    test('普通 custom 通知仍保留 custom 语义', () {
      final notification = DiscourseNotification.fromJson(
        notificationJson(
          id: 4,
          data: {
            'message': 'some_plugin.event',
            'title': 'some_plugin.notification.title',
          },
        ),
      );

      expect(notification.notificationType, NotificationType.custom);
      expect(notification.isAcceptedSolutionNotification, isFalse);
    });
  });
}
