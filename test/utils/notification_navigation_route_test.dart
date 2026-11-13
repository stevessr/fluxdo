import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/notification_navigation.dart';

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
