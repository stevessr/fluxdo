import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/user/radial_account_quick_switcher.dart';

void main() {
  group('bottom-right radial account switcher layout', () {
    const cases = <({Size size, EdgeInsets padding, Offset anchor})>[
      (
        size: Size(360, 800),
        padding: EdgeInsets.only(top: 24, bottom: 24),
        anchor: Offset(324, 730),
      ),
      (
        size: Size(390, 844),
        padding: EdgeInsets.only(top: 47, bottom: 34),
        anchor: Offset(350, 760),
      ),
      (
        size: Size(320, 568),
        padding: EdgeInsets.only(top: 24, bottom: 16),
        anchor: Offset(286, 500),
      ),
      (
        size: Size(800, 360),
        padding: EdgeInsets.only(top: 24, bottom: 24),
        anchor: Offset(720, 295),
      ),
    ];

    for (final testCase in cases) {
      for (final accountCount in const [1, 3, 10, 16]) {
        test('${testCase.size.width}x${testCase.size.height} keeps '
            '$accountCount accounts visible', () {
          final layout = calculateRadialAccountQuickSwitcherLayoutForTest(
            size: testCase.size,
            padding: testCase.padding,
            anchor: testCase.anchor,
            switchableAccountCount: accountCount,
          );

          expect(layout.overflowed, isFalse);
          expect(layout.accountCenters, hasLength(accountCount));
          _expectAllTargetsVisible(layout);

          for (final center in [
            ...layout.accountCenters,
            layout.manageCenter,
          ]) {
            expect(center.dx, lessThanOrEqualTo(layout.center.dx + 0.01));
            expect(center.dy, lessThanOrEqualTo(layout.center.dy + 0.01));
          }
        });
      }
    }

    test('never pushes excess accounts beyond the viewport', () {
      final layout = calculateRadialAccountQuickSwitcherLayoutForTest(
        size: const Size(320, 568),
        padding: const EdgeInsets.only(top: 24, bottom: 16),
        anchor: const Offset(286, 500),
        switchableAccountCount: 200,
      );

      expect(layout.overflowed, isTrue);
      _expectAllTargetsVisible(layout);
    });
  });

  test('top-right placement opens into the lower-left visible quadrant', () {
    final layout = calculateRadialAccountQuickSwitcherLayoutForTest(
      size: const Size(390, 844),
      padding: const EdgeInsets.only(top: 47, bottom: 34),
      anchor: const Offset(350, 82),
      switchableAccountCount: 10,
      fromTop: true,
    );

    expect(layout.overflowed, isFalse);
    expect(layout.accountCenters, hasLength(10));
    _expectAllTargetsVisible(layout);
    for (final center in [...layout.accountCenters, layout.manageCenter]) {
      expect(center.dx, lessThanOrEqualTo(layout.center.dx + 0.01));
      expect(center.dy, greaterThanOrEqualTo(layout.center.dy - 0.01));
    }
  });
}

void _expectAllTargetsVisible(RadialAccountQuickSwitcherLayoutSnapshot layout) {
  final centers = [...layout.accountCenters, layout.manageCenter];
  final bounds = layout.targetCenterBounds;
  for (final center in centers) {
    expect(center.dx, greaterThanOrEqualTo(bounds.left - 0.01));
    expect(center.dx, lessThanOrEqualTo(bounds.right + 0.01));
    expect(center.dy, greaterThanOrEqualTo(bounds.top - 0.01));
    expect(center.dy, lessThanOrEqualTo(bounds.bottom + 0.01));
  }

  for (var first = 0; first < centers.length; first++) {
    for (var second = first + 1; second < centers.length; second++) {
      expect(
        (centers[first] - centers[second]).distance,
        greaterThanOrEqualTo(layout.nodeSize - 0.5),
        reason: 'radial targets must not overlap',
      );
    }
  }
}
