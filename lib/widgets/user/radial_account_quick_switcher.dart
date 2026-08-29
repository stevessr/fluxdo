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

/// 多环“伞状”账号切换器。
///
/// 这个组件只负责触摸长按后的 overlay。账号数量增多时会根据 SafeArea
/// 可以容纳的最大圆盘半径自动增加环数；当前账号固定在圆心，账号管理固定
/// 在最外环朝向屏幕内部的一侧正中。
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
    final curve = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    _opacity = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _scale = Tween<double>(begin: 0.82, end: 1).animate(curve);
    _dwellController = AnimationController(vsync: this, duration: _dwellDuration);
    _pointerListener = _handlePointerEvent;
    widget.pointerRoute.attach(_pointerListener);
    unawaited(_entryController.forward());
    unawaited(_reload());
  }

  @override
  void dispose() {
    _dwellGeneration++;
    _dwellController.dispose();
    widget.pointerRoute.detach(_pointerListener);
    widget.pointerRoute.dispose();
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
      final pointerPosition = _lastPointerPosition;
      if (pointerPosition != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updateHoveredTarget(pointerPosition, haptic: false);
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _handlePointerEvent(PointerEvent event) {
    if (_finishing) return;

    // 外接鼠标触发时仍回退到经典面板，避免把依赖持续触摸 pointer 的交互
    // 强行套在桌面设备上。
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
        // 5 秒停留模式下，提前松手就是取消；只有进度走满才会执行。
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
      _dwellController.forward(from: 0).then((_) {
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
    if (reset) _dwellController.value = 0;
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
      // 宿主同步销毁 overlay 时仍继续收口。
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

    final radialBody = FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        alignment: Alignment(
          media.size.width == 0 ? 0 : layout.center.dx / media.size.width * 2 - 1,
          media.size.height == 0 ? 0 : layout.center.dy / media.size.height * 2 - 1,
        ),
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
                left: layout.center.dx - 10,
                top: layout.center.dy - 10,
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

    // 与旧快捷切换器保持一致：overlay 只绘制，原长按 pointer 继续通过全局
    // pointer route 跟踪，不额外制造 ModalBarrier 或第二个手势竞争者。
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
      left: center.dx - 29,
      top: center.dy - 29,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surfaceContainerHigh.withValues(alpha: 0.96),
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

    final child = target.isManage
        ? Icon(
            Symbols.manage_accounts_rounded,
            size: 25,
            color: hovered ? scheme.onPrimaryContainer : scheme.primary,
          )
        : _RadialAccountAvatar(account: target.account!, radius: 20);

    return Positioned(
      left: target.center.dx - _nodeSize / 2,
      top: target.center.dy - _nodeSize / 2,
      child: AnimatedScale(
        scale: hovered ? 1.12 : 1,
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
                      : scheme.surfaceContainerHigh.withValues(alpha: 0.95),
                  border: Border.all(
                    color: hovered
                        ? scheme.primary.withValues(alpha: 0.55)
                        : scheme.outlineVariant.withValues(alpha: 0.62),
                    width: hovered ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: hovered ? 0.2 : 0.12),
                      blurRadius: hovered ? 14 : 9,
                    ),
                  ],
                ),
                child: Semantics(
                  label: target.isManage
                      ? context.l10n.accountManage_title
                      : target.account!.username,
                  child: Center(child: child),
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
    const minRingRadius = 66.0;
    const preferredRingGap = 64.0;
    const minimumRingGap = 54.0;
    const preferredNodePitch = 60.0;

    final safe = Rect.fromLTRB(
      padding.left + outerMargin,
      padding.top + outerMargin,
      math.max(padding.left + outerMargin, size.width - padding.right - outerMargin),
      math.max(padding.top + outerMargin, size.height - padding.bottom - outerMargin),
    );

    final maxDiskRadius = math.max(
      minRingRadius + nodeRadius,
      math.min(safe.width, safe.height) / 2,
    );
    final maxRingRadius = math.max(
      minRingRadius,
      maxDiskRadius - nodeRadius - 4,
    );

    final switchable = accounts
        .where((account) => account.username != currentUsername)
        .toList(growable: false);
    final itemCount = switchable.length + 1; // + 账号管理

    int capacityFor(double radius) =>
        math.max(4, (2 * math.pi * radius / preferredNodePitch).floor());

    var ringCount = 1;
    while (true) {
      final gap = ringCount <= 1
          ? 0.0
          : (maxRingRadius - minRingRadius) / (ringCount - 1);
      if (ringCount > 1 && gap < minimumRingGap) {
        ringCount--;
        break;
      }
      final radii = List<double>.generate(
        ringCount,
        (index) => ringCount == 1
            ? math.min(maxRingRadius, math.max(minRingRadius, 78))
            : minRingRadius + gap * index,
      );
      final capacity = radii.fold<int>(0, (sum, r) => sum + capacityFor(r));
      if (capacity >= itemCount) break;
      final nextOuter = minRingRadius + preferredRingGap * ringCount;
      if (nextOuter > maxRingRadius && gap <= preferredRingGap) break;
      ringCount++;
      if (ringCount >= 8) break;
    }
    ringCount = math.max(1, ringCount);

    final radii = <double>[];
    if (ringCount == 1) {
      radii.add(math.min(maxRingRadius, math.max(minRingRadius, 78)));
    } else {
      final idealOuter = minRingRadius + preferredRingGap * (ringCount - 1);
      final outer = math.min(maxRingRadius, idealOuter);
      final gap = (outer - minRingRadius) / (ringCount - 1);
      for (var i = 0; i < ringCount; i++) {
        radii.add(minRingRadius + gap * i);
      }
    }

    final diskRadius = radii.last + nodeRadius + 4;
    final preferred = Offset(
      safe.right - diskRadius,
      fromTop ? safe.top + diskRadius : safe.bottom - diskRadius,
    );
    final center = Offset(
      preferred.dx.clamp(safe.left + diskRadius, safe.right - diskRadius),
      preferred.dy.clamp(safe.top + diskRadius, safe.bottom - diskRadius),
    );

    final targets = <_RadialTarget>[];
    var accountOffset = 0;
    for (var ring = 0; ring < radii.length; ring++) {
      final radius = radii[ring];
      final isOuter = ring == radii.length - 1;
      final capacity = capacityFor(radius);
      final reserved = isOuter ? 1 : 0;
      final remaining = switchable.length - accountOffset;
      final accountCount = math.min(math.max(0, capacity - reserved), remaining);

      if (isOuter) {
        // 底部入口向上展开、顶部入口向下展开：管理入口始终位于最外环
        // 朝屏幕内部的正中，延续旧纵向菜单“管理在远端”的肌肉记忆。
        final manageAngle = fromTop ? math.pi / 2 : -math.pi / 2;
        final totalSlots = math.max(1, accountCount + 1);
        targets.add(
          _RadialTarget(
            target: manageTarget,
            center: center + Offset.fromDirection(manageAngle, radius),
            isManage: true,
          ),
        );
        for (var i = 0; i < accountCount; i++) {
          final angle = manageAngle + 2 * math.pi * (i + 1) / totalSlots;
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
        final offset = -math.pi / 2 + math.pi / accountCount;
        for (var i = 0; i < accountCount; i++) {
          final angle = offset + 2 * math.pi * i / accountCount;
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

    // 极端账号数量超出按可视区域估算的舒适容量时仍保证全部账号可达：
    // 把余项均匀追加到最外环，而不是静默截断。
    if (accountOffset < switchable.length) {
      final radius = radii.last;
      final manageAngle = fromTop ? math.pi / 2 : -math.pi / 2;
      final remaining = switchable.length - accountOffset;
      final existingOuterAccounts = targets.where((t) {
        return !t.isManage && ((t.center - center).distance - radius).abs() < 1;
      }).length;
      final total = existingOuterAccounts + remaining + 1;
      targets.removeWhere((t) => t.isManage || ((t.center - center).distance - radius).abs() < 1);
      targets.add(
        _RadialTarget(
          target: manageTarget,
          center: center + Offset.fromDirection(manageAngle, radius),
          isManage: true,
        ),
      );
      final outerAccounts = switchable.skip(accountOffset - existingOuterAccounts).toList();
      for (var i = 0; i < outerAccounts.length; i++) {
        final angle = manageAngle + 2 * math.pi * (i + 1) / total;
        final account = outerAccounts[i];
        targets.add(
          _RadialTarget(
            target: account.username,
            center: center + Offset.fromDirection(angle, radius),
            account: account,
          ),
        );
      }
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
      ..strokeWidth = 1;
    for (final radius in radii) {
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AccountRingPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.color != color ||
        !_sameRadii(oldDelegate.radii, radii);
  }

  static bool _sameRadii(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
