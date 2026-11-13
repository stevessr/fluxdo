import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/layout/adaptive_navigation.dart';
import 'package:fluxdo/widgets/user/account_quick_switcher_trigger_state.dart';

void main() {
  testWidgets(
    'topDestinationCount keeps only the top group above category shortcuts',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(220, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                height: 700,
                child: AdaptiveNavigationRail(
                  selectedIndex: -1,
                  onDestinationSelected: (_) {},
                  extended: true,
                  topDestinationCount: 1,
                  categoryShortcuts: const SizedBox(
                    key: ValueKey('shortcuts'),
                    height: 80,
                  ),
                  destinations: const [
                    AdaptiveDestination(
                      id: 'home',
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: 'Home',
                    ),
                    AdaptiveDestination(
                      id: 'profile',
                      icon: Icon(Icons.person_outline),
                      selectedIcon: Icon(Icons.person),
                      label: 'Profile',
                    ),
                    AdaptiveDestination(
                      id: 'bookmarks',
                      icon: Icon(Icons.bookmark_outline),
                      selectedIcon: Icon(Icons.bookmark),
                      label: 'Bookmarks',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final homeTop = tester.getTopLeft(find.text('Home')).dy;
      final shortcutsTop = tester
          .getTopLeft(find.byKey(const ValueKey('shortcuts')))
          .dy;
      final profileTop = tester.getTopLeft(find.text('Profile')).dy;
      final bookmarksBottom = tester.getBottomRight(find.text('Bookmarks')).dy;
      final railBottom = tester
          .getBottomRight(find.byType(AdaptiveNavigationRail))
          .dy;

      expect(homeTop, lessThan(shortcutsTop));
      expect(shortcutsTop, lessThan(profileTop));
      expect(railBottom - bookmarksBottom, lessThanOrEqualTo(32));
    },
  );
  for (final extended in [false, true]) {
    testWidgets(
      'rail profile long press anchors to icon (extended=$extended)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(900, 700);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(AccountQuickSwitcherTriggerState.clear);

        var invoked = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.centerLeft,
                child: AdaptiveNavigationRail(
                  selectedIndex: 0,
                  onDestinationSelected: (_) {},
                  extended: extended,
                  topDestinationCount: 1,
                  destinations: [
                    const AdaptiveDestination(
                      id: 'home',
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: 'Home',
                    ),
                    AdaptiveDestination(
                      id: 'profile',
                      icon: const Icon(Icons.person_outline),
                      selectedIcon: const Icon(Icons.person),
                      label: 'Profile',
                      onLongPress: () => invoked++,
                    ),
                  ],
                ),
                ),
              ),
            ),
        );

        final profileIcon = find.byIcon(Icons.person_outline);
        final expectedCenter = tester.getCenter(profileIcon);
        await tester.longPress(profileIcon);
        expect(invoked, 1);
        final anchor = AccountQuickSwitcherTriggerState.takeAnchor();
        expect(anchor, isNotNull);
        expect((anchor! - expectedCenter).distance, lessThan(1.0));
        expect(anchor.dx, lessThan(200));
      },
    );
  }

}
