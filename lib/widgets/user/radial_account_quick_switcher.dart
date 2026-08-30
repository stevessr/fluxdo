import 'dart:async';
import 'dart:math' as math;

import 'package:app_icons/app_icons.dart';
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

    // 手机底栏的可调长按识别器会在调用 AccountSwitcherSheet.show 的同一
    // 事件轮次写入真实按钮中心。没有记录时（例如其它旧入口）再按边缘位置
    // 兜底，但绝不把真实圆心强行搬到屏幕内部。
    final anchor = AccountQuickSwitcherTriggerState.takeAnchor();
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

/// Overlay 插入前先接住当前长按 pointer 的后续事件，避免 PointerUp 刚好落在
/// Overlay 创建的帧间隙里而留下悬浮层。
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
    required this.trigger,
    required this.pointerRoute,
    required this.showClassic,
    required this.onRemove,
    required this.onComplete,
  });

  final BuildContext hostContext;
  final bool fromTop;
  final Offset? anchor;
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
  static const _nodeSize = 50.0;
  static const _hitRadius = 31.0;

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
    _dwellController = AnimationController(vsync: this, duration: _dwellDuration);
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

    // Overlay 在长按已经成立后插入，因此当前手指不会再发 PointerDown。
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
        // 5 秒停留模式只有目标进度走满才执行，提前松手就是取消。
        unawaited(_finish(null));
      }
      return;
    }

    if (event is PointerCancelEvent) {
      unawaited(_finish(null));
    }
  }

  void _updateHoveredTarget(Offset globalPosition, {bool haptic = true}) {
    if (!mounted || _finishing) return;
    final next = _targetAt(globalPosition);
    if (next == _hoveredTarget) return;

    _cancelDwell(reset: true);
    setState(() => _hoveredTarget = next);

    if (haptic && next != null) {
      unawaited(HapticFeedback.selectionClick());
    }

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

    _RadialTarget? nearest;
    var nearestDistance = double.infinity;
    for (final target in layout.targets) {
      final distance = (globalPosition - target.center).distance;
      if (distance <= _hitRadius && distance < nearestDistance) {
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

  Future<void> _finish(
    String? target, {
    bool fallbackToClassic = false,
  }) async {
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
          builder: (_) => _RadialAccountSwitchCover(account: account),
        );
        switchCoverStopwatch = Stopwatch()..start();
        overlay.insert(switchCover);
        await WidgetsBinding.instance.endOfFrame;
      }
    }

    try {
      await _entryController.reverse();
    } catch (_) {
      // 宿主同步销毁 Overlay 时继续清理即可。
    }
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
          if (remaining > Duration.zero) {
            await Future<void>.delayed(remaining);
          }
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
    final scheme = Theme.of(context).colorScheme;
    final layout = _RadialAccountLayout.calculate(
      size: media.size,
      padding: media.padding,
      fromTop: widget.fromTop,
      anchor: widget.anchor,
      accounts: _accounts,
      currentUsername: _currentUsername,
      manageTarget: _manageTarget,
    );
    _layout = layout;

    final alignment = Alignment(
      media.size.width <= 0.0
          ? 0.0
          : layout.center.dx / media.size.width * 2.0 - 1.0,
      media.size.height <= 0.0
          ? 0.0
          : layout.center.dy / media.size.height * 2.0 - 1.0,
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
                _buildTarget(context, target),
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
              : Icon(
                  Symbols.person_rounded,
                  size: 28,
                  color: scheme.primary,
                ),
        ),
      ),
    );
  }

  Widget _buildTarget(BuildContext context, _RadialTarget target) {
    final scheme = Theme.of(context).colorScheme;
    final hovered = _hoveredTarget == target.target;
    final showProgress =
        hovered &&
        widget.trigger == AccountQuickSwitchTrigger.dwellFiveSeconds &&
        _isActionable(target.target);

    final targetChild = target.isManage
        ? Icon(
            Symbols.manage_accounts_rounded,
            size: 25,
            color: hovered ? scheme.onPrimaryContainer : scheme.primary,
          )
        : _RadialAccountAvatar(account: target.account!, radius: 20);

    return Positioned(
      left: target.center.dx - _nodeSize / 2.0,
      top: target.center.dy - _nodeSize / 2.0,
      child: AnimatedScale(
        scale: hovered ? 1.12 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: _nodeSize,
          height: _nodeSize,
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

/// 边缘扇形布局。触发按钮就是 [center]，只计算朝屏幕内部的 90° 圆弧。
class _RadialAccountLayout {
  const _RadialAccountLayout({
    required this.center,
    required this.radii,
    required this.targets,
    required this.startAngle,
    required this.sweepAngle,
  });

  final Offset center;
  final List<double> radii;
  final List<_RadialTarget> targets;
  final double startAngle;
  final double sweepAngle;

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
    const nodeRadius = 25.0;
    const preferredInnerRadius = 76.0;
    const preferredRingGap = 64.0;
    const minimumRingGap = 52.0;
    const preferredNodePitch = 58.0;
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

    // 真正的触发中心优先；旧入口没有上报 anchor 时才贴右上/右下兜底。
    final center = anchor ??
        Offset(
          safe.right - 26.0,
          fromTop ? safe.top + 34.0 : safe.bottom - 34.0,
        );

    // 扇形方向由最近屏幕边/角决定，而不是由“按钮→屏幕中心”向量决定。
    // 竖屏右下按钮若指向屏幕中心，中轴会严重偏上，90° 弧的一端甚至
    // 继续朝右出屏；按边缘内法线则右下角稳定得到 left↔up 的四分之一圆。
    final inwardAngle = _inwardAngleForEdge(center, safe);
    final startAngle = inwardAngle - sweep / 2.0;

    // 取扇形左边界/中轴/右边界三条射线中最早撞到可视边界的一条，
    // 保证每层圆弧两端的头像都不会被切出屏幕。
    final rayDistances = <double>[
      _distanceToRectEdge(center, startAngle, safe),
      _distanceToRectEdge(center, inwardAngle, safe),
      _distanceToRectEdge(center, startAngle + sweep, safe),
    ].where((value) => value.isFinite && value > 0.0).toList();
    final rawMaxRadius = rayDistances.isEmpty
        ? math.min(size.width, size.height) * 0.45
        : rayDistances.reduce((a, b) => math.min(a, b));
    final maxRadius = math.max(48.0, rawMaxRadius - nodeRadius - 6.0);
    final defaultInnerRadius = math.min(preferredInnerRadius, maxRadius);

    final switchable = accounts
        .where((account) => account.username != currentUsername)
        .toList(growable: false);

    int capacityFor(double radius) {
      if (radius <= 0.0) return 1;
      // 圆弧长度 / 舒适头像间距，再加一个端点槽位。
      return math.max(2, (radius * sweep / preferredNodePitch).floor() + 1);
    }

    // “管理”永远使用账号之外的最外层圆弧。先从可用半径里预留至少一层
    // 的径向间距，再在剩余区域布置账号。这样账号再多也不会被最后一层
    // 的兜底逻辑硬塞到管理节点附近。
    final hasAccounts = switchable.isNotEmpty;
    final maxAccountRadius = hasAccounts
        ? math.max(48.0, maxRadius - minimumRingGap)
        : defaultInnerRadius;
    final accountInnerRadius = math.min(
      preferredInnerRadius,
      maxAccountRadius,
    );

    final maxAccountRingCount = !hasAccounts || maxAccountRadius <= accountInnerRadius
        ? (hasAccounts ? 1 : 0)
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

    int comfortableAccountCapacity(List<double> radii) {
      var total = 0;
      for (final radius in radii) {
        total += capacityFor(radius);
      }
      return total;
    }

    var accountRingCount = hasAccounts ? 1 : 0;
    while (accountRingCount < maxAccountRingCount &&
        comfortableAccountCapacity(accountRadiiFor(accountRingCount)) <
            switchable.length) {
      accountRingCount++;
    }

    final accountRadii = accountRadiiFor(accountRingCount).toList();

    // 极端账号数量下宁可继续新增账号环并把管理环向外推，也绝不把剩余账号
    // 全塞到最后一环造成头像与“管理”重叠。正常手机尺寸下不会越过 maxRadius；
    // 此兜底只处理账号数量超过可视舒适容量的情况。
    while (hasAccounts &&
        comfortableAccountCapacity(accountRadii) < switchable.length) {
      final nextRadius = accountRadii.isEmpty
          ? accountInnerRadius
          : accountRadii.last + minimumRingGap;
      accountRadii.add(nextRadius);
    }

    final manageRadius = accountRadii.isEmpty
        ? defaultInnerRadius
        : math.max(
            accountRadii.last + minimumRingGap,
            math.min(maxRadius, accountRadii.last + preferredRingGap),
          );
    final radii = <double>[...accountRadii, manageRadius];

    final targets = <_RadialTarget>[];
    var accountOffset = 0;
    for (final radius in accountRadii) {
      final remaining = switchable.length - accountOffset;
      if (remaining <= 0) break;
      final accountCount = math.min(remaining, capacityFor(radius));
      final ringAccounts = switchable
          .skip(accountOffset)
          .take(accountCount)
          .toList(growable: false);
      final angles = _accountAngles(
        count: ringAccounts.length,
        startAngle: startAngle,
        sweepAngle: sweep,
        inwardAngle: inwardAngle,
      );

      for (var i = 0; i < ringAccounts.length; i++) {
        final account = ringAccounts[i];
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

    // 管理入口独占最外层中轴。账号环不再为它“留一个角度槽”，而是与其
    // 保持至少 minimumRingGap 的径向距离，因此不会发生径向/角向重叠。
    targets.add(
      _RadialTarget(
        target: manageTarget,
        center: center + Offset.fromDirection(inwardAngle, manageRadius),
        isManage: true,
      ),
    );

    return _RadialAccountLayout(
      center: center,
      radii: radii,
      targets: targets,
      startAngle: startAngle,
      sweepAngle: sweep,
    );
  }

  static double _inwardAngleForEdge(Offset center, Rect rect) {
    final leftDistance = (center.dx - rect.left).abs();
    final rightDistance = (rect.right - center.dx).abs();
    final topDistance = (center.dy - rect.top).abs();
    final bottomDistance = (rect.bottom - center.dy).abs();
    final horizontalDistance = math.min(leftDistance, rightDistance);
    final verticalDistance = math.min(topDistance, bottomDistance);

    // 靠近两个边时按角处理。84dp 足够覆盖底栏最外侧槽位，又不会把
    // 底边中间的按钮误判成角落。
    const cornerBand = 84.0;
    if (horizontalDistance <= cornerBand && verticalDistance <= cornerBand) {
      final dx = leftDistance <= rightDistance ? 1.0 : -1.0;
      final dy = topDistance <= bottomDistance ? 1.0 : -1.0;
      return math.atan2(dy, dx);
    }

    if (verticalDistance <= horizontalDistance) {
      return topDistance <= bottomDistance ? math.pi / 2.0 : -math.pi / 2.0;
    }
    return leftDistance <= rightDistance ? 0.0 : math.pi;
  }

  static List<double> _accountAngles({
    required int count,
    required double startAngle,
    required double sweepAngle,
    required double inwardAngle,
  }) {
    if (count <= 0) return const <double>[];
    if (count == 1) return <double>[inwardAngle];
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

class _RadialAccountSwitchCover extends StatelessWidget {
  const _RadialAccountSwitchCover({required this.account});

  final SavedAccount account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Material(
          color: scheme.surface.withValues(alpha: 0.96),
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RadialAccountAvatar(account: account, radius: 30),
                  const SizedBox(height: 20),
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.6),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.accountManage_switching,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '@${account.username}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
