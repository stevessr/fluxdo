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

/// 触摸长按使用的多环“伞状”账号切换器。
///
/// 圆心固定显示当前账号；其它账号会按数量与 SafeArea 自动分配到一层或
/// 多层圆环；账号管理入口固定在最外环朝屏幕内部的一侧正中。
abstract final class RadialAccountQuickSwitcher {
  static Future<void> show(
    BuildContext context, {
    required bool fromTop,
    required AccountQuickSwitchTrigger trigger,
    required Future<void> Function() showClassic,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return showClassic();

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
    required this.trigger,
    required this.pointerRoute,
    required this.showClassic,
    required this.onRemove,
    required this.onComplete,
  });

  final BuildContext hostContext;
  final bool fromTop;
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
    _scale = Tween<double>(begin: 0.82, end: 1.0).animate(entryCurve);
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
      // 与经典快速切换器一致：先把当前 session 固化，保证切走后能切回来。
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

    // 移动设备也可能接鼠标。真正由非触摸设备触发时回退经典 bottom sheet。
    if (event.kind != PointerDeviceKind.touch) {
      if (_trackingPointer == null &&
          (event is PointerUpEvent || event is PointerCancelEvent)) {
        unawaited(_finish(null, fallbackToClassic: true));
      }
      return;
    }

