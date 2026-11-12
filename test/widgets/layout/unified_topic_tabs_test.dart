import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/selected_topic_provider.dart';
import 'package:fluxdo/widgets/layout/pico_parallel_tabs.dart';

void main() {
  testWidgets('长按统一标签提供关闭其他、关闭所有两个动作', (tester) async {
    final notifier = SelectedTopicNotifier()
      ..openTopicTab(topicId: 1, initialTitle: '公开', instanceId: 'public')
      ..openTopicTab(
        topicId: 2,
        initialTitle: '私信',
        instanceId: 'pm',
        isPrivateMessage: true,
      );

    Widget buildTabs() => MaterialApp(
      locale: const Locale('en'),
      home: Scaffold(
        body: PicoParallelTabs(
          selected: notifier.state,
          onActivate: notifier.activateTab,
          onClose: notifier.closeTab,
          onCloseOthers: notifier.closeOtherTabs,
          onCloseAll: notifier.closeAllTabs,
          onShowFeed: notifier.showFeed,
        ),
      ),
    );

    await tester.pumpWidget(buildTabs());
    expect(find.byIcon(Icons.mail_outline_rounded), findsOneWidget);

    await tester.longPress(find.byKey(const ValueKey('pico-pane-tab-1')));
    await tester.pumpAndSettle();
    expect(find.text('Close other tabs'), findsOneWidget);
    expect(find.text('Close all tabs'), findsOneWidget);

    await tester.tap(find.text('Close other tabs'));
    await tester.pumpAndSettle();
    expect(notifier.state.stack, hasLength(1));
    expect(notifier.state.instanceId, 'pm');

    await tester.pumpWidget(buildTabs());
    await tester.longPress(find.byKey(const ValueKey('pico-pane-tab-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close all tabs'));
    await tester.pumpAndSettle();

    expect(notifier.state.stack, isEmpty);
    expect(notifier.state.tabMode, isFalse);
  });
}
