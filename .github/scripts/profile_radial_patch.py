from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"{path}: expected one match, got {count}: {old[:80]!r}"
        )
    file.write_text(text.replace(old, new, 1))


# Capture the actual navigation item center for both stock and floating bottom
# bars instead of assuming the Profile entry lives at the right edge.
path = "lib/widgets/layout/adaptive_navigation.dart"
replace_once(
    path,
    "import '../../utils/platform_utils.dart';\n",
    "import '../../utils/platform_utils.dart';\n"
    "import '../user/account_quick_switcher_trigger_state.dart';\n",
)
replace_once(
    path,
    "}\n\n/// 侧边导航栏组件 (平板/桌面)\n",
    """}

void _recordAccountQuickSwitcherAnchor(
  BuildContext context, [
  Offset? fallback,
]) {
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
""",
)
replace_once(
    path,
    """        Widget maybeLongPress(Widget child) => d.onLongPress == null
            ? child
            : GestureDetector(
                onLongPress: d.onLongPress,
                behavior: HitTestBehavior.translucent,
                child: child,
              );
""",
    """        Widget maybeLongPress(Widget child) {
          final callback = d.onLongPress;
          if (callback == null) return child;
          return Builder(
            builder: (triggerContext) => GestureDetector(
              onLongPressStart: (details) {
                _recordAccountQuickSwitcherAnchor(
                  triggerContext,
                  details.globalPosition,
                );
                callback();
              },
              behavior: HitTestBehavior.translucent,
              child: child,
            ),
          );
        }
""",
)
replace_once(
    path,
    """          onTap: onTap,
          onLongPress: onLongPress,
          child: labelless
""",
    """          onTap: onTap,
          onLongPress: onLongPress == null
              ? null
              : () {
                  _recordAccountQuickSwitcherAnchor(context);
                  onLongPress!();
                },
          child: labelless
""",
)

# Restore radial switching for the bottom Profile entry and make the vertical
# fallback follow the real horizontal trigger position too.
path = "lib/widgets/user/account_switcher_sheet.dart"
replace_once(
    path,
    "import 'account_switch_loading.dart';\nimport 'radial_account_quick_switcher.dart';\n",
    "import 'account_quick_switcher_trigger_state.dart';\n"
    "import 'account_switch_loading.dart';\n"
    "import 'radial_account_quick_switcher.dart';\n",
)
replace_once(
    path,
    """/// 触摸设备的底栏「我的」始终使用 Telegram 风格纵向快捷切换器；右上角
/// 头像入口仍可在外观设置里选择伞状切换器。桌面端继续使用经典 bottom
/// sheet。
""",
    """/// 触摸设备可在外观设置里选择伞状快捷切换器；伞状布局以真实长按入口
/// 为圆心并自动朝屏幕内侧展开。关闭时保留 Telegram 风格纵向快捷切换器。
/// 桌面端继续使用经典 bottom sheet。
""",
)
replace_once(
    path,
    """    if (_preferTouchQuickSwitcher) {
      if (placement == AccountQuickSwitcherPlacement.bottomRight) {
        return _TouchAccountSwitcherEntry.show(context, placement: placement);
      }
      final container = ProviderScope.containerOf(context, listen: false);
""",
    """    if (_preferTouchQuickSwitcher) {
      final container = ProviderScope.containerOf(context, listen: false);
""",
)
replace_once(
    path,
    """  /// 底栏「我的」是固定交互，不受伞状开关影响。
  @visibleForTesting
  static bool shouldUseRadialSwitcher({
    required AccountQuickSwitcherPlacement placement,
    required bool radialEnabled,
  }) {
    return radialEnabled && placement == AccountQuickSwitcherPlacement.topRight;
  }
""",
    """  /// 手机端所有账号快捷入口都遵循伞状开关；具体展开象限由真实锚点决定。
  @visibleForTesting
  static bool shouldUseRadialSwitcher({
    required AccountQuickSwitcherPlacement placement,
    required bool radialEnabled,
  }) {
    return radialEnabled;
  }
""",
)
replace_once(
    path,
    """    final completer = Completer<void>();
    final pointerRoute = _QuickPointerRouteController();
    late OverlayEntry entry;
""",
    """    final globalAnchor = AccountQuickSwitcherTriggerState.takeAnchor();
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
""",
)
replace_once(
    path,
    """        hostContext: context,
        placement: placement,
        pointerRoute: pointerRoute,
""",
    """        hostContext: context,
        placement: placement,
        anchor: anchor,
        pointerRoute: pointerRoute,
""",
)
replace_once(
    path,
    """    required this.hostContext,
    required this.placement,
    required this.pointerRoute,
""",
    """    required this.hostContext,
    required this.placement,
    required this.anchor,
    required this.pointerRoute,
""",
)
replace_once(
    path,
    """  final BuildContext hostContext;
  final AccountQuickSwitcherPlacement placement;
  final _QuickPointerRouteController pointerRoute;
""",
    """  final BuildContext hostContext;
  final AccountQuickSwitcherPlacement placement;
  final Offset? anchor;
  final _QuickPointerRouteController pointerRoute;
""",
)
replace_once(
    path,
    """    final showManageDivider = _loading || _accounts.isNotEmpty;

    final switcher = FadeTransition(
""",
    """    final showManageDivider = _loading || _accounts.isNotEmpty;
    const switcherWidth = 72.0;
    final maxSwitcherLeft = media.size.width - 12.0 - switcherWidth;
    final switcherLeft = widget.anchor == null
        ? null
        : (widget.anchor!.dx - switcherWidth / 2.0)
              .clamp(12.0, maxSwitcherLeft < 12.0 ? 12.0 : maxSwitcherLeft)
              .toDouble();

    final switcher = FadeTransition(
""",
)
replace_once(
    path,
    "alignment: fromTop ? Alignment.topRight : Alignment.bottomRight,",
    "alignment: fromTop ? Alignment.topCenter : Alignment.bottomCenter,",
)
replace_once(path, "width: 72,", "width: switcherWidth,")
replace_once(
    path,
    """            if (fromTop)
              Positioned(right: 12, top: edgeInset, child: switcher)
            else
              Positioned(right: 12, bottom: edgeInset, child: switcher),
""",
    """            if (fromTop)
              if (switcherLeft != null)
                Positioned(left: switcherLeft, top: edgeInset, child: switcher)
              else
                Positioned(right: 12, top: edgeInset, child: switcher)
            else if (switcherLeft != null)
              Positioned(left: switcherLeft, bottom: edgeInset, child: switcher)
            else
              Positioned(right: 12, bottom: edgeInset, child: switcher),
""",
)

