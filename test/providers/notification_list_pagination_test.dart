import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/notification.dart';
import 'package:fluxdo/models/notification_category.dart';
import 'package:fluxdo/providers/notification_list_provider.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';

Map<String, dynamic> _notification(int id, NotificationType type) => {
  'id': id,
  'user_id': 1,
  'notification_type': type.id,
  'read': false,
  'created_at': '2026-10-24T00:00:00.000Z',
  'data': <String, dynamic>{},
};

Map<String, dynamic> _response(
  List<Map<String, dynamic>> notifications, {
  int total = 0,
}) => {
  'notifications': notifications,
  'total_rows_notifications': total,
  'seen_notification_id': 0,
};

ProviderContainer _container() {
  final container = ProviderContainer();
  final subscription = container.listen(notificationListProvider, (_, _) {});
  addTearDown(subscription.close);
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'category continues into historical pages and de-duplicates recent',
    () async {
      final service = DiscourseService();
      final offsets = <int>[];
      final interceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.queryParameters['recent'] == true) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: _response([
                  _notification(300, NotificationType.mentioned),
                ]),
              ),
            );
            return;
          }
          if (!options.queryParameters.containsKey('offset')) {
            handler.resolve(
              Response(requestOptions: options, data: _response([], total: 0)),
            );
            return;
          }
          final offset = options.queryParameters['offset'] as int? ?? 0;
          offsets.add(offset);
          final items = switch (offset) {
            0 => [_notification(300, NotificationType.mentioned)],
            60 => [_notification(280, NotificationType.replied)],
            120 => [_notification(150, NotificationType.mentioned)],
            _ => <Map<String, dynamic>>[],
          };
          handler.resolve(
            Response(
              requestOptions: options,
              data: _response(items, total: 181),
            ),
          );
        },
      );
      service.dio.interceptors.insert(0, interceptor);
      addTearDown(() => service.dio.interceptors.remove(interceptor));

      final container = _container();
      await container.read(notificationListProvider.future);
      final notifier = container.read(notificationListProvider.notifier);
      await notifier.setCategory(NotificationCategory.mentions);
      expect(notifier.hasMore, isTrue);
      expect(container.read(notificationListProvider).value!.single.id, 300);

      await notifier.loadMore();
      expect(offsets, [0, 60, 120]);
      expect(container.read(notificationListProvider).value!.map((n) => n.id), [
        300,
        150,
      ]);
      expect(notifier.historyOffset, 180);
      expect(notifier.needsManualLoadMore, isFalse);

      await notifier.loadMore();
      expect(offsets, [0, 60, 120, 180]);
      expect(notifier.hasMore, isFalse);
      await notifier.loadMore();
      expect(offsets, hasLength(4));
    },
  );

  test(
    'sparse category pauses after bounded scan and resumes at cursor',
    () async {
      final service = DiscourseService();
      final offsets = <int>[];
      final interceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.queryParameters['recent'] == true) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: _response([
                  _notification(400, NotificationType.mentioned),
                ]),
              ),
            );
            return;
          }
          if (!options.queryParameters.containsKey('offset')) {
            handler.resolve(
              Response(requestOptions: options, data: _response([], total: 0)),
            );
            return;
          }
          final offset = options.queryParameters['offset'] as int? ?? 0;
          offsets.add(offset);
          handler.resolve(
            Response(
              requestOptions: options,
              data: _response(
                offset == 240
                    ? [_notification(10, NotificationType.mentioned)]
                    : [_notification(500 - offset, NotificationType.replied)],
                total: 300,
              ),
            ),
          );
        },
      );
      service.dio.interceptors.insert(0, interceptor);
      addTearDown(() => service.dio.interceptors.remove(interceptor));

      final container = _container();
      await container.read(notificationListProvider.future);
      final notifier = container.read(notificationListProvider.notifier);
      await notifier.setCategory(NotificationCategory.mentions);

      await notifier.loadMore();
      expect(offsets, [0, 60, 120, 180]);
      expect(notifier.needsManualLoadMore, isTrue);
      expect(notifier.hasMore, isTrue);
      await notifier.loadMore();
      expect(offsets, hasLength(4), reason: 'automatic retry must be bounded');

      notifier.allowMoreHistoryScan();
      await notifier.loadMore();
      expect(offsets, [0, 60, 120, 180, 240]);
      expect(container.read(notificationListProvider).value!.map((n) => n.id), [
        400,
        10,
      ]);
      expect(notifier.hasMore, isFalse);
    },
  );

  test(
    'late history response cannot overwrite a newly selected category',
    () async {
      final service = DiscourseService();
      final historyRequested = Completer<void>();
      final historyResponse = Completer<Map<String, dynamic>>();
      final interceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.queryParameters['recent'] == true) {
            final type = options.queryParameters['filter_by_types'];
            handler.resolve(
              Response(
                requestOptions: options,
                data: _response([
                  if (type == 'mentioned')
                    _notification(1, NotificationType.mentioned)
                  else
                    _notification(2, NotificationType.replied),
                ]),
              ),
            );
            return;
          }
          if (!options.queryParameters.containsKey('offset')) {
            handler.resolve(
              Response(requestOptions: options, data: _response([], total: 0)),
            );
            return;
          }
          if (!historyRequested.isCompleted) historyRequested.complete();
          historyResponse.future.then((data) {
            handler.resolve(Response(requestOptions: options, data: data));
          });
        },
      );
      service.dio.interceptors.insert(0, interceptor);
      addTearDown(() => service.dio.interceptors.remove(interceptor));

      final container = _container();
      await container.read(notificationListProvider.future);
      final notifier = container.read(notificationListProvider.notifier);
      await notifier.setCategory(NotificationCategory.mentions);

      final oldPage = notifier.loadMore();
      await historyRequested.future;
      await notifier.setCategory(NotificationCategory.replies);
      historyResponse.complete(
        _response([_notification(3, NotificationType.mentioned)], total: 60),
      );
      await oldPage;

      expect(notifier.category, NotificationCategory.replies);
      expect(container.read(notificationListProvider).value!.single.id, 2);
      expect(notifier.historyOffset, 0);
      expect(notifier.hasMore, isTrue);
    },
  );

  test('unread category scans history with server read filter', () async {
    final service = DiscourseService();
    final historyQueries = <Map<String, dynamic>>[];
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.queryParameters['recent'] == true) {
          handler.resolve(
            Response(requestOptions: options, data: _response([])),
          );
          return;
        }
        if (!options.queryParameters.containsKey('offset')) {
          handler.resolve(
            Response(requestOptions: options, data: _response([], total: 0)),
          );
          return;
        }
        historyQueries.add(options.queryParameters);
        handler.resolve(
          Response(
            requestOptions: options,
            data: _response([
              _notification(25, NotificationType.replied),
            ], total: 60),
          ),
        );
      },
    );
    service.dio.interceptors.insert(0, interceptor);
    addTearDown(() => service.dio.interceptors.remove(interceptor));

    final container = _container();
    await container.read(notificationListProvider.future);
    final notifier = container.read(notificationListProvider.notifier);
    await notifier.setCategory(NotificationCategory.replies);
    await notifier.setFilter(NotificationReadFilter.unread);
    expect(container.read(notificationListProvider).value, isEmpty);
    expect(notifier.hasMore, isTrue);

    await notifier.loadMore();
    expect(historyQueries.last['filter'], 'unread');
    expect(container.read(notificationListProvider).value!.single.id, 25);
    expect(notifier.hasMore, isFalse);
  });
  test('mark-all cancels pending unread pagination', () async {
    final service = DiscourseService();
    final requested = Completer<void>();
    final delayedHistory = Completer<Map<String, dynamic>>();
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.method == 'PUT') {
          handler.resolve(
            Response(requestOptions: options, data: <String, dynamic>{}),
          );
          return;
        }
        if (options.queryParameters['recent'] == true) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: _response([
                _notification(30, NotificationType.mentioned),
              ]),
            ),
          );
          return;
        }
        if (!options.queryParameters.containsKey('offset')) {
          handler.resolve(
            Response(requestOptions: options, data: _response([], total: 0)),
          );
          return;
        }
        if (!requested.isCompleted) requested.complete();
        delayedHistory.future.then((data) {
          handler.resolve(Response(requestOptions: options, data: data));
        });
      },
    );
    service.dio.interceptors.insert(0, interceptor);
    addTearDown(() => service.dio.interceptors.remove(interceptor));

    final container = _container();
    await container.read(notificationListProvider.future);
    final notifier = container.read(notificationListProvider.notifier);
    await notifier.setCategory(NotificationCategory.mentions);
    await notifier.setFilter(NotificationReadFilter.unread);

    final pending = notifier.loadMore();
    await requested.future;
    await notifier.markAllAsRead();

    expect(container.read(notificationListProvider).value, isEmpty);
    delayedHistory.complete(
      _response([_notification(20, NotificationType.mentioned)], total: 60),
    );
    await pending;

    expect(container.read(notificationListProvider).value, isEmpty);
    expect(notifier.hasMore, isFalse);
    expect(notifier.historyOffset, 0);
  });

  test('single read preserves state during pagination', () async {
    final service = DiscourseService();
    final requested = Completer<void>();
    final delayedHistory = Completer<Map<String, dynamic>>();
    final offsets = <int>[];
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        final offset = options.queryParameters['offset'] as int?;
        if (offset == null) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: _response([
                _notification(80, NotificationType.mentioned),
              ], total: 120),
            ),
          );
          return;
        }
        offsets.add(offset);
        if (offsets.length == 1) {
          requested.complete();
          delayedHistory.future.then((data) {
            handler.resolve(Response(requestOptions: options, data: data));
          });
        } else {
          handler.resolve(
            Response(
              requestOptions: options,
              data: _response([
                _notification(75, NotificationType.replied),
              ], total: 120),
            ),
          );
        }
      },
    );
    service.dio.interceptors.insert(0, interceptor);
    addTearDown(() => service.dio.interceptors.remove(interceptor));

    final container = _container();
    await container.read(notificationListProvider.future);
    final notifier = container.read(notificationListProvider.notifier);

    final pending = notifier.loadMore();
    await requested.future;
    notifier.markAsRead(80);
    delayedHistory.complete(
      _response([_notification(75, NotificationType.replied)], total: 120),
    );
    await pending;

    final current = container.read(notificationListProvider).value!;
    expect(current.single.id, 80);
    expect(current.single.read, isTrue);
    expect(notifier.historyOffset, 60);
    expect(notifier.hasMore, isTrue);

    await notifier.loadMore();
    expect(offsets, [60, 60]);
    expect(container.read(notificationListProvider).value!.map((n) => n.id), [
      80,
      75,
    ]);
  });
  test('mark-all while switching category finishes refresh', () async {
    final service = DiscourseService();
    final firstRecentStarted = Completer<void>();
    final firstRecent = Completer<Map<String, dynamic>>();
    var recentCalls = 0;
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.method == 'PUT') {
          handler.resolve(
            Response(requestOptions: options, data: <String, dynamic>{}),
          );
          return;
        }
        if (options.queryParameters['recent'] == true) {
          recentCalls++;
          if (recentCalls == 1) {
            firstRecentStarted.complete();
            firstRecent.future.then((data) {
              handler.resolve(Response(requestOptions: options, data: data));
            });
          } else {
            handler.resolve(
              Response(
                requestOptions: options,
                data: _response([
                  {
                    ..._notification(42, NotificationType.mentioned),
                    'read': true,
                  },
                ]),
              ),
            );
          }
          return;
        }
        handler.resolve(
          Response(requestOptions: options, data: _response([], total: 0)),
        );
      },
    );
    service.dio.interceptors.insert(0, interceptor);
    addTearDown(() => service.dio.interceptors.remove(interceptor));

    final container = _container();
    await container.read(notificationListProvider.future);
    final notifier = container.read(notificationListProvider.notifier);
    final pendingCategory = notifier.setCategory(NotificationCategory.mentions);
    await firstRecentStarted.future;
    await notifier.markAllAsRead();

    firstRecent.complete(
      _response([_notification(45, NotificationType.mentioned)]),
    );
    await pendingCategory;

    expect(recentCalls, 2);
    expect(container.read(notificationListProvider).isLoading, isFalse);
    final current = container.read(notificationListProvider).value!;
    expect(current.single.id, 42);
    expect(current.single.read, isTrue);
  });
}
