import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/layout/pane_filmstrip.dart';

class _TrackedPane extends StatefulWidget {
  const _TrackedPane({required this.onMount, required this.onUnmount});

  final VoidCallback onMount;
  final VoidCallback onUnmount;

  @override
  State<_TrackedPane> createState() => _TrackedPaneState();
}

class _TrackedPaneState extends State<_TrackedPane> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    widget.onUnmount();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(key: ValueKey('tracked-tab-content'));
  }
}

void main() {
  testWidgets(
    'showMasterOnly retains mounted tab and restores the same State',
    (tester) async {
      var mounts = 0;
      var unmounts = 0;
      var showMasterOnly = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) {
                return Column(
                  children: [
                    TextButton(
                      onPressed: () {
                        update(() => showMasterOnly = !showMasterOnly);
                      },
                      child: const Text('Toggle feed'),
                    ),
                    Expanded(
                      child: PaneFilmstrip(
                        master: const ColoredBox(
                          color: Colors.white,
                          child: SizedBox.expand(
                            key: ValueKey('master-content'),
                          ),
                        ),
                        panes: [
                          KeyedSubtree(
                            key: const ValueKey('topic-1'),
                            child: _TrackedPane(
                              onMount: () => mounts++,
                              onUnmount: () => unmounts++,
                            ),
                          ),
                        ],
                        masterWidth: 300,
                        viewportPanes: 2,
                        showMasterOnly: showMasterOnly,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(mounts, 1);
      expect(unmounts, 0);

      await tester.tap(find.text('Toggle feed'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey('tracked-tab-content'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(mounts, 1);
      expect(unmounts, 0);
      expect(
        tester.getSize(find.byKey(const ValueKey('master-content'))).width,
        greaterThan(300),
      );

      await tester.tap(find.text('Toggle feed'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('tracked-tab-content')),
        findsOneWidget,
      );
      expect(mounts, 1);
      expect(unmounts, 0);
    },
  );
}