    // Overlay 是在长按已成立后才插入，因此当前序列不会再收到 PointerDown；
    // 第一条 move/up/cancel 就是原长按手指。之后的 PointerDown 属于第二根手指。
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
        // 5 秒模式只有进度走满才执行；提前松手明确视为取消。
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
      // 宿主同步销毁 Overlay 时 controller 可能已经不可用，继续清理即可。
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
                painter: _AccountRingPainter(
                  center: layout.center,
                  radii: layout.radii,
                  color: scheme.outlineVariant.withValues(alpha: 0.55),
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

    // 原 pointer 仍沿原 hit-test route 派发；这里只绘制，不加 ModalBarrier，
    // 从而不会再次出现背景多渲染一层“切换选项框”的问题。
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

/// 纯几何布局：先由可视区域得出最多能放多少层，再根据账号数量选择“足够
/// 容纳目标的最少层数”。这样账号少时不会铺满屏幕，账号多时才逐层扩展。
class _RadialAccountLayout {
  const _RadialAccountLayout({
    required this.center,
    required this.radii,
    required this.targets,
  });

  final Offset center;
  final List<double> radii;
  final List<_RadialTarget> targets;

  static _RadialAccountLayout calculate({
    required Size size,
    required EdgeInsets padding,
    required bool fromTop,
    required List<SavedAccount> accounts,
    required String? currentUsername,
    required String manageTarget,
  }) {
    const outerMargin = 12.0;
    const nodeRadius = 25.0;
    const centerAndNodePadding = 4.0;
    const preferredInnerRadius = 68.0;
    const preferredRingGap = 64.0;
    const minimumRingGap = 52.0;
    const preferredNodePitch = 58.0;

    final left = padding.left + outerMargin;
    final top = padding.top + outerMargin;
    final right = math.max(left + 1.0, size.width - padding.right - outerMargin);
    final bottom = math.max(top + 1.0, size.height - padding.bottom - outerMargin);
    final safe = Rect.fromLTRB(left, top, right, bottom);

    // 节点自身也占半径，所以圆环最大半径必须先扣除节点半径与少量留白。
    final halfMinExtent = math.min(safe.width, safe.height) / 2.0;
    final maxRingRadius = math.max(
      0.0,
      halfMinExtent - nodeRadius - centerAndNodePadding,
    );
    final innerRingRadius = math.min(preferredInnerRadius, maxRingRadius);

    final switchable = accounts
        .where((account) => account.username != currentUsername)
        .toList(growable: false);
    final itemCount = switchable.length + 1; // 最外环还要留账号管理入口。

    int capacityFor(double radius) {
      if (radius <= 0.0) return 4;
      return math.max(
        4,
        (2.0 * math.pi * radius / preferredNodePitch).floor(),
      );
    }

    final maxRingCount = maxRingRadius <= innerRingRadius
        ? 1
        : math.max(
            1,
            1 +
                ((maxRingRadius - innerRingRadius) / minimumRingGap).floor(),
          );

    List<double> radiiFor(int count) {
      if (count <= 1) return <double>[innerRingRadius];
      final preferredOuter =
          innerRingRadius + preferredRingGap * (count - 1);
      final outer = math.min(maxRingRadius, preferredOuter);
      final gap = (outer - innerRingRadius) / (count - 1);
      return List<double>.generate(
        count,
        (index) => innerRingRadius + gap * index,
      );
    }

    int totalCapacity(List<double> radii) {
      var total = 0;
      for (var i = 0; i < radii.length; i++) {
        final reserveForManage = i == radii.length - 1 ? 1 : 0;
        total += math.max(0, capacityFor(radii[i]) - reserveForManage);
      }
      return total;
    }

    var ringCount = 1;
    while (ringCount < maxRingCount &&
        totalCapacity(radiiFor(ringCount)) < itemCount - 1) {
      ringCount++;
    }
    final radii = radiiFor(ringCount);

    final diskRadius = radii.last + nodeRadius + centerAndNodePadding;
    final preferredCenter = Offset(
      safe.right - diskRadius,
      fromTop ? safe.top + diskRadius : safe.bottom - diskRadius,
    );

    double fitAxis(double preferred, double minValue, double maxValue, double fallback) {
      if (minValue > maxValue) return fallback;
      return preferred.clamp(minValue, maxValue).toDouble();
    }

    final center = Offset(
      fitAxis(
        preferredCenter.dx,
        safe.left + diskRadius,
        safe.right - diskRadius,
        safe.center.dx,
      ),
      fitAxis(
        preferredCenter.dy,
        safe.top + diskRadius,
        safe.bottom - diskRadius,
        safe.center.dy,
      ),
    );

    final targets = <_RadialTarget>[];
    var accountOffset = 0;

    for (var ringIndex = 0; ringIndex < radii.length; ringIndex++) {
      final radius = radii[ringIndex];
      final isOuter = ringIndex == radii.length - 1;
      final reserveForManage = isOuter ? 1 : 0;
      final remaining = switchable.length - accountOffset;
      final accountCount = math.min(
        remaining,
        math.max(0, capacityFor(radius) - reserveForManage),
      );

      if (isOuter) {
        final manageAngle = fromTop ? math.pi / 2.0 : -math.pi / 2.0;
        final slotCount = math.max(1, accountCount + 1);
        targets.add(
          _RadialTarget(
            target: manageTarget,
            center: center + Offset.fromDirection(manageAngle, radius),
            isManage: true,
          ),
        );
        for (var i = 0; i < accountCount; i++) {
          final angle = manageAngle + 2.0 * math.pi * (i + 1) / slotCount;
          final account = switchable[accountOffset + i];
          targets.add(
            _RadialTarget(
              target: account.username,
              center: center + Offset.fromDirection(angle, radius),
              account: account,
            ),
          );
        }
      } else if (accountCount > 0) {
        final angleOffset = -math.pi / 2.0 + math.pi / accountCount;
        for (var i = 0; i < accountCount; i++) {
          final angle = angleOffset + 2.0 * math.pi * i / accountCount;
          final account = switchable[accountOffset + i];
          targets.add(
            _RadialTarget(
              target: account.username,
              center: center + Offset.fromDirection(angle, radius),
              account: account,
            ),
          );
        }
      }
      accountOffset += accountCount;
    }

    // 极端账号数量超过当前可视区域的舒适容量时不静默丢账号：把最外环
    // 重新均匀分配为“原外环账号 + 余项 + 管理”。会更密，但仍然全部可达。
    if (accountOffset < switchable.length) {
      final outerRadius = radii.last;
      final outerAccounts = <SavedAccount>[];
      final keptTargets = <_RadialTarget>[];
      for (final target in targets) {
        final isOnOuter =
            ((target.center - center).distance - outerRadius).abs() < 0.5;
        if (isOnOuter) {
          if (!target.isManage && target.account != null) {
            outerAccounts.add(target.account!);
          }
        } else {
          keptTargets.add(target);
        }
      }
      outerAccounts.addAll(switchable.skip(accountOffset));

      final manageAngle = fromTop ? math.pi / 2.0 : -math.pi / 2.0;
      final slotCount = outerAccounts.length + 1;
      keptTargets.add(
        _RadialTarget(
          target: manageTarget,
          center: center + Offset.fromDirection(manageAngle, outerRadius),
          isManage: true,
        ),
      );
      for (var i = 0; i < outerAccounts.length; i++) {
        final angle = manageAngle + 2.0 * math.pi * (i + 1) / slotCount;
        final account = outerAccounts[i];
        keptTargets.add(
          _RadialTarget(
            target: account.username,
            center: center + Offset.fromDirection(angle, outerRadius),
            account: account,
          ),
        );
      }
      return _RadialAccountLayout(
        center: center,
        radii: radii,
        targets: keptTargets,
      );
    }

    return _RadialAccountLayout(center: center, radii: radii, targets: targets);
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

class _AccountRingPainter extends CustomPainter {
  const _AccountRingPainter({
    required this.center,
    required this.radii,
    required this.color,
  });

  final Offset center;
  final List<double> radii;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (final radius in radii) {
      if (radius > 0.0) canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AccountRingPainter oldDelegate) {
    if (oldDelegate.center != center || oldDelegate.color != color) return true;
    if (oldDelegate.radii.length != radii.length) return true;
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
