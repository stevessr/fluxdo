import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/site_info_page.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';

class _FakeDiscourseService extends Fake implements DiscourseService {
  final requests = <String>[];

  @override
  late final Dio dio = Dio(BaseOptions(baseUrl: 'https://linux.do'))
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options.path);
          if (options.path == '/about.json') {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                data: {
                  'users': <dynamic>[],
                  'about': {
                    'title': 'Test Forum',
                    'description': 'Test site description',
                  },
                },
              ),
            );
            return;
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              data: '<div itemprop="mainContentOfPage">'
                  '<h2 id="section">Policy content</h2>'
                  '<p>Loaded from ${options.path}</p>'
                  '</div>',
            ),
          );
        },
      ),
    );
}

class _RouteCounter extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

void main() {
  testWidgets('all four tabs share one route and reuse loaded sections', (
    tester,
  ) async {
    final service = _FakeDiscourseService();
    final observer = _RouteCounter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [discourseServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          navigatorObservers: [observer],
          home: const SiteInfoPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Forum'), findsOneWidget);
    expect(observer.pushes, 1);
    expect(service.requests.where((path) => path == '/about.json').length, 1);

    Future<void> select(String tab) async {
      final chip = find.widgetWithText(ChoiceChip, tab);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
      expect(observer.pushes, 1);
    }

    await select('Guidelines');
    expect(service.requests.where((path) => path == '/guidelines').length, 1);
    await select('Terms');
    expect(service.requests.where((path) => path == '/tos').length, 1);
    await select('Privacy');
    expect(service.requests.where((path) => path == '/privacy').length, 1);

    await select('Guidelines');
    expect(service.requests.where((path) => path == '/guidelines').length, 1);
    await select('About');
    expect(service.requests.where((path) => path == '/about.json').length, 1);
    expect(find.text('Test Forum'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