# Radial geometry: derive left/right from actual available space and use
# deterministic avatar capacities: 1 at the pivot, then 3/5/7/... .
path = "lib/widgets/user/radial_account_quick_switcher.dart"
replace_once(path, "    const preferredNodePitch = 58.0;\n", "")
replace_once(
    path,
    """    // Placement is already known by the caller. Do not infer it again from a
    // percentage of the screen: compact/floating navigation bars can place the
    // profile entry well inside that threshold even though it is still the
    // bottom-right trigger.
    final inwardAngle = fromTop ? math.pi * 3.0 / 4.0 : math.pi * 5.0 / 4.0;
    final startAngle = fromTop ? math.pi / 2.0 : math.pi;
""",
    """    // The vertical side is known by the entry kind, but the horizontal side is
    // deliberately derived from the real trigger position. Configurable/floating
    // bottom navigation can put Profile at either bottom-left or bottom-right.
    // Pick the quadrant with more horizontal room and always expand inward.
    final roomToLeft = center.dx - targetCenterBounds.left;
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
""",
)
replace_once(
    path,
    """    // Slot geometry is derived from the complete saved-account registry. The
    // active account keeps its original slot but is not rendered there, so
    // switching the active account cannot make the remaining targets reflow.
    final slotAccounts = accounts;
""",
    """    // The active account is the dedicated 1-avatar centre layer. Remaining
    // avatars fill deterministic odd-capacity arc layers: 3, 5, 7, ... .
    final slotAccounts = accounts
        .where((account) => account.username != currentUsername)
        .toList(growable: false);
""",
)
replace_once(
    path,
    """    int capacityFor(double radius) {
      if (radius <= 0.0) return 0;
      final targetArc = accountArcFor(radius);
      if (targetArc.sweepAngle <= 0.0) return 0;
      return math.max(
        1,
        (radius * targetArc.sweepAngle / preferredNodePitch).floor() + 1,
      );
    }

""",
    """    int capacityForRing(int ringIndex) => ringIndex * 2 + 3;

    var requiredAccountRingCount = 0;
    var slotsRemaining = slotAccounts.length;
    while (slotsRemaining > 0) {
      slotsRemaining -= capacityForRing(requiredAccountRingCount);
      requiredAccountRingCount++;
    }

""",
)
replace_once(
    path,
    """    int comfortableAccountCapacity(List<double> radii) {
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
""",
    """    final accountRingCount = math.min(
      requiredAccountRingCount,
      maxAccountRingCount,
    );
    final accountRadii = accountRadiiFor(accountRingCount).toList();
    final overflowed = requiredAccountRingCount > maxAccountRingCount;
""",
)
replace_once(
    path,
    """    var accountOffset = 0;
    for (final radius in accountRadii) {
      final remaining = slotAccounts.length - accountOffset;
      if (remaining <= 0) break;
      final accountCount = math.min(remaining, capacityFor(radius));
""",
    """    var accountOffset = 0;
    for (var ringIndex = 0; ringIndex < accountRadii.length; ringIndex++) {
      final radius = accountRadii[ringIndex];
      final remaining = slotAccounts.length - accountOffset;
      if (remaining <= 0) break;
      final accountCount = math.min(
        remaining,
        capacityForRing(ringIndex),
      );
""",
)

