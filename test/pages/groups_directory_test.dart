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
            'bio_excerpt': '加入群组，页面不再展示广告。',
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
    expect(find.text('加入群组，页面不再展示广告。'), findsOneWidget);
    expect(find.text('6529'), findsOneWidget);
    expect(find.text('加入'), findsOneWidget);
    expect(find.text('成员'), findsOneWidget);
    expect(find.text('已关闭'), findsOneWidget);
    expect(types.last, isNull);
    expect(tester.takeException(), isNull);

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
    expect(find.byKey(const ValueKey('group-card-g-verified-staff')), findsOneWidget);

    // 搜索仍通过服务端 filter 参数，不仅仅过滤当前页面的数据。
    await tester.enterText(find.byType(TextField).first, '机构');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(filters.last, '机构');
    expect(tester.takeException(), isNull);

    // 单列窄屏布局不应溢出。
    await tester.binding.setSurfaceSize(const Size(320, 700));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group-card-g-verified-staff')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
