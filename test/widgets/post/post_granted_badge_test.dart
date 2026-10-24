import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/pages/badge_page.dart';
import 'package:fluxdo/widgets/post/post_item/widgets/post_granted_badge.dart';

class _PushObserver extends NavigatorObserver {
  Route<dynamic>? latestPage;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (previousRoute != null) latestPage = route;
  }
}

void main() {
  const badge = GrantedBadge(
    id: 164,
    name: 'Only Apple can do',
    description: "It's something Only Apple can do.",
    icon: 'fab-apple',
    slug: '-',
    badgeTypeId: 2,
  );

  testWidgets('silver Apple badge opens native detail filtered by author', (
    tester,
  ) async {
    final observer = _PushObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: const Scaffold(
          body: PostGrantedBadgeIcon(badge: badge, username: 'ccy'),
        ),
      ),
    );

    final icon = tester.widget<FaIcon>(find.byType(FaIcon));
    expect(icon.icon, FontAwesomeIcons.apple);
    expect(icon.color, const Color(0xFF9A9A9A));
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      "It's something Only Apple can do.",
    );
    await tester.tap(find.byKey(const ValueKey('post-granted-badge-164')));

    // Inspect the route builder without pumping BadgePage's network requests.
    final route = observer.latestPage as MaterialPageRoute<void>?;
    expect(route, isNotNull);
    final destination = route!.builder(
      tester.element(find.byType(PostGrantedBadgeIcon)),
    ) as BadgePage;
    expect(destination.badgeId, 164);
    expect(destination.badgeSlug, '-');
    expect(destination.username, 'ccy');
  });

  testWidgets('unmapped icon is omitted rather than showing a wrong logo', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PostGrantedBadgeIcon(
            badge: GrantedBadge(
              id: 100,
              name: 'Unknown',
              icon: 'nonexistent-badge-icon',
              slug: '-',
              badgeTypeId: 2,
            ),
            username: 'tester',
          ),
        ),
      ),
    );
    expect(find.byType(FaIcon), findsNothing);
    expect(find.byKey(const ValueKey('post-granted-badge-100')), findsNothing);
  });
}
