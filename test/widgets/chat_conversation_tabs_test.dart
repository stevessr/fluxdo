import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/chat/chat_conversation_tabs.dart';

class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  var outerIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Row(
            children: [
              TextButton(
                key: const ValueKey('show-dms'),
                onPressed: () => setState(() => outerIndex = 0),
                child: const Text('Direct Messages'),
              ),
              TextButton(
                key: const ValueKey('show-channels'),
                onPressed: () => setState(() => outerIndex = 1),
                child: const Text('Channels'),
              ),
            ],
          ),
          Expanded(
            child: IndexedStack(
              index: outerIndex,
              children: const [
                ChatConversationTabs(
                  id: 'regression',
                  privateCount: 2,
                  groupCount: 2,
                  privateLabel: 'Private',
                  groupLabel: 'Group',
                  privateChild: Center(child: Text('PRIVATE-CONTENT')),
                  groupChild: Center(child: Text('GROUP-CONTENT')),
                ),
                Center(child: Text('CHANNEL-CONTENT')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets(
    'Direct Messages -> Channels -> Direct Messages keeps highlight and content in sync',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _Harness()));

      expect(find.text('PRIVATE-CONTENT'), findsOneWidget);
      expect(find.text('GROUP-CONTENT'), findsNothing);

      await tester.tap(find.text('Group'));
      await tester.pumpAndSettle();
      expect(find.text('GROUP-CONTENT'), findsOneWidget);
      expect(find.text('PRIVATE-CONTENT'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('show-channels')));
      await tester.pumpAndSettle();
      expect(find.text('CHANNEL-CONTENT'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('show-dms')));
      await tester.pumpAndSettle();
      expect(find.text('GROUP-CONTENT'), findsOneWidget);

      await tester.tap(find.text('Private'));
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE-CONTENT'), findsOneWidget);
      expect(find.text('GROUP-CONTENT'), findsNothing);

      final stack = tester.widget<IndexedStack>(
        find.byKey(const ValueKey('chat-regression-subtab-view')),
      );
      expect(stack.index, 0);
    },
  );
}
