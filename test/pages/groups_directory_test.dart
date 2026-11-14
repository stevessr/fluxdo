import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/groups_page.dart';
import 'package:fluxdo/providers/discourse_providers.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';

void main() {
  testWidgets('群组目录展示官方卡片、成员状态和服务端类型筛选', (tester) async {
    final types = <String?>[];
    final filters = <String?>[];
    final fullBio = List.filled(8, '讨论装机配置，分享最新游戏技巧，寻找游戏伙伴。').join();
    final service = DiscourseService();
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.method != 'GET' || options.path != '/groups.json') {
          handler.reject(
            DioException(requestOptions: options, message: 'Unexpected request'),
          );
          return;
        }
        final type = options.queryParameters['type']?.toString();
        types.add(type);
        filters.add(options.queryParameters['filter']?.toString());
        final all = [
          {
            'id': 90,
            'name': 'g-adsfree',
            'full_name': '无广告组',
            'user_count': 6529,
            'public_admission': true,
            'bio_excerpt': '讨论装机配置…',
            'bio_cooked': '<p>$fullBio</p>',
          },
          {
            'id': 116,
            'name': 'g-premium',
            'full_name': 'Premium分组',
            'is_group_user': true,
            'public_exit': false,
            'flair_url': null,
          },
          {
            'id': 91,
            'name': 'g-verified-staff',
            'full_name': '机构成员组',
            'public_admission': false,
            'public_exit': false,
          },
        ];
        final selected = switch (type) {
          'my' || 'owner' => [all[1]],
          'public' => [all[0]],
          'close' => [all[2]],
          _ => all,
        };
        handler.resolve(
          Response(
            requestOptions: options,
            data: {
              'groups': selected,
              'total_rows_groups': selected.length,
              'load_more_groups': '/groups.json?page=1',
            },
          ),
        );
      },
    );
    service.dio.interceptors.insert(0, interceptor);
    addTearDown(() => service.dio.interceptors.remove(interceptor));
    await tester.binding.setSurfaceSize(const Size(980, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [discourseServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(
          locale: Locale('zh'),
          supportedLocales: [Locale('en'), Locale('zh')],
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: GroupsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group-card-g-adsfree')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-card-g-premium')), findsOneWidget);
    expect(find.text(fullBio), findsOneWidget);
    final longCard = find.byKey(const ValueKey('group-card-g-adsfree'));
    final shortCard = find.byKey(const ValueKey('group-card-g-premium'));
    expect(
      tester.getSize(longCard).height,
      greaterThan(tester.getSize(shortCard).height),
    );
    // 简介超过四行后仍完整排版，操作按钮位于正文下方且没有越出卡片。
    expect(tester.getSize(find.text(fullBio)).height, greaterThan(100));
    expect(
      tester.getBottomLeft(find.text(fullBio)).dy,
      lessThan(tester.getTopLeft(find.text('加入')).dy),
    );
    expect(
      tester.getBottomLeft(find.text('加入')).dy,
      lessThan(tester.getBottomLeft(longCard).dy),
    );
    expect(find.text('6529'), findsOneWidget);
    expect(find.text('加入'), findsOneWidget);
    expect(find.text('成员'), findsOneWidget);
    expect(find.text('已关闭'), findsOneWidget);
    expect(types.last, isNull);
    expect(find.text('加载更多'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(320, 700));
    await tester.pumpAndSettle();
    expect(find.text('6529'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomLeft(find.text(fullBio)).dy,
      lessThan(tester.getBottomLeft(longCard).dy),
    );
    await tester.binding.setSurfaceSize(const Size(980, 780));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('groups-type-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('groups-filter-my')));
    await tester.pumpAndSettle();
    expect(types.last, 'my');
    expect(find.byKey(const ValueKey('group-card-g-premium')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-card-g-adsfree')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('groups-type-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('groups-filter-close')));
    await tester.pumpAndSettle();
    expect(types.last, 'close');
    expect(find.text('已关闭'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('group-card-g-verified-staff')),
      findsOneWidget,
    );

    // 搜索仍通过服务端 filter 参数，不仅仅过滤当前页面的数据。
    await tester.enterText(find.byType(TextField).first, '机构');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(filters.last, '机构');
    expect(tester.takeException(), isNull);

    // 单列窄屏布局不应溢出。
    await tester.binding.setSurfaceSize(const Size(320, 700));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('group-card-g-verified-staff')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('群组全部加载后隐藏底部加载入口且不再请求下一页', (tester) async {
    final pages = <int>[];
    final service = DiscourseService();
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        final page = options.queryParameters['page'] as int;
        pages.add(page);
        handler.resolve(
          Response(
            requestOptions: options,
            data: {
              'groups': [
                {'id': page + 1, 'name': 'group-$page', 'user_count': 10},
              ],
              'total_rows_groups': 2,
              // 最后一页仍返回翻页地址，不能只用这个字段判断是否还有群组。
              'load_more_groups': '/groups.json?page=${page + 1}',
            },
          ),
        );
      },
    );
    service.dio.interceptors.insert(0, interceptor);
    addTearDown(() => service.dio.interceptors.remove(interceptor));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [discourseServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(
          locale: Locale('zh'),
          supportedLocales: [Locale('zh')],
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: GroupsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('加载更多'), findsOneWidget);
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();

    expect(pages, [0, 1]);
    expect(find.byKey(const ValueKey('group-card-group-1')), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(pages, [0, 1]);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('快速切换群组类型时丢弃旧请求结果', (tester) async {
    final releaseFirstRequest = Completer<void>();
    final requestedTypes = <String?>[];
    final service = DiscourseService();
    var requestCount = 0;
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.method != 'GET' || options.path != '/groups.json') {
          handler.reject(
            DioException(requestOptions: options, message: 'Unexpected request'),
          );
          return;
        }
        requestCount++;
        final type = options.queryParameters['type']?.toString();
        requestedTypes.add(type);
        final response = Response(
          requestOptions: options,
          data: {
            'groups': [
              {
                'id': type == 'public' ? 80 : 70,
                'name': type == 'public' ? 'public-group' : 'stale-group',
                'full_name': type == 'public' ? '公开群组结果' : '过期群组结果',
              },
            ],
            'total_rows_groups': 1,
          },
        );
        if (requestCount == 1) {
          // 第一个请求晚于两次筛选操作完成。
          releaseFirstRequest.future.then((_) => handler.resolve(response));
        } else {
          handler.resolve(response);
        }
      },
    );
    service.dio.interceptors.insert(0, interceptor);
    addTearDown(() => service.dio.interceptors.remove(interceptor));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [discourseServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: GroupsPage()),
      ),
    );
    await tester.pump();
    expect(requestedTypes, [null]);

    await tester.tap(find.byKey(const ValueKey('groups-type-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('groups-filter-my')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('groups-type-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('groups-filter-public')));
    await tester.pump();

    releaseFirstRequest.complete();
    await tester.pumpAndSettle();
    expect(requestedTypes.last, 'public');
    expect(find.text('公开群组结果'), findsOneWidget);
    expect(find.text('过期群组结果'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
