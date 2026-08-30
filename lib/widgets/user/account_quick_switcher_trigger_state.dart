import 'package:flutter/widgets.dart';

/// Bridges the navigation long-press target and the account switcher overlay.
///
/// [AccountSwitcherSheet.show] is intentionally still a parameterless callback at
/// its existing call sites. The configurable long-press wrapper records the real
/// trigger button center immediately before invoking that callback, and the
/// radial overlay consumes it on the same event turn.
abstract final class AccountQuickSwitcherTriggerState {
  static Offset? _pendingAnchor;

  static void setAnchor(Offset anchor) {
    _pendingAnchor = anchor;
  }

  static Offset? takeAnchor() {
    final anchor = _pendingAnchor;
    _pendingAnchor = null;
    return anchor;
  }

  static void clear() {
    _pendingAnchor = null;
  }
}
