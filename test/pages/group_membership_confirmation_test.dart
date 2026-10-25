import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/group_page.dart';
import 'package:fluxdo/pages/groups_page.dart';
import 'package:fluxdo/providers/discourse_providers.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';

void main() {
  for (final detail in [false, true]) {
    testWidgets(
      '${detail ? 'Group detail' : 'Group directory'} only leaves after confirmation',
      (tester) async {
        var leaveRequests = 0;
        var isMember = true;
        final service = DiscourseService();
        final interceptor = InterceptorsWrapper(
          onRequest: (options, handler) {
            final group = <String, dynamic>{
              'id': 7,
              'name': 'test_group',
              'full_name': '测试群组',
              'user_count': isMember ? 4 : 3,
              'is_group_user': isMember,
              'public_exit': true,
              'can_see_members': false,
            };
            if (options.method == 'GET' && options.path == '/groups.json') {
              handler.resolve(Response(
                requestOptions: options,
                data: {
                  'groups': [group],
                  'total_rows_groups': 1,
                },
              ));
            } else if (options.method == 'GET' &&
                options.path == '/groups/test_group.json') {
              handler.resolve(Response(
                requestOptions: options,
                data: {'group': group},
              ));
            } else if (options.method == 'DELETE' &&
                options.path == '/groups/7/leave.json') {
              leaveRequests++;
              isMember = false;
              handler.resolve(Response(
                requestOptions: options,
                data: {'success': 'OK'},
              ));
            } else {
              handler.reject(DioException(
                requestOptions: options,
                message: 'Unexpected request: ${options.method} ${options.path}',
              ));
            }
          },
        );
        service.dio.interceptors.insert(0, interceptor);
        addTearDown(() => service.dio.interceptors.remove(interceptor));

        await tester.binding.setSurfaceSize(const Size(320, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [discourseServiceProvider.overrideWithValue(service)],
            child: MaterialApp(
              locale: const Locale('zh'),
              supportedLocales: const [Locale('en'), Locale('zh')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: detail
                  ? const GroupPage(groupName: 'test_group')
                  : const GroupsPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.widgetWithText(OutlinedButton, '退出'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Opening, cancelling, or dismissing must not send a DELETE.
        await tester.tap(find.widgetWithText(OutlinedButton, '退出'));
        await tester.pumpAndSettle();
        expect(find.textContaining('测试群组'), findsWidgets);
        expect(leaveRequests, 0);
        await tester.tap(find.byKey(const ValueKey('leave-group-cancel')));
        await tester.pumpAndSettle();
        expect(leaveRequests, 0);
        expect(find.widgetWithText(OutlinedButton, '退出'), findsOneWidget);

        await tester.tap(find.widgetWithText(OutlinedButton, '退出'));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        expect(leaveRequests, 0);

        await tester.tap(find.widgetWithText(OutlinedButton, '退出'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('leave-group-confirm')));
        await tester.pumpAndSettle();
        expect(leaveRequests, 1);
        expect(find.widgetWithText(OutlinedButton, '退出'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
