import 'dart:async';
import 'dart:math' as math;

import 'package:app_icons/app_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../pages/account_manage_page.dart';
import '../../providers/account_quick_switcher_preferences.dart';
import '../../providers/app_state_refresher.dart';
import '../../services/account_manager.dart';
import '../../services/toast_service.dart';
import '../../utils/url_helper.dart';
import '../common/smart_avatar.dart';
import 'account_quick_switcher_trigger_state.dart';
import 'account_switch_loading.dart';

/// 触摸长按使用的“伞状”账号切换器。
///
/// 这里的“伞状”不是完整同心圆：触发按钮本身就是圆心，只向屏幕内部展开
/// 约 90° 的多层圆弧。当前账号覆盖在触发按钮圆心；账号管理固定在最外层
/// 专用圆弧正中，其余账号只使用它以内的圆弧，避免管理入口与账号重叠。
abstract final class RadialAccountQuickSwitcher {
  static Future<void> show(
    BuildContext context, {
    required bool fromTop,
    required AccountQuickSwitchTrigger trigger,
    required Future<void> Function() showClassic,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return showClassic();

    final globalAnchor = AccountQuickSwitcherTriggerState.takeAnchor();
    final overlayRenderObject = overlay.context.findRenderObject();
    final overlayBox =
        overlayRenderObject is RenderBox &&
            overlayRenderObject.hasSize &&
            overlayRenderObject.size.width > 0.0 &&
            overlayRenderObject.size.height > 0.0
        ? overlayRenderObject
        : null;
    final anchor = globalAnchor == null || overlayBox == null
        ? globalAnchor
        : overlayBox.globalToLocal(globalAnchor);
    final globalToOverlay = overlayBox == null
        ? (Offset position) => position
        : (Offset position) => overlayBox.globalToLocal(position);
    final completer = Completer<void>();
    final pointerRoute = _RadialPointerRouteController();
    late OverlayEntry entry;

    void removeEntry() {
      pointerRoute.dispose();
      if (entry.mounted) entry.remove();
    }

    void complete() {
      if (!completer.isCompleted) completer.complete();
    }

    entry = OverlayEntry(
      builder: (_) => _RadialAccountQuickSwitcherOverlay(
        hostContext: context,
        fromTop: fromTop,
        anchor: anchor,
        overlaySize: overlayBox?.size,
        globalToOverlay: globalToOverlay,
        trigger: trigger,
        pointerRoute: pointerRoute,
        showClassic: showClassic,
        onRemove: removeEntry,
        onComplete: complete,
      ),
    );
    overlay.insert(entry);
    return completer.future;
  }
}

class _RadialPointerRouteController {
  PointerRoute? _listener;
  PointerEvent? _pendingEvent;
  bool _disposed = false;

  _RadialPointerRouteController() {
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
  }

  void _route(PointerEvent event) {
    if (_disposed) return;
    final listener = _listener;
    if (listener != null) {
      listener(event);
      return;
    }
    if (event is PointerMoveEvent ||
        event is PointerUpEvent ||
        event is PointerCancelEvent) {
      _pendingEvent = event;
    }
  }

  void attach(PointerRoute listener) {
    if (_disposed) return;
    _listener = listener;
    final pending = _pendingEvent;
    _pendingEvent = null;
    if (pending != null) listener(pending);
  }

  void detach(PointerRoute listener) {
    if (_listener == listener) _listener = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _listener = null;
    _pendingEvent = null;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_route);
  }
}

class _RadialAccountQuickSwitcherOverlay extends StatefulWidget {
  const _RadialAccountQuickSwitcherOverlay({
    required this.hostContext,
    required this.fromTop,
    required this.anchor,
    required this.overlaySize,
    required this.globalToOverlay,
    required this.trigger,
    required this.pointerRoute,
    required this.showClassic,
    required this.onRemove,
    required this.onComplete,
  });

