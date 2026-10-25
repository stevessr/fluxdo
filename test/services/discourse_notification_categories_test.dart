import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/notification_category.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'mention and reply tabs send separate silent Discourse filters',
    () async {
      final service = DiscourseService();
      final requests = <RequestOptions>[];
      final interceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'notifications': <Map<String, dynamic>>[],
                'total_rows_notifications': 0,
                'seen_notification_id': 0,
              },
            ),
          );
        },
      );
      service.dio.interceptors.insert(0, interceptor);
      addTearDown(() => service.dio.interceptors.remove(interceptor));

      const expectedTypes = <NotificationCategory, String>{
        NotificationCategory.replies: 'posted,quoted,replied',
        NotificationCategory.mentions: 'mentioned',
        NotificationCategory.assigned: 'assigned',
        NotificationCategory.chat:
            'chat_mention,chat_message,chat_invitation,'
            'chat_quoted,chat_watched_thread',
      };

      for (final entry in expectedTypes.entries) {
        final response = await service.getRecentNotifications(
          filterByTypes: entry.key.serverFilterTypeNames,
          limit: 60,
          silent: true,
          bumpLastSeenReviewable: false,
        );
        expect(response.notifications, isEmpty);

        final request = requests.last;
        expect(request.method, 'GET');
        expect(request.uri.path, endsWith('/notifications'));
        expect(request.queryParameters['recent'], true);
        expect(request.queryParameters['limit'], 60);
        expect(request.queryParameters['filter_by_types'], entry.value);
        expect(request.queryParameters['silent'], true);
        expect(
          request.queryParameters.containsKey('bump_last_seen_reviewable'),
          isFalse,
        );
        expect(request.queryParameters.containsKey('filter'), isFalse);
      }
      expect(requests, hasLength(expectedTypes.length));
    },
  );
}
