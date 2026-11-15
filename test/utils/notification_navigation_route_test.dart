import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/navigation/nav_action_bus.dart';
import 'package:fluxdo/utils/notification_navigation.dart';
import 'package:fluxdo/widgets/layout/master_detail_layout.dart';

class _RouteProbe extends StatelessWidget {
  const _RouteProbe();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Builder(
        builder: (context) => Text(
          ModalRoute.of(context)?.settings.name ?? 'unnamed',
        ),
      ),
    );
  }
}

void main() {

  testWidgets('平行视界通知入口切换工作区而不叠加旧通知路由', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  expect(MasterDetailLayout.canShowBothPanesFor(context), isTrue);
                  openNotificationPage(
                    context,
                    const _RouteProbe(),
                    isNotificationList: true,
                  );
                },
                child: const Text('notification badge'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('notification badge'));
    await tester.pump();
    final first = container.read(navDestinationRequestProvider);
    expect(first?.targetId, NavEntryIds.notifications);
    expect(find.text(notificationPageRouteName), findsNothing);

    await tester.tap(find.text('notification badge'));
    await tester.pump();
    expect(container.read(navDestinationRequestProvider)?.nonce, first!.nonce + 1);
    expect(find.text(notificationPageRouteName), findsNothing);
  });
  testWidgets('只有完整通知页使用独立通知路由名', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => openNotificationPage(
                    context,
                    const _RouteProbe(),
                    isNotificationList: true,
                  ),
                  child: const Text('notification list'),
                ),
                TextButton(
                  onPressed: () =>
                      openNotificationPage(context, const _RouteProbe()),
                  child: const Text('normal page'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('notification list'));
    await tester.pumpAndSettle();
    expect(find.text(notificationPageRouteName), findsOneWidget);

    Navigator.of(tester.element(find.text(notificationPageRouteName))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('normal page'));
    await tester.pumpAndSettle();
    expect(find.text('unnamed'), findsOneWidget);
  });
}