  final BuildContext hostContext;
  final bool fromTop;
  final Offset? anchor;
  final Size? overlaySize;
  final Offset Function(Offset) globalToOverlay;
  final AccountQuickSwitchTrigger trigger;
  final _RadialPointerRouteController pointerRoute;
  final Future<void> Function() showClassic;
  final VoidCallback onRemove;
  final VoidCallback onComplete;

  @override
  State<_RadialAccountQuickSwitcherOverlay> createState() =>
      _RadialAccountQuickSwitcherOverlayState();
}

class _RadialAccountQuickSwitcherOverlayState
    extends State<_RadialAccountQuickSwitcherOverlay>
    with TickerProviderStateMixin {
  static const _manageTarget = '__fluxdo_manage_accounts__';
  static const _dwellDuration = Duration(seconds: 5);
  static const _switchCoverMinDuration = Duration(milliseconds: 320);
  final AccountManager _manager = AccountManager();
  late final AnimationController _entryController;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final AnimationController _dwellController;
  late final PointerRoute _pointerListener;
  List<SavedAccount> _accounts = const [];
  String? _currentUsername;
  String? _hoveredTarget;
  Offset? _lastPointerPosition;
  int? _trackingPointer;
  _RadialAccountLayout? _layout;
  bool _loading = true;
  bool _finishing = false;
  bool _fallbackScheduled = false;
  int _dwellGeneration = 0;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
      reverseDuration: const Duration(milliseconds: 125),
    );
    final entryCurve = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    _opacity = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _scale = Tween<double>(begin: 0.72, end: 1.0).animate(entryCurve);
    _dwellController = AnimationController(
      vsync: this,
      duration: _dwellDuration,
    );
    _pointerListener = _handlePointerEvent;
    widget.pointerRoute.attach(_pointerListener);
    unawaited(_entryController.forward());
    unawaited(_reload());
  }

  @override
  void dispose() {
    _dwellGeneration++;
    widget.pointerRoute.detach(_pointerListener);
    widget.pointerRoute.dispose();
    _dwellController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      await _manager.syncCurrentAccount();
      final accountsFuture = _manager.listAccounts();
      final currentFuture = _manager.getCurrentUsername();
      final accounts = await accountsFuture;
      final current = await currentFuture;
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _currentUsername = current;
        _loading = false;
      });
      final pointer = _lastPointerPosition;
      if (pointer != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updateHoveredTarget(pointer, haptic: false);
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _handlePointerEvent(PointerEvent event) {
    if (_finishing) return;
    if (event.kind != PointerDeviceKind.touch) {
      if (_trackingPointer == null &&
          (event is PointerUpEvent || event is PointerCancelEvent)) {
        unawaited(_finish(null, fallbackToClassic: true));
      }
      return;
    }
    if (_trackingPointer == null) {
      if (event is PointerDownEvent) return;
      _trackingPointer = event.pointer;
    }
    if (event.pointer != _trackingPointer) return;
    if (event is PointerMoveEvent) {
      _lastPointerPosition = event.position;
      _updateHoveredTarget(event.position);
      return;
    }
    if (event is PointerUpEvent) {
      _lastPointerPosition = event.position;
      _updateHoveredTarget(event.position, haptic: false);
      if (widget.trigger == AccountQuickSwitchTrigger.release) {
        unawaited(_finish(_hoveredTarget));
      } else {
        unawaited(_finish(null));
      }
      return;
    }
    if (event is PointerCancelEvent) unawaited(_finish(null));
  }

  void _updateHoveredTarget(Offset globalPosition, {bool haptic = true}) {
    if (!mounted || _finishing) return;
    final next = _targetAt(globalPosition);
    if (next == _hoveredTarget) return;
    _cancelDwell(reset: true);
    setState(() => _hoveredTarget = next);
    if (haptic && next != null) unawaited(HapticFeedback.selectionClick());
    if (widget.trigger != AccountQuickSwitchTrigger.dwellFiveSeconds ||
        !_isActionable(next)) {
      return;
    }
    final generation = ++_dwellGeneration;
    unawaited(
      _dwellController.forward(from: 0.0).then((_) {
        if (!mounted ||
            _finishing ||
            generation != _dwellGeneration ||
            _hoveredTarget != next ||
            _dwellController.status != AnimationStatus.completed) {
          return;
        }
        unawaited(HapticFeedback.heavyImpact());
        unawaited(_finish(next));
      }),
    );
  }

  void _cancelDwell({required bool reset}) {
    _dwellGeneration++;
    _dwellController.stop();
    if (reset) _dwellController.value = 0.0;
  }

  bool _isActionable(String? target) {
    if (target == null || target == _currentUsername) return false;
    if (target == _manageTarget) return true;
    return _accountForTarget(target) != null;
  }

  String? _targetAt(Offset globalPosition) {
    final layout = _layout;
    if (layout == null || _loading) return null;
    final localPosition = widget.globalToOverlay(globalPosition);
    final hitRadius = layout.nodeSize / 2.0 + 6.0;
    _RadialTarget? nearest;
    var nearestDistance = double.infinity;
    for (final target in layout.targets) {
      final distance = (localPosition - target.center).distance;
      if (distance <= hitRadius && distance < nearestDistance) {
        nearest = target;
        nearestDistance = distance;
      }
    }
    return nearest?.target;
  }

  SavedAccount? _accountForTarget(String? target) {
    if (target == null || target == _manageTarget) return null;
    for (final account in _accounts) {
      if (account.username == target) return account;
    }
    return null;
  }

  SavedAccount? get _currentAccount {
    final current = _currentUsername;
    if (current == null) return null;
    for (final account in _accounts) {
      if (account.username == current) return account;
    }
    return null;
  }

  Future<void> _finish(String? target, {bool fallbackToClassic = false}) async {
    if (_finishing) return;
    _finishing = true;
    _cancelDwell(reset: false);
    final hostContext = widget.hostContext;
    final remove = widget.onRemove;
    final complete = widget.onComplete;
    final currentUsername = _currentUsername;
    final account = _accountForTarget(target);
    OverlayEntry? switchCover;
    Stopwatch? switchCoverStopwatch;
    if (target != null && !fallbackToClassic) {
      unawaited(HapticFeedback.lightImpact());
    }
    final shouldSwitchAccount =
        !fallbackToClassic &&
        target != _manageTarget &&
        account != null &&
        account.username != currentUsername &&
        hostContext.mounted;
    if (shouldSwitchAccount) {
      final overlay = Overlay.maybeOf(hostContext, rootOverlay: true);
      if (overlay != null) {
        switchCover = OverlayEntry(
          builder: (_) => AccountSwitchLoadingCover(account: account),
        );
        switchCoverStopwatch = Stopwatch()..start();
        overlay.insert(switchCover);
        await WidgetsBinding.instance.endOfFrame;
      }
    }
    try {
      await _entryController.reverse();
    } catch (_) {}
    remove();
    try {
      if (fallbackToClassic) {
        if (hostContext.mounted) await widget.showClassic();
        return;
      }
      if (target == _manageTarget) {
        if (hostContext.mounted) {
          unawaited(
            Navigator.of(hostContext).push(
              MaterialPageRoute(builder: (_) => const AccountManagePage()),
            ),
          );
        }
        return;
      }
      if (account == null || account.username == currentUsername) return;
      if (hostContext.mounted) {
        await _performRadialAccountSwitch(hostContext, _manager, account);
        if (switchCover != null) {
          await WidgetsBinding.instance.endOfFrame;
          final elapsed = switchCoverStopwatch?.elapsed ?? Duration.zero;
          final remaining = _switchCoverMinDuration - elapsed;
          if (remaining > Duration.zero) await Future<void>.delayed(remaining);
        }
      }
    } finally {
      final cover = switchCover;
      if (cover != null) {
        switchCoverStopwatch?.stop();
        if (cover.mounted) cover.remove();
        cover.dispose();
      }
      complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final overlaySize = widget.overlaySize ?? media.size;
    final scheme = Theme.of(context).colorScheme;
    final layout = _RadialAccountLayout.calculate(
      size: overlaySize,
      padding: media.viewPadding,
      fromTop: widget.fromTop,
      anchor: widget.anchor,
      accounts: _accounts,
      currentUsername: _currentUsername,
      manageTarget: _manageTarget,
    );
    _layout = layout;
    if (layout.overflowed && !_loading && !_finishing && !_fallbackScheduled) {
      _fallbackScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _finishing || !(_layout?.overflowed ?? false)) return;
        unawaited(_finish(null, fallbackToClassic: true));
      });
    } else if (!layout.overflowed) {
      _fallbackScheduled = false;
    }
    final alignment = Alignment(
      overlaySize.width <= 0.0
          ? 0.0
          : layout.center.dx / overlaySize.width * 2.0 - 1.0,
      overlaySize.height <= 0.0
          ? 0.0
          : layout.center.dy / overlaySize.height * 2.0 - 1.0,
    );
    final radialBody = FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        alignment: alignment,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _AccountArcPainter(
                  center: layout.center,
                  radii: layout.radii,
                  startAngle: layout.startAngle,
                  sweepAngle: layout.sweepAngle,
                  color: scheme.outlineVariant.withValues(alpha: 0.58),
                ),
              ),
            ),
            _buildCenter(context, layout.center),
            if (_loading)
              Positioned(
                left: layout.center.dx - 10.0,
                top: layout.center.dy - 10.0,
                child: const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              for (final target in layout.targets)
                _buildTarget(context, target, layout.nodeSize),
          ],
        ),
      ),
    );
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(children: [Positioned.fill(child: radialBody)]),
      ),
    );
  }

  Widget _buildCenter(BuildContext context, Offset center) {
    final scheme = Theme.of(context).colorScheme;
    final current = _currentAccount;
    return Positioned(
      left: center.dx - 29.0,
      top: center.dy - 29.0,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surfaceContainerHigh.withValues(alpha: 0.97),
          border: Border.all(color: scheme.primary, width: 2),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.18),
              blurRadius: 12,
            ),
          ],
        ),
        child: Center(
          child: current != null
              ? _RadialAccountAvatar(account: current, radius: 23)
              : Icon(Symbols.person_rounded, size: 28, color: scheme.primary),
        ),
      ),
    );
  }

  Widget _buildTarget(
    BuildContext context,
    _RadialTarget target,
    double nodeSize,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final hovered = _hoveredTarget == target.target;
    final showProgress =
        hovered &&
        widget.trigger == AccountQuickSwitchTrigger.dwellFiveSeconds &&
        _isActionable(target.target);
    final targetChild = target.isManage
        ? Icon(
            Symbols.manage_accounts_rounded,
            size: (nodeSize * 0.5).clamp(20.0, 25.0).toDouble(),
            color: hovered ? scheme.onPrimaryContainer : scheme.primary,
          )
        : _RadialAccountAvatar(
            account: target.account!,
            radius: (nodeSize * 0.4).clamp(15.0, 20.0).toDouble(),
          );
    return Positioned(
      left: target.center.dx - nodeSize / 2.0,
      top: target.center.dy - nodeSize / 2.0,
      child: AnimatedScale(
        scale: hovered ? 1.12 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: nodeSize,
          height: nodeSize,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 110),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hovered
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHigh.withValues(alpha: 0.96),
                  border: Border.all(
                    color: hovered
                        ? scheme.primary.withValues(alpha: 0.55)
                        : scheme.outlineVariant.withValues(alpha: 0.62),
                    width: hovered ? 1.5 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(
                        alpha: hovered ? 0.20 : 0.12,
                      ),
                      blurRadius: hovered ? 14 : 9,
                    ),
                  ],
                ),
                child: Semantics(
                  label: target.isManage
                      ? context.l10n.accountManage_title
                      : target.account!.username,
                  child: Center(child: targetChild),
                ),
              ),
              if (showProgress)
                AnimatedBuilder(
                  animation: _dwellController,
                  builder: (context, _) => CircularProgressIndicator(
                    value: _dwellController.value,
                    strokeWidth: 3,
                    strokeCap: StrokeCap.round,
                    backgroundColor: scheme.primary.withValues(alpha: 0.12),
                    color: scheme.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadialAccountLayout {
  const _RadialAccountLayout({
    required this.center,
    required this.nodeSize,
    required this.targetCenterBounds,
    required this.radii,
    required this.targets,
    required this.startAngle,
    required this.sweepAngle,
    required this.overflowed,
  });

  final Offset center;
  final double nodeSize;
  final Rect targetCenterBounds;
  final List<double> radii;
  final List<_RadialTarget> targets;
  final double startAngle;
  final double sweepAngle;
  final bool overflowed;

  static _RadialAccountLayout calculate({
    required Size size,
    required EdgeInsets padding,
    required bool fromTop,
    required Offset? anchor,
    required List<SavedAccount> accounts,
    required String? currentUsername,
    required String manageTarget,
  }) {
    const outerMargin = 8.0;
    const nodeSize = 50.0;
    const nodeRadius = 25.0;
    const hoveredNodeRadius = nodeRadius * 1.12;
    const preferredInnerRadius = 76.0;
    const preferredRingGap = 64.0;
    const minimumRingGap = 52.0;
    const sweep = math.pi / 2.0;
    final safe = Rect.fromLTRB(
      padding.left + outerMargin,
      padding.top + outerMargin,
      math.max(
        padding.left + outerMargin + 1.0,
        size.width - padding.right - outerMargin,
      ),
      math.max(
        padding.top + outerMargin + 1.0,
        size.height - padding.bottom - outerMargin,
      ),
    );
    final targetCenterBounds = safe.deflate(hoveredNodeRadius + 2.0);
    final rawCenter =
        anchor ??
        Offset(
          safe.right - 26.0,
          fromTop ? safe.top + 34.0 : safe.bottom - 34.0,
        );
    final center = Offset(
      rawCenter.dx.clamp(0.0, size.width).toDouble(),
      rawCenter.dy.clamp(0.0, size.height).toDouble(),
    );

    // Placement is already known by the caller. Do not infer it again from a
    // percentage of the screen: compact/floating navigation bars can place the
    // profile entry well inside that threshold even though it is still the
    // bottom-right trigger.
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

    final geometryBounds = Rect.fromLTRB(
      math.min(targetCenterBounds.left, center.dx),
      math.min(targetCenterBounds.top, center.dy),
      math.max(targetCenterBounds.right, center.dx),
      math.max(targetCenterBounds.bottom, center.dy),
    );
    // The account arcs below are clipped against [targetCenterBounds], so the
    // outer radius only needs to fit along the fan's inward centreline. Taking
    // the minimum of the two cardinal endpoints unnecessarily threw away a
    // large triangular part of the usable area on compact/floating bars.
    final inwardDistance = _distanceToRectEdge(
      center,
      inwardAngle,
      geometryBounds,
    );
    final rawMaxRadius = !inwardDistance.isFinite || inwardDistance <= 0.0
        ? math.min(size.width, size.height) * 0.45
        : inwardDistance;
    final maxRadius = math.max(0.0, rawMaxRadius - 2.0);
    final defaultInnerRadius = math.min(preferredInnerRadius, maxRadius);

    // Slot geometry is derived from the complete saved-account registry. The
    // active account keeps its original slot but is not rendered there, so
    // switching the active account cannot make the remaining targets reflow.
    final slotAccounts = accounts
        .where((account) => account.username != currentUsername)
        .toList(growable: false);

    ({double startAngle, double sweepAngle}) accountArcFor(double radius) =>
        _accountTargetArc(
          center: center,
          rect: targetCenterBounds,
          radius: radius,
          startAngle: startAngle,
          sweepAngle: sweep,
          inwardAngle: inwardAngle,
        );

    int capacityForRing(int ringIndex) => ringIndex * 2 + 3;

    var requiredAccountRingCount = 0;
    var slotsRemaining = slotAccounts.length;
    while (slotsRemaining > 0) {
      slotsRemaining -= capacityForRing(requiredAccountRingCount);
      requiredAccountRingCount++;
    }

    final hasAccounts = slotAccounts.isNotEmpty;
    final maxAccountRadius = hasAccounts
        ? math.max(0.0, maxRadius - minimumRingGap)
        : defaultInnerRadius;
    final accountInnerRadius = math.min(preferredInnerRadius, maxAccountRadius);
    final maxAccountRingCount = !hasAccounts || maxAccountRadius <= 0.0
        ? 0
        : maxAccountRadius <= accountInnerRadius
        ? 1
        : math.max(
            1,
            1 +
                ((maxAccountRadius - accountInnerRadius) / minimumRingGap)
                    .floor(),
          );

    List<double> accountRadiiFor(int count) {
      if (count <= 0) return const <double>[];
      if (count == 1) return <double>[accountInnerRadius];
      final preferredOuter =
          accountInnerRadius + preferredRingGap * (count - 1);
      final outer = math.min(maxAccountRadius, preferredOuter);
      final gap = (outer - accountInnerRadius) / (count - 1);
      return List<double>.generate(
        count,
        (index) => accountInnerRadius + gap * index,
      );
    }

    final accountRingCount = math.min(requiredAccountRingCount, maxAccountRingCount);
    final accountRadii = accountRadiiFor(accountRingCount).toList();
    final overflowed = requiredAccountRingCount > maxAccountRingCount;
    final manageRadius = accountRadii.isEmpty
        ? defaultInnerRadius
        : math.min(maxRadius, accountRadii.last + preferredRingGap);
    final radii = <double>[...accountRadii, manageRadius];
    final targets = <_RadialTarget>[];
    var accountOffset = 0;
    for (var ringIndex = 0; ringIndex < accountRadii.length; ringIndex++) {
      final radius = accountRadii[ringIndex];
      final remaining = slotAccounts.length - accountOffset;
      if (remaining <= 0) break;
      final accountCount = math.min(remaining, capacityForRing(ringIndex));
      final ringAccounts = slotAccounts
          .skip(accountOffset)
          .take(accountCount)
          .toList(growable: false);
      final targetArc = accountArcFor(radius);
      final angles = _accountAngles(
        count: ringAccounts.length,
        startAngle: targetArc.startAngle,
        sweepAngle: targetArc.sweepAngle,
        inwardAngle: inwardAngle,
      );
      for (var i = 0; i < ringAccounts.length; i++) {
        final account = ringAccounts[i];
        if (account.username == currentUsername) continue;
        targets.add(
          _RadialTarget(
            target: account.username,
            center: center + Offset.fromDirection(angles[i], radius),
            account: account,
          ),
        );
      }
      accountOffset += accountCount;
    }
    final manageArc = accountArcFor(manageRadius);
    final manageAngle = manageArc.sweepAngle <= 0.0
        ? inwardAngle
        : inwardAngle
              .clamp(
                manageArc.startAngle,
                manageArc.startAngle + manageArc.sweepAngle,
              )
              .toDouble();
    targets.add(
      _RadialTarget(
        target: manageTarget,
        center: center + Offset.fromDirection(manageAngle, manageRadius),
        isManage: true,
      ),
    );
    return _RadialAccountLayout(
      center: center,
      nodeSize: nodeSize,
      targetCenterBounds: targetCenterBounds,
      radii: radii,
      targets: targets,
      startAngle: startAngle,
      sweepAngle: sweep,
      overflowed: overflowed,
    );
  }

  static ({double startAngle, double sweepAngle}) _accountTargetArc({
    required Offset center,
    required Rect rect,
    required double radius,
    required double startAngle,
    required double sweepAngle,
    required double inwardAngle,
  }) {
    if (radius <= 0.0 || rect.width <= 0.0 || rect.height <= 0.0) {
      return (startAngle: inwardAngle, sweepAngle: 0.0);
    }

    bool fits(double angle) {
      final point = center + Offset.fromDirection(angle, radius);
      const epsilon = 0.01;
      return point.dx >= rect.left - epsilon &&
          point.dx <= rect.right + epsilon &&
          point.dy >= rect.top - epsilon &&
          point.dy <= rect.bottom + epsilon;
    }

    // Intersect the requested quadrant with the actual rectangle of legal node
    // centres. This trims both axes (the former implementation only trimmed the
    // navigation edge, so the vertical endpoint could still sit beyond the
    // right edge). Sampling locates the contiguous interval; bisection then
    // refines its two pixel-safe boundaries.
    const sampleCount = 192;
    final step = sweepAngle / sampleCount;
    var first = -1;
    var last = -1;
    for (var index = 0; index <= sampleCount; index++) {
      if (!fits(startAngle + step * index)) continue;
      if (first < 0) first = index;
      last = index;
    }
    if (first < 0) {
      return (startAngle: inwardAngle, sweepAngle: 0.0);
    }

    var targetStart = startAngle + step * first;
    var targetEnd = startAngle + step * last;
    if (first > 0) {
      var outside = targetStart - step;
      var inside = targetStart;
      for (var iteration = 0; iteration < 24; iteration++) {
        final middle = (outside + inside) / 2.0;
        if (fits(middle)) {
          inside = middle;
        } else {
          outside = middle;
        }
      }
      targetStart = inside;
    }
    if (last < sampleCount) {
      var inside = targetEnd;
      var outside = targetEnd + step;
      for (var iteration = 0; iteration < 24; iteration++) {
        final middle = (inside + outside) / 2.0;
        if (fits(middle)) {
          inside = middle;
        } else {
          outside = middle;
        }
      }
      targetEnd = inside;
    }

    const angularInset = 0.0001;
    targetStart += angularInset;
    targetEnd -= angularInset;
    if (targetEnd <= targetStart) {
      final preferred = inwardAngle
          .clamp(
            math.min(targetStart, targetEnd),
            math.max(targetStart, targetEnd),
          )
          .toDouble();
      return (startAngle: preferred, sweepAngle: 0.0);
    }
    return (startAngle: targetStart, sweepAngle: targetEnd - targetStart);
  }

  static List<double> _accountAngles({
    required int count,
    required double startAngle,
    required double sweepAngle,
    required double inwardAngle,
  }) {
    if (count <= 0) return const <double>[];
    if (count == 1) {
      return <double>[
        inwardAngle.clamp(startAngle, startAngle + sweepAngle).toDouble(),
      ];
    }
    return List<double>.generate(
      count,
      (index) => startAngle + sweepAngle * index / (count - 1),
    );
  }

  static double _distanceToRectEdge(Offset origin, double angle, Rect rect) {
    final dx = math.cos(angle);
    final dy = math.sin(angle);
    final candidates = <double>[];
    void addCandidate(double t) {
      if (!t.isFinite || t <= 0.0) return;
      final point = origin + Offset(dx * t, dy * t);
      const epsilon = 0.5;
      if (point.dx >= rect.left - epsilon &&
          point.dx <= rect.right + epsilon &&
          point.dy >= rect.top - epsilon &&
          point.dy <= rect.bottom + epsilon) {
        candidates.add(t);
      }
    }

    if (dx.abs() > 1e-6) {
      addCandidate((rect.left - origin.dx) / dx);
      addCandidate((rect.right - origin.dx) / dx);
    }
    if (dy.abs() > 1e-6) {
      addCandidate((rect.top - origin.dy) / dy);
      addCandidate((rect.bottom - origin.dy) / dy);
    }
    if (candidates.isEmpty) return double.infinity;
    return candidates.reduce((a, b) => math.min(a, b));
  }
}

/// Geometry snapshot used by regression tests for the edge-constrained fan.
@immutable
class RadialAccountQuickSwitcherLayoutSnapshot {
  const RadialAccountQuickSwitcherLayoutSnapshot({
    required this.center,
    required this.nodeSize,
    required this.targetCenterBounds,
    required this.accountCenters,
    required this.manageCenter,
    required this.overflowed,
  });

  final Offset center;
  final double nodeSize;
  final Rect targetCenterBounds;
  final List<Offset> accountCenters;
  final Offset manageCenter;
  final bool overflowed;
}

@visibleForTesting
RadialAccountQuickSwitcherLayoutSnapshot
calculateRadialAccountQuickSwitcherLayoutForTest({
  required Size size,
  required EdgeInsets padding,
  required Offset anchor,
  required int switchableAccountCount,
  bool fromTop = false,
}) {
  assert(switchableAccountCount >= 0);
  final savedAt = DateTime.fromMillisecondsSinceEpoch(0);
  final accounts = <SavedAccount>[
    SavedAccount(username: 'current', savedAt: savedAt),
    for (var index = 0; index < switchableAccountCount; index++)
      SavedAccount(username: 'account-$index', savedAt: savedAt),
  ];
  final layout = _RadialAccountLayout.calculate(
    size: size,
    padding: padding,
    fromTop: fromTop,
    anchor: anchor,
    accounts: accounts,
    currentUsername: 'current',
    manageTarget: '__test_manage__',
  );
  final manageTarget = layout.targets.firstWhere((target) => target.isManage);
  return RadialAccountQuickSwitcherLayoutSnapshot(
    center: layout.center,
    nodeSize: layout.nodeSize,
    targetCenterBounds: layout.targetCenterBounds,
    accountCenters: [
      for (final target in layout.targets)
        if (!target.isManage) target.center,
    ],
    manageCenter: manageTarget.center,
    overflowed: layout.overflowed,
  );
}

class _RadialTarget {
  const _RadialTarget({
    required this.target,
    required this.center,
    this.account,
    this.isManage = false,
  });
  final String target;
  final Offset center;
  final SavedAccount? account;
  final bool isManage;
}

class _AccountArcPainter extends CustomPainter {
  const _AccountArcPainter({
    required this.center,
    required this.radii,
    required this.startAngle,
    required this.sweepAngle,
    required this.color,
  });
  final Offset center;
  final List<double> radii;
  final double startAngle;
  final double sweepAngle;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (final radius in radii) {
      if (radius <= 0.0) continue;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AccountArcPainter oldDelegate) {
    if (oldDelegate.center != center ||
        oldDelegate.color != color ||
        oldDelegate.startAngle != startAngle ||
        oldDelegate.sweepAngle != sweepAngle ||
        oldDelegate.radii.length != radii.length) {
      return true;
    }
    for (var i = 0; i < radii.length; i++) {
      if (oldDelegate.radii[i] != radii[i]) return true;
    }
    return false;
  }
}

Future<bool> _performRadialAccountSwitch(
  BuildContext context,
  AccountManager manager,
  SavedAccount account,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await manager.switchToAccount(account.username);
    await AppStateRefresher.resetForAccountSwitch(container);
    if (context.mounted) {
      ToastService.showSuccess(context.l10n.accountManage_switchDone);
    }
    return true;
  } on AccountSessionExpiredException {
    if (context.mounted) {
      ToastService.showError(
        context.l10n.accountManage_sessionExpired(account.username),
      );
    }
    return false;
  } catch (_) {
    if (context.mounted) {
      ToastService.showError(context.l10n.accountManage_switchFailed);
    }
    return false;
  }
}

class _RadialAccountAvatar extends StatelessWidget {
  const _RadialAccountAvatar({required this.account, required this.radius});
  final SavedAccount account;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final template = account.avatarTemplate;
    final imageUrl = template != null && template.isNotEmpty
        ? UrlHelper.resolveUrlWithCdn(template.replaceAll('{size}', '96'))
        : null;
    return SmartAvatar(
      imageUrl: imageUrl,
      radius: radius,
      fallbackText: account.username,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}