# Appearance copy now matches both bottom-left and bottom-right radial use.
path = "lib/settings/definitions/account_quick_switcher_appearance_defs.dart"
replace_once(
    path,
    "radialDescription: '仅用于右上角头像入口；右下角「我的」始终使用悬浮账号列表。',",
    "radialDescription: '以实际长按入口为圆心，自动向屏幕内侧展开；当前账号在圆心，后续头像按 3、5、7… 分层。',",
)
replace_once(
    path,
    "radialDescription: '僅用於右上角頭像入口；右下角「我的」一律使用懸浮帳號列表。',",
    "radialDescription: '以實際長按入口為圓心，自動向螢幕內側展開；目前帳號在圓心，後續頭像按 3、5、7… 分層。',",
)
replace_once(
    path,
    "radialDescription: 'Only applies to top-right avatar entries. The bottom-right Profile entry always uses the floating account list.',",
    "radialDescription: 'Use the actual pressed entry as the pivot and expand inward. The active account stays at the center; later avatar rings hold 3, 5, 7, ... accounts.',",
)

# Regression tests: bottom Profile follows the setting, left-side anchors mirror
# correctly, and odd ring capacities stay deterministic.
path = "test/widgets/user/account_switcher_sheet_test.dart"
replace_once(
    path,
    "test('bottom-right account switcher always ignores radial mode', () {",
    "test('bottom account switcher follows radial mode', () {",
)
replace_once(
    path,
    """      isFalse,
    );
  });

  test('top-right account switcher still follows radial mode', () {
""",
    """      isTrue,
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
""",
)

path = "test/widgets/user/radial_account_quick_switcher_layout_test.dart"
marker = "  test('top-right placement opens into the lower-left visible quadrant', () {\n"
replace_once(
    path,
    marker,
    """  test('bottom-left placement mirrors into the upper-right quadrant', () {
    final layout = calculateRadialAccountQuickSwitcherLayoutForTest(
      size: const Size(390, 844),
      padding: const EdgeInsets.only(top: 47, bottom: 34),
      anchor: const Offset(40, 760),
      switchableAccountCount: 8,
    );

    expect(layout.overflowed, isFalse);
    expect(layout.accountCenters, hasLength(8));
    _expectAllTargetsVisible(layout);
    for (final center in [...layout.accountCenters, layout.manageCenter]) {
      expect(center.dx, greaterThanOrEqualTo(layout.center.dx - 0.01));
      expect(center.dy, lessThanOrEqualTo(layout.center.dy + 0.01));
    }
  });

  test('avatar arc layers use 3, 5, 7 capacities after the center', () {
    final layout = calculateRadialAccountQuickSwitcherLayoutForTest(
      size: const Size(430, 932),
      padding: const EdgeInsets.only(top: 48, bottom: 34),
      anchor: const Offset(390, 850),
      switchableAccountCount: 15,
    );

    expect(layout.overflowed, isFalse);
    final countsByRadius = <int, int>{};
    for (final center in layout.accountCenters) {
      final radius = (center - layout.center).distance.round();
      countsByRadius[radius] = (countsByRadius[radius] ?? 0) + 1;
    }
    final counts = countsByRadius.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    expect(counts.map((entry) => entry.value).toList(), [3, 5, 7]);
  });

""" + marker,
)
