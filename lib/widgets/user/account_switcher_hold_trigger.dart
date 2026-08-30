import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/account_quick_switcher_preferences.dart';
import 'account_quick_switcher_trigger_state.dart';

/// Long-press recognizer used by the mobile account-switch entry.
///
/// The classic switcher keeps Flutter's normal long-press behavior. Radial mode
/// replaces it with a configurable recognizer whose progress is visible from
/// pointer-down and whose haptics get progressively stronger toward completion.
class AccountSwitcherHoldTrigger extends ConsumerStatefulWidget {
  const AccountSwitcherHoldTrigger({
    super.key,
    required this.child,
    required this.onLongPress,
  });

  final Widget child;
  final VoidCallback onLongPress;

  @override
  ConsumerState<AccountSwitcherHoldTrigger> createState() =>
      _AccountSwitcherHoldTriggerState();
}

class _AccountSwitcherHoldTriggerState
    extends ConsumerState<AccountSwitcherHoldTrigger>
    with SingleTickerProviderStateMixin {
  static const _progressDiameter = 34.0;

  late final AnimationController _progressController;

  bool _holding = false;
  bool _accepted = false;
  bool _manuallyCancelled = false;
  int _hapticStage = 0;
  int? _pointer;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..addListener(_handleProgressHaptics);
  }

  @override
  void dispose() {
    _progressController
      ..removeListener(_handleProgressHaptics)
      ..dispose();
    super.dispose();
  }

  void _handleDown(LongPressDownDetails details) {
    final duration = ref.read(accountQuickSwitcherPreferencesProvider).holdDuration;
    _progressController.duration = duration;
    _accepted = false;
    _manuallyCancelled = false;
    _hapticStage = 0;
    if (mounted) setState(() => _holding = true);
    _progressController.forward(from: 0.0);
  }

  void _handleCancel() {
    AccountQuickSwitcherTriggerState.clear();
    _manuallyCancelled = true;
    _resetHold();
  }

  void _handleStart(LongPressStartDetails details) {
    if (_accepted || _manuallyCancelled) return;
    _accepted = true;
    _progressController.value = 1.0;

    AccountQuickSwitcherTriggerState.setAnchor(
      _resolveNavigationItemAnchor(details.globalPosition),
    );

    unawaited(HapticFeedback.heavyImpact());
    widget.onLongPress();
  }

  /// The recognizer is intentionally wrapped around the icon so the progress
  /// ring does not disturb NavigationBar layout. Using that icon's RenderBox as
  /// the radial origin, however, makes the bottom-right profile entry visibly
  /// too high whenever the destination also has a label (and in the floating
  /// capsule layout). Walk upward through render ancestors and use the largest
  /// plausible navigation-item box containing the finger instead.
  Offset _resolveNavigationItemAnchor(Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return globalPosition;
    }

    final viewSize = MediaQuery.sizeOf(context);
    final maxTargetWidth = math.min(160.0, viewSize.width * 0.5);
    RenderBox? best;
    RenderObject? current = renderObject;

    while (current != null) {
      if (current is RenderBox && current.hasSize) {
        final size = current.size;
        if (size.width >= 44.0 &&
            size.height >= 40.0 &&
            size.width <= maxTargetWidth &&
            size.height <= 96.0) {
          final rect = current.localToGlobal(Offset.zero) & size;
          if (rect.inflate(1.0).contains(globalPosition)) {
            best = current;
          }
        }
      }
      final parent = current.parent;
      current = parent is RenderObject ? parent : null;
    }

    final target = best ?? renderObject;
    return target.localToGlobal(target.size.center(Offset.zero));
  }

  void _handleEnd(LongPressEndDetails details) {
    _pointer = null;
    _resetHold();
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointer = event.pointer;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_accepted || _manuallyCancelled || event.pointer != _pointer) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final local = renderObject.globalToLocal(event.position);
    final size = renderObject.size;
    final activeRect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: math.max(size.width, _progressDiameter),
      height: math.max(size.height, _progressDiameter),
    );
    if (activeRect.contains(local)) return;

    // Before recognition, leaving the visible trigger cancels charging. Once
    // accepted we intentionally stop doing this so the same finger can slide
    // outward onto an account target.
    _manuallyCancelled = true;
    AccountQuickSwitcherTriggerState.clear();
    _resetHold();
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    if (!_accepted) AccountQuickSwitcherTriggerState.clear();
    _resetHold();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    AccountQuickSwitcherTriggerState.clear();
    _manuallyCancelled = true;
    _resetHold();
  }

  void _resetHold() {
    _progressController.stop();
    _progressController.value = 0.0;
    _hapticStage = 0;
    if (mounted && _holding) setState(() => _holding = false);
  }

  void _handleProgressHaptics() {
    if (!_holding || _accepted || _manuallyCancelled) return;
    final value = _progressController.value;

    final nextStage = switch (value) {
      >= 0.94 => 5,
      >= 0.84 => 4,
      >= 0.68 => 3,
      >= 0.45 => 2,
      >= 0.20 => 1,
      _ => 0,
    };
    if (nextStage <= _hapticStage) return;
    _hapticStage = nextStage;

    switch (nextStage) {
      case 1:
        unawaited(HapticFeedback.selectionClick());
        break;
      case 2:
        unawaited(HapticFeedback.lightImpact());
        break;
      case 3:
      case 4:
        unawaited(HapticFeedback.mediumImpact());
        break;
      case 5:
        unawaited(HapticFeedback.heavyImpact());
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(accountQuickSwitcherPreferencesProvider);

    if (!preferences.radialEnabled) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: widget.onLongPress,
        child: widget.child,
      );
    }

    final duration = preferences.holdDuration;
    final scheme = Theme.of(context).colorScheme;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: RawGestureDetector(
        key: ValueKey<int>(duration.inMilliseconds),
        behavior: HitTestBehavior.translucent,
        gestures: <Type, GestureRecognizerFactory>{
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(duration: duration),
                (recognizer) {
                  recognizer
                    ..onLongPressDown = _handleDown
                    ..onLongPressStart = _handleStart
                    ..onLongPressCancel = _handleCancel
                    ..onLongPressEnd = _handleEnd;
                },
              ),
        },
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            widget.child,
            if (_holding)
              Positioned(
                width: _progressDiameter,
                height: _progressDiameter,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _progressController,
                    builder: (context, _) => CircularProgressIndicator(
                      value: _progressController.value,
                      strokeWidth: 2.4,
                      strokeCap: StrokeCap.round,
                      backgroundColor: scheme.primary.withValues(alpha: 0.10),
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
