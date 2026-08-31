from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, got {count}: {old[:80]!r}")
    file.write_text(text.replace(old, new, 1))


path = "lib/widgets/layout/adaptive_navigation.dart"
replace_once(path, "import '../../utils/platform_utils.dart';\n", "import '../../utils/platform_utils.dart';\nimport '../user/account_quick_switcher_trigger_state.dart';\n")
replace_once(path, "}\n\n/// 侧边导航栏组件 (平板/桌面)\n", """}

void _recordAccountQuickSwitcherAnchor(BuildContext context, [Offset? fallback]) {
  AccountQuickSwitcherTriggerState.clear();
  final renderObject = context.findRenderObject();
  if (renderObject is RenderBox && renderObject.hasSize) {
    AccountQuickSwitcherTriggerState.setAnchor(
      renderObject.localToGlobal(renderObject.size.center(Offset.zero)),
    );
  } else if (fallback != null) {
    AccountQuickSwitcherTriggerState.setAnchor(fallback);
  }
}

/// 侧边导航栏组件 (平板/桌面)
""")
replace_once(path, """        Widget maybeLongPress(Widget child) => d.onLongPress == null
            ? child
            : GestureDetector(
                onLongPress: d.onLongPress,
                behavior: HitTestBehavior.translucent,
                child: child,
              );
""", """        Widget maybeLongPress(Widget child) {
          final callback = d.onLongPress;
          if (callback == null) return child;
          return Builder(
            builder: (triggerContext) => GestureDetector(
              onLongPressStart: (details) {
                _recordAccountQuickSwitcherAnchor(triggerContext, details.globalPosition);
                callback();
              },
              behavior: HitTestBehavior.translucent,
              child: child,
            ),
          );
        }
""")
replace_once(path, """          onTap: onTap,
          onLongPress: onLongPress,
          child: labelless
""", """          onTap: onTap,
          onLongPress: onLongPress == null
              ? null
              : () {
                  _recordAccountQuickSwitcherAnchor(context);
                  onLongPress!();
                },
          child: labelless
""")

path = "lib/widgets/user/account_switcher_sheet.dart"
replace_once(path, "import 'account_switch_loading.dart';\nimport 'radial_account_quick_switcher.dart';\n", "import 'account_quick_switcher_trigger_state.dart';\nimport 'account_switch_loading.dart';\nimport 'radial_account_quick_switcher.dart';\n")
replace_once(path, """    if (_preferTouchQuickSwitcher) {
      if (placement == AccountQuickSwitcherPlacement.bottomRight) {
        return _TouchAccountSwitcherEntry.show(context, placement: placement);
      }
      final container = ProviderScope.containerOf(context, listen: false);
""", """    if (_preferTouchQuickSwitcher) {
      final container = ProviderScope.containerOf(context, listen: false);
""")
replace_once(path, "return radialEnabled && placement == AccountQuickSwitcherPlacement.topRight;", "return radialEnabled;")
replace_once(path, """    final completer = Completer<void>();
    final pointerRoute = _QuickPointerRouteController();
    late OverlayEntry entry;
""", """    final globalAnchor = AccountQuickSwitcherTriggerState.takeAnchor();
    final overlayRenderObject = overlay.context.findRenderObject();
    final overlayBox = overlayRenderObject is RenderBox && overlayRenderObject.hasSize
        ? overlayRenderObject
        : null;
    final anchor = globalAnchor == null || overlayBox == null
        ? globalAnchor
        : overlayBox.globalToLocal(globalAnchor);
    final completer = Completer<void>();
    final pointerRoute = _QuickPointerRouteController();
    late OverlayEntry entry;
""")
replace_once(path, """        hostContext: context,
        placement: placement,
        pointerRoute: pointerRoute,
""", """        hostContext: context,
        placement: placement,
        anchor: anchor,
        pointerRoute: pointerRoute,
""")
replace_once(path, """    required this.hostContext,
    required this.placement,
    required this.pointerRoute,
""", """    required this.hostContext,
    required this.placement,
    required this.anchor,
    required this.pointerRoute,
""")
replace_once(path, """  final BuildContext hostContext;
  final AccountQuickSwitcherPlacement placement;
  final _QuickPointerRouteController pointerRoute;
""", """  final BuildContext hostContext;
  final AccountQuickSwitcherPlacement placement;
  final Offset? anchor;
  final _QuickPointerRouteController pointerRoute;
""")
replace_once(path, """    final showManageDivider = _loading || _accounts.isNotEmpty;

    final switcher = FadeTransition(
""", """    final showManageDivider = _loading || _accounts.isNotEmpty;
    const switcherWidth = 72.0;
    final maxSwitcherLeft = media.size.width - 12.0 - switcherWidth;
    final switcherLeft = widget.anchor == null
        ? null
        : (widget.anchor!.dx - switcherWidth / 2.0)
              .clamp(12.0, maxSwitcherLeft < 12.0 ? 12.0 : maxSwitcherLeft)
              .toDouble();

    final switcher = FadeTransition(
""")
replace_once(path, "alignment: fromTop ? Alignment.topRight : Alignment.bottomRight,", "alignment: fromTop ? Alignment.topCenter : Alignment.bottomCenter,")
replace_once(path, "width: 72,", "width: switcherWidth,")
replace_once(path, """            if (fromTop)
              Positioned(right: 12, top: edgeInset, child: switcher)
            else
              Positioned(right: 12, bottom: edgeInset, child: switcher),
""", """            if (fromTop)
              if (switcherLeft != null)
                Positioned(left: switcherLeft, top: edgeInset, child: switcher)
              else
                Positioned(right: 12, top: edgeInset, child: switcher)
            else if (switcherLeft != null)
              Positioned(left: switcherLeft, bottom: edgeInset, child: switcher)
            else
              Positioned(right: 12, bottom: edgeInset, child: switcher),
""")

