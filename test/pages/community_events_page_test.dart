import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/community_events_page.dart';

Dio _client(
  void Function(RequestOptions options, RequestInterceptorHandler handler)
  onRequest,
) {
  final dio = Dio(BaseOptions(baseUrl: 'https://linux.do'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: onRequest));
  return dio;
}

Response<dynamic> _page(
  RequestOptions request, {
  required String type,
  required List<Map<String, dynamic>> users,
  required int total,
  String? next,
}) {
  return Response<dynamic>(
    requestOptions: request,
    statusCode: 200,
    data: {type: users, 'total_rows_$type': total, 'load_more_$type': next},
  );
}

Map<String, dynamic> _user(String name) => {
  'username': name.toLowerCase(),
  'name': name,
  'cakedate': '2024-10-25',
};

void main() {
  testWidgets('两层标签复用一张页面，分类和时间分别请求正确的 API', (tester) async {
    final requests = <RequestOptions>[];
    final dio = _client((options, handler) {
      requests.add(options);
      final birthdays = options.path.contains('/birthdays/');
      final type = birthdays ? 'birthdays' : 'anniversaries';
      handler.resolve(
        _page(
          options,
          type: type,
          users: [_user(birthdays ? 'Bob' : 'Alice')],
          total: 1,
        ),
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CommunityEventsPage(
          view: CommunityEventsView.anniversaries,
          client: dio,
          initialMonth: 7,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Anniversaries'), findsOneWidget);
    expect(find.text('Birthdays'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(requests.last.path, '/cakeday/anniversaries/today');

    await tester.tap(find.text('Birthdays'));
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
    expect(requests.last.path, '/cakeday/birthdays/today');

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(requests.last.path, '/cakeday/birthdays/all');
    expect(requests.last.queryParameters['month'], 7);
    expect(find.byType(DropdownButton<int>), findsOneWidget);
  });

  testWidgets('分页失败保留已有用户，重试后不会继续显示加载更多', (tester) async {
    var failOnce = true;
    final dio = _client((options, handler) {
      final isMore = options.path.contains('page=1');
      if (isMore && failOnce) {
        failOnce = false;
        handler.reject(
          DioException(
            requestOptions: options,
            response: Response<dynamic>(
              requestOptions: options,
              statusCode: 503,
            ),
            type: DioExceptionType.badResponse,
          ),
        );
        return;
      }
      handler.resolve(
        _page(
          options,
          type: 'anniversaries',
          users: [_user(isMore ? 'Bob' : 'Alice')],
          total: 2,
          next: '/cakeday/anniversaries/today?page=1',
        ),
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CommunityEventsPage(
          view: CommunityEventsView.anniversaries,
          client: dio,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Retry loading'), findsOneWidget);

    await tester.tap(find.text('Retry loading'));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
    expect(find.text('Retry loading'), findsNothing);
  });
}
