import 'dart:async';

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
      '${detail ? 'Group detail' : 'Group directory'} ignores stale refresh after leaving',
      (tester) async {
        var isMember = true;
        var leaveRequests = 0;
        var holdRefresh = false;
        final refreshStarted = Completer<void>();
        final releaseRefresh = Completer<void>();
        final service = DiscourseService();
        final interceptor = InterceptorsWrapper(
          onRequest: (options, handler) async {
            final snapshot = isMember;
            if (options.method == 'GET' &&
                (options.path == '/groups.json' ||
                    options.path == '/groups/test_group.json')) {
              if (holdRefresh) {
                holdRefresh = false;
                refreshStarted.complete();
                await releaseRefresh.future;
              }
              final group = {
                'id': 7,
                'name': 'test_group',
                'full_name': '测试群组',
                'user_count': snapshot ? 4 : 3,
                'is_group_user': snapshot,
                'public_exit': true,
                'can_see_members': false,
              };
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: options.path == '/groups.json'
                      ? {
                          'groups': [group],
                          'total_rows_groups': 1,
                        }
                      : {'group': group},
                ),
              );
              return;
            }
            if (options.method == 'DELETE' &&
                options.path == '/groups/7/leave.json') {
              leaveRequests++;
              isMember = false;
              handler.resolve(
                Response(requestOptions: options, data: {'success': 'OK'}),
              );
              return;
            }
            handler.reject(
              DioException(requestOptions: options, message: 'Unexpected API'),
            );
          },
        );
        service.dio.interceptors.insert(0, interceptor);
        addTearDown(() => service.dio.interceptors.remove(interceptor));
        addTearDown(() {
          if (!releaseRefresh.isCompleted) releaseRefresh.complete();
        });

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

        holdRefresh = true;
        await tester.tap(find.byTooltip('刷新'));
        await tester.pump();
        // Dio dispatches the interceptor asynchronously after a widget frame.
        await tester.runAsync(
          () => refreshStarted.future.timeout(const Duration(seconds: 5)),
        );

        await tester.tap(find.widgetWithText(OutlinedButton, '退出'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('leave-group-confirm')));
        await tester.pump();
        expect(leaveRequests, 1);

        // The in-flight GET contains a membership snapshot from before DELETE.
        releaseRefresh.complete();
        await tester.pumpAndSettle();
        expect(find.widgetWithText(OutlinedButton, '退出'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