path = "lib/widgets/user/radial_account_quick_switcher.dart"
replace_once(path, "    const preferredNodePitch = 58.0;\n", "")
replace_once(path, """    final inwardAngle = fromTop ? math.pi * 3.0 / 4.0 : math.pi * 5.0 / 4.0;
    final startAngle = fromTop ? math.pi / 2.0 : math.pi;
""", """    final roomToLeft = center.dx - targetCenterBounds.left;
    final roomToRight = targetCenterBounds.right - center.dx;
    final opensRight = roomToRight >= roomToLeft;
    final double inwardAngle;
    final double startAngle;
    if (fromTop) {
      if (opensRight) {
        startAngle = 0.0;
        inwardAngle = math.pi / 4.0;
      } else {
        startAngle = math.pi / 2.0;
        inwardAngle = math.pi * 3.0 / 4.0;
      }
    } else {
      if (opensRight) {
        startAngle = math.pi * 3.0 / 2.0;
        inwardAngle = math.pi * 7.0 / 4.0;
      } else {
        startAngle = math.pi;
        inwardAngle = math.pi * 5.0 / 4.0;
      }
    }
""")
replace_once(path, "    final slotAccounts = accounts;\n", """    final slotAccounts = accounts
        .where((account) => account.username != currentUsername)
        .toList(growable: false);
""")
replace_once(path, """    int capacityFor(double radius) {
      if (radius <= 0.0) return 0;
      final targetArc = accountArcFor(radius);
      if (targetArc.sweepAngle <= 0.0) return 0;
      return math.max(
        1,
        (radius * targetArc.sweepAngle / preferredNodePitch).floor() + 1,
      );
    }

""", """    int capacityForRing(int ringIndex) => ringIndex * 2 + 3;

    var requiredAccountRingCount = 0;
    var slotsRemaining = slotAccounts.length;
    while (slotsRemaining > 0) {
      slotsRemaining -= capacityForRing(requiredAccountRingCount);
      requiredAccountRingCount++;
    }

""")
replace_once(path, """    int comfortableAccountCapacity(List<double> radii) {
      var total = 0;
      for (final radius in radii) {
        total += capacityFor(radius);
      }
      return total;
    }

    var accountRingCount = hasAccounts && maxAccountRingCount > 0 ? 1 : 0;
    while (accountRingCount < maxAccountRingCount &&
        comfortableAccountCapacity(accountRadiiFor(accountRingCount)) <
            slotAccounts.length) {
      accountRingCount++;
    }
    final accountRadii = accountRadiiFor(accountRingCount).toList();
    if (accountRadii.length > 1 &&
        comfortableAccountCapacity(accountRadii) < slotAccounts.length) {
      final stretchedGap =
          (maxAccountRadius - accountInnerRadius) / (accountRadii.length - 1);
      for (var index = 0; index < accountRadii.length; index++) {
        accountRadii[index] = accountInnerRadius + stretchedGap * index;
      }
    }
    final overflowed =
        comfortableAccountCapacity(accountRadii) < slotAccounts.length;
""", """    final accountRingCount = math.min(requiredAccountRingCount, maxAccountRingCount);
    final accountRadii = accountRadiiFor(accountRingCount).toList();
    final overflowed = requiredAccountRingCount > maxAccountRingCount;
""")
replace_once(path, """    var accountOffset = 0;
    for (final radius in accountRadii) {
      final remaining = slotAccounts.length - accountOffset;
      if (remaining <= 0) break;
      final accountCount = math.min(remaining, capacityFor(radius));
""", """    var accountOffset = 0;
    for (var ringIndex = 0; ringIndex < accountRadii.length; ringIndex++) {
      final radius = accountRadii[ringIndex];
      final remaining = slotAccounts.length - accountOffset;
      if (remaining <= 0) break;
      final accountCount = math.min(remaining, capacityForRing(ringIndex));
""")

path = "test/widgets/user/account_switcher_sheet_test.dart"
replace_once(path, "test('bottom-right account switcher always ignores radial mode', () {", "test('bottom profile account switcher follows radial mode', () {")
replace_once(path, """      isFalse,
    );
  });

  test('top-right account switcher still follows radial mode', () {
""", """      isTrue,
    );
    expect(
      AccountSwitcherSheet.shouldUseRadialSwitcher(
        placement: AccountQuickSwitcherPlacement.bottomRight,
        radialEnabled: false,
      ),
      isFalse,
    );
  });

  test('top-right account switcher still follows radial mode', () {
""")
