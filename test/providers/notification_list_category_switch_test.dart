import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/notification.dart';
import 'package:fluxdo/models/notification_category.dart';
import 'package:fluxdo/providers/notification_list_provider.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';

Map<String, dynamic> _response(int id, NotificationType type) => {
  'notifications': [
    {
      'id': id,
      'user_id': 1,
      'notification_type': type.id,
      'read': false,
      'created_at': '2026-10-24T00:00:00.000Z',
      'data': <String, dynamic>{},
    },
  ],
  'total_rows_notifications': 1,
  'seen_notification_id': 0,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an older mentions response never overwrites the replies tab', () async {
    final service = DiscourseService();
    final mentionsRequested = Completer<void>();
    final repliesRequested = Completer<void>();
    final mentionsResponse = Completer<Map<String, dynamic>>();
    final repliesResponse = Completer<Map<String, dynamic>>();

    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        final types = options.queryParameters['filter_by_types'];
        if (types == 'mentioned') {
          if (!mentionsRequested.isCompleted) mentionsRequested.complete();
          mentionsResponse.future.then((data) {
            handler.resolve(Response(requestOptions: options, data: data));
          });
        } else if (types == 'posted,quoted,replied') {
          if (!repliesRequested.isCompleted) repliesRequested.complete();
          repliesResponse.future.then((data) {
            handler.resolve(Response(requestOptions: options, data: data));
          });
        } else {
          handler.resolve(
            Response(
              requestOptions: options,
              data: _response(100, NotificationType.replied),
            ),
          );
        }
      },
    );
    service.dio.interceptors.insert(0, interceptor);
    addTearDown(() => service.dio.interceptors.remove(interceptor));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(notificationListProvider, (_, _) {});
    addTearDown(subscription.close);

    await container.read(notificationListProvider.future);
    final notifier = container.read(notificationListProvider.notifier);

    final first = notifier.setCategory(NotificationCategory.mentions);
    await mentionsRequested.future;
    final second = notifier.setCategory(NotificationCategory.replies);
    await repliesRequested.future;

    repliesResponse.complete(_response(2, NotificationType.replied));
    await second;
    mentionsResponse.complete(_response(1, NotificationType.mentioned));
    await first;

    expect(notifier.category, NotificationCategory.replies);
    expect(container.read(notificationListProvider).value?.single.id, 2);
    expect(notifier.hasMore, isFalse);
  });
}
