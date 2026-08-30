import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/notification.dart';

void main() {
  group('discourse-solved 通知', () {
    Map<String, dynamic> notificationJson({
      required int id,
      required dynamic data,
      int? postNumber,
    }) {
      return {
        'id': id,
        'user_id': 1,
        'notification_type': 14,
        'read': false,
        'high_priority': true,
        'created_at': '2026-08-31T00:00:00.000Z',
        'topic_id': 42,
        'post_number': postNumber ?? id,
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

    test('同一主题的多条 solution 通知分别保留楼层落点', () {
      final response = NotificationListResponse.fromJson({
        'notifications': [
          notificationJson(
            id: 201,
            postNumber: 2,
            data: {
              'message': 'solved.accepted_notification',
              'display_username': 'alice',
              'topic_title': 'same topic',
              'title': 'solved.notification.title',
            },
          ),
          notificationJson(
            id: 202,
            postNumber: 9,
            data: {
              'message': 'solved.accepted_notification',
              'display_username': 'bob',
              'topic_title': 'same topic',
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
      expect(response.notifications.map((n) => n.id), [201, 202]);
      expect(response.notifications.map((n) => n.topicId), [42, 42]);
      expect(response.notifications.map((n) => n.postNumber), [2, 9]);
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
