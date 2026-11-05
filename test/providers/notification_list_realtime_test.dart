import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/notification.dart';
import 'package:fluxdo/models/notification_category.dart';
import 'package:fluxdo/providers/notification_list_provider.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';

Map<String, dynamic> _notification(
  int id,
  NotificationType type, {
  bool read = false,
}) => {
  'id': id,
  'user_id': 1,
  'notification_type': type.id,
  'read': read,
  'created_at': '2026-11-05T00:00:00.000Z',
  'data': <String, dynamic>{},
};

Map<String, dynamic> _response(
  List<Map<String, dynamic>> items, {
  int total = 0,
}) => {
  'notifications': items,
  'total_rows_notifications': total,
  'seen_notification_id': 0,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('live push updates history without resetting pagination or duplicating rows', () async {
    final service = DiscourseService();
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(
            requestOptions: options,
            data: _response([
              _notification(10, NotificationType.replied),
            ], total: 120),
          ),
        );
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
    expect(notifier.historyOffset, 60);

    final pushed = DiscourseNotification.fromJson(
      _notification(11, NotificationType.mentioned),
    );
    notifier.applyRealtimeUpdate(latest: pushed);
    notifier.applyRealtimeUpdate(latest: pushed);
    expect(container.read(notificationListProvider).value!.map((n) => n.id), [
      11,
      10,
    ]);
    expect(notifier.historyOffset, 0);

    notifier.applyRealtimeUpdate(readStatuses: {11: true});
    expect(container.read(notificationListProvider).value!.first.read, isTrue);

    // A duplicated stale event must not resurrect an already-read row.
    notifier.applyRealtimeUpdate(latest: pushed);
    expect(container.read(notificationListProvider).value!.first.read, isTrue);
  });

  test('remote read invalidates unread cursor instead of skipping history', () async {
    final service = DiscourseService();
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(
            requestOptions: options,
            data: _response([
              _notification(50, NotificationType.mentioned),
            ], total: 240),
          ),
        );
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
    await notifier.setFilter(NotificationReadFilter.unread);

    expect(notifier.historyOffset, 60);
    notifier.applyRealtimeUpdate(readStatuses: {50: true});
    expect(container.read(notificationListProvider).value, isEmpty);
    expect(notifier.historyOffset, 0);
    expect(notifier.hasMore, isTrue);
  });

  test('silent reconciliation includes unseen rows without losing scroll history', () async {
    final service = DiscourseService();
    var requests = 0;
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        requests++;
        handler.resolve(
          Response(
            requestOptions: options,
            data: _response(
              requests == 1
                  ? [_notification(10, NotificationType.replied)]
                  : [
                      _notification(13, NotificationType.mentioned),
                      _notification(12, NotificationType.replied),
                      _notification(10, NotificationType.replied),
                    ],
              total: requests == 1 ? 180 : 182,
            ),
          ),
        );
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
    notifier.scheduleRealtimeSync();

    await Future<void>.delayed(const Duration(milliseconds: 750));
    expect(container.read(notificationListProvider).value!.map((n) => n.id),
        [13, 12, 10]);
    // The recent additions are already within the new first page.
    expect(notifier.historyOffset, 60);
    expect(notifier.hasMore, isTrue);
  });

  test(
    'unread category respects type and removes notifications marked read',
    () async {
      final service = DiscourseService();
      final interceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: _response([
                _notification(20, NotificationType.mentioned),
              ], total: 1),
            ),
          );
        },
      );
      service.dio.interceptors.insert(0, interceptor);
      addTearDown(() => service.dio.interceptors.remove(interceptor));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final subscription = container.listen(
        notificationListProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.read(notificationListProvider.future);

      final notifier = container.read(notificationListProvider.notifier);
      await notifier.setCategory(NotificationCategory.mentions);
      await notifier.setFilter(NotificationReadFilter.unread);

      notifier.applyRealtimeUpdate(
        latest: DiscourseNotification.fromJson(
          _notification(21, NotificationType.replied),
        ),
      );
      expect(container.read(notificationListProvider).value!.map((n) => n.id), [
        20,
      ]);

      notifier.applyRealtimeUpdate(
        latest: DiscourseNotification.fromJson(
          _notification(22, NotificationType.mentioned),
        ),
      );
      expect(container.read(notificationListProvider).value!.map((n) => n.id), [
        22,
        20,
      ]);

      notifier.applyRealtimeUpdate(readStatuses: {22: true});
      expect(container.read(notificationListProvider).value!.map((n) => n.id), [
        20,
      ]);
    },
  );
}
