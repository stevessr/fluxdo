import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/user/account_switcher_sheet.dart';

void main() {
  test('bottom profile account switcher follows radial mode', () {
    expect(
      AccountSwitcherSheet.shouldUseRadialSwitcher(
        placement: AccountQuickSwitcherPlacement.bottomRight,
        radialEnabled: true,
      ),
      isTrue,
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
    expect(
      AccountSwitcherSheet.shouldUseRadialSwitcher(
        placement: AccountQuickSwitcherPlacement.topRight,
        radialEnabled: true,
      ),
      isTrue,
    );
    expect(
      AccountSwitcherSheet.shouldUseRadialSwitcher(
        placement: AccountQuickSwitcherPlacement.topRight,
        radialEnabled: false,
      ),
      isFalse,
    );
  });
}
