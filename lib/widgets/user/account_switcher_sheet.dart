import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../../l10n/s.dart';
import '../../pages/account_manage_page.dart';
import '../../providers/app_state_refresher.dart';
import '../../services/account_manager.dart';
import '../../services/toast_service.dart';
import '../../utils/url_helper.dart';
import '../common/app_bottom_sheet.dart';
import '../common/smart_avatar.dart';

/// 快速账号切换悬浮层相对屏幕的入口位置。
///
/// 底栏「我的」从右下向上展开；内置浏览器/帖子详情头像从右上向下展开。
/// 各入口共享完全相同的账号数据、命中测试、停留切换和真正的 session 切换动作。
enum AccountQuickSwitcherPlacement { bottomRight, topRight }

/// 账号切换入口。
///
/// - 触摸长按：Telegram 风格纵向悬浮胶囊，滑过账号后短暂停留即切换；
/// - 鼠标/桌面：沿用普通 bottom sheet；
/// - 普通点击可以显式调用 [showClassic]，不会误启动需要持续 pointer 的
///   长按悬浮层。
abstract final class AccountSwitcherSheet {
  static Future<void> show(
    BuildContext context, {
    AccountQuickSwitcherPlacement placement =
        AccountQuickSwitcherPlacement.bottomRight,
  }) {
    if (_preferTouchQuickSwitcher) {
      return _TouchAccountSwitcherEntry.show(context, placement: placement);
    }
    return showClassic(context);
  }

  static Future<void> showClassic(BuildContext context) {
    return AppBottomSheet.show(
      context: context,
      title: context.l10n.accountManage_title,
      builder: (_) => const _AccountSwitcherBody(),
    );
  }

  static bool get _preferTouchQuickSwitcher {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => true,
      _ => false,
    };
  }
}

/// Overlay build 前就接住当前长按 pointer 的后续事件，避免插入 Overlay 的
/// 一帧窗口里先收到 PointerUp 导致悬浮层残留。
class _QuickPointerRouteController {
  PointerRoute? _listener;
  PointerEvent? _pendingEvent;
  bool _disposed = false;

  _QuickPointerRouteController() {
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

/// 只负责 OverlayEntry 装卸。没有 ModalBarrier，也不复用 classic sheet，
/// 因而背景不会再画一层“切换选项框”。
abstract final class _TouchAccountSwitcherEntry {
  static Future<void> show(
    BuildContext context, {
    required AccountQuickSwitcherPlacement placement,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return AccountSwitcherSheet.showClassic(context);

    final completer = Completer<void>();
    final pointerRoute = _QuickPointerRouteController();
    late OverlayEntry entry;

    void removeEntry() {
      pointerRoute.dispose();
      if (entry.mounted) entry.remove();
    }

    void complete() {
      if (!completer.isCompleted) completer.complete();
    }

    entry = OverlayEntry(
      builder: (_) => _TouchAccountQuickSwitcher(
        hostContext: context,
        placement: placement,
        pointerRoute: pointerRoute,
        onRemove: removeEntry,
        onComplete: complete,
      ),
    );
    overlay.insert(entry);
    return completer.future;
  }
}

class _TouchAccountQuickSwitcher extends StatefulWidget {
  const _TouchAccountQuickSwitcher({
    required this.hostContext,
    required this.placement,
    required this.pointerRoute,
    required this.onRemove,
    required this.onComplete,
  });

  final BuildContext hostContext;
  final AccountQuickSwitcherPlacement placement;
  final _QuickPointerRouteController pointerRoute;
  final VoidCallback onRemove;
  final VoidCallback onComplete;

  @override
  State<_TouchAccountQuickSwitcher> createState() =>
      _TouchAccountQuickSwitcherState();
}

class _TouchAccountQuickSwitcherState extends State<_TouchAccountQuickSwitcher>
    with SingleTickerProviderStateMixin {
  static const _manageTarget = '__fluxdo_manage_accounts__';
  static const _dwellDuration = Duration(milliseconds: 320);
  static const _switchCoverMinDuration = Duration(milliseconds: 320);

  final AccountManager _manager = AccountManager();
  final GlobalKey _manageKey = GlobalKey(debugLabel: 'quick-account-manage');

  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;
  late final PointerRoute _pointerListener;

  List<SavedAccount> _accounts = const [];
  Map<String, GlobalKey> _accountKeys = const {};
  String? _currentUsername;
  String? _hoveredTarget;
  Offset? _lastPointerPosition;
  int? _trackingPointer;
  Timer? _dwellTimer;
  bool _loading = true;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 170),
      reverseDuration: const Duration(milliseconds: 105),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _opacity = curve;
    _scale = Tween<double>(begin: 0.9, end: 1).animate(curve);
    _slide = Tween<Offset>(
      begin: widget.placement == AccountQuickSwitcherPlacement.topRight
          ? const Offset(0, -0.08)
          : const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(curve);

    _pointerListener = _handlePointerEvent;
    widget.pointerRoute.attach(_pointerListener);
    unawaited(_controller.forward());
    unawaited(_reload());
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    widget.pointerRoute.detach(_pointerListener);
    widget.pointerRoute.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      // 切换前先固化当前登录态，保证切走后仍可无损切回来。
      await _manager.syncCurrentAccount();
      final accountsFuture = _manager.listAccounts();
      final currentFuture = _manager.getCurrentUsername();
      final accounts = await accountsFuture;
      final current = await currentFuture;
      // 触发入口本身已经展示当前 profile，长按悬浮层只列可切换目标，
      // 避免同一个当前账号在入口和浮层里重复出现。
      final switchableAccounts = accounts
          .where((account) => account.username != current)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _accounts = switchableAccounts;
        _currentUsername = current;
        _accountKeys = {
          for (final account in switchableAccounts)
            account.username: GlobalKey(
              debugLabel: 'quick-account-${account.username}',
            ),
        };
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

    // 移动端也可能外接鼠标。若真正触发长按的是鼠标，松开后退回经典面板。
    if (event.kind != PointerDeviceKind.touch) {
      if (_trackingPointer == null &&
          (event is PointerUpEvent || event is PointerCancelEvent)) {
        unawaited(_finish(null, fallbackToClassic: true));
      }
      return;
    }

    // Overlay 在长按已经成立后插入；此后出现 PointerDown 是第二根手指，
    // 不允许它抢走原长按序列。
    if (_trackingPointer == null) {
      if (event is PointerDownEvent) return;
      _trackingPointer = event.pointer;
    }
    if (event.pointer != _trackingPointer) return;

    if (event is PointerMoveEvent) {
      _lastPointerPosition = event.position;
      _updateHoveredTarget(event.position);
    } else if (event is PointerUpEvent) {
      _lastPointerPosition = event.position;
      _updateHoveredTarget(event.position, haptic: false);
      unawaited(_finish(_hoveredTarget));
    } else if (event is PointerCancelEvent) {
      unawaited(_finish(null));
    }
  }

  void _updateHoveredTarget(Offset globalPosition, {bool haptic = true}) {
    if (!mounted || _finishing) return;
    final next = _targetAt(globalPosition);
    if (next == _hoveredTarget) return;

    _dwellTimer?.cancel();
    _dwellTimer = null;
    setState(() => _hoveredTarget = next);

    if (haptic && next != null) {
      unawaited(HapticFeedback.selectionClick());
    }

    // 管理入口只在松手时打开，防止用户从按钮向账号滑动时误进入管理页。
    // 当前账号也不启动计时器。其余账号停留 320ms 后立即切换，无需松手。
    if (next == null ||
        next == _manageTarget ||
        next == _currentUsername ||
        _accountForTarget(next) == null) {
      return;
    }
    _dwellTimer = Timer(_dwellDuration, () {
      if (!mounted || _finishing || _hoveredTarget != next) return;
      unawaited(_finish(next));
    });
  }

  String? _targetAt(Offset globalPosition) {
    if (_containsGlobalPoint(_manageKey, globalPosition)) return _manageTarget;
    for (final account in _accounts) {
      final key = _accountKeys[account.username];
      if (key != null && _containsGlobalPoint(key, globalPosition)) {
        return account.username;
      }
    }
    return null;
  }

  bool _containsGlobalPoint(GlobalKey key, Offset point) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    return (topLeft & renderObject.size).contains(point);
  }

  SavedAccount? _accountForTarget(String? target) {
    if (target == null || target == _manageTarget) return null;
    for (final account in _accounts) {
      if (account.username == target) return account;
    }
    return null;
  }

  Future<void> _finish(
    String? target, {
    bool fallbackToClassic = false,
  }) async {
    if (_finishing) return;
    _finishing = true;
    _dwellTimer?.cancel();
    _dwellTimer = null;

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

    // 对真正的账号快速切换，先在悬浮层仍存在时把全屏 cover 插到它上方，
    // 从确认目标这一刻开始就吞掉全部输入。这样悬浮层 reverse/remove 与
    // session/provider 重载之间不存在一帧可误触窗口。
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
          builder: (_) => _QuickAccountSwitchCover(account: account),
        );
        switchCoverStopwatch = Stopwatch()..start();
        overlay.insert(switchCover);
        // 确认 cover 已经完成一次绘制后再开始销毁旧悬浮层与切换 session。
        await WidgetsBinding.instance.endOfFrame;
      }
    }

    try {
      await _controller.reverse();
    } catch (_) {
      // 宿主若同步移除 Overlay，controller 可能已 dispose；仍继续收口。
    }
    remove();

    try {
      if (fallbackToClassic) {
        if (hostContext.mounted) {
          await AccountSwitcherSheet.showClassic(hostContext);
        }
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
        await _performAccountSwitch(hostContext, _manager, account);

        // resetForAccountSwitch 完成后再给新账号的 provider / 页面一帧 rebuild，
        // 然后才移除 cover，避免用户看到半更新状态或在组件重建时误触。
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
    final fromTop = widget.placement == AccountQuickSwitcherPlacement.topRight;
    final edgeInset = fromTop
        ? media.padding.top + kToolbarHeight + 8.0
        : media.padding.bottom + 72.0;
    final maxHeight = (media.size.height -
            media.padding.top -
            media.padding.bottom -
            kToolbarHeight -
            20)
        .clamp(120.0, 520.0)
        .toDouble();
    final showManageDivider = _loading || _accounts.isNotEmpty;

    final switcher = FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: _scale,
          alignment: fromTop ? Alignment.topRight : Alignment.bottomRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh.withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.55),
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.18),
                    blurRadius: 22,
                    offset: Offset(0, fromTop ? 6 : -2),
                  ),
                ],
              ),
              child: SizedBox(
                width: 72,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 管理按钮始终放在触发入口的远端：底部入口向上展开时
                      // 管理在顶部；顶部入口向下展开时管理在底部。
                      if (!fromTop) _buildManageTarget(context),
                      if (!fromTop && showManageDivider)
                        _buildManageDivider(scheme),
                      if (_loading)
                        const SizedBox(
                          height: 58,
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      else
                        for (final account in _accounts)
                          _buildAccountTarget(context, account),
                      if (fromTop && showManageDivider)
                        _buildManageDivider(scheme),
                      if (fromTop) _buildManageTarget(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // 当前 pointer 仍沿原 hit-test route 派发；这里纯绘制，不阻断背景，也不
    // 创建第二份可交互账号框。
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            if (fromTop)
              Positioned(right: 12, top: edgeInset, child: switcher)
            else
              Positioned(right: 12, bottom: edgeInset, child: switcher),
          ],
        ),
      ),
    );
  }

  Widget _buildManageDivider(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Divider(
        height: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.55),
      ),
    );
  }

  Widget _buildManageTarget(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _buildTargetShell(
      key: _manageKey,
      hovered: _hoveredTarget == _manageTarget,
      semanticLabel: context.l10n.accountManage_title,
      child: Icon(
        Symbols.manage_accounts_rounded,
        size: 25,
        color: _hoveredTarget == _manageTarget
            ? scheme.onPrimaryContainer
            : scheme.primary,
      ),
    );
  }

  Widget _buildAccountTarget(BuildContext context, SavedAccount account) {
    final key = _accountKeys[account.username];
    final hovered = _hoveredTarget == account.username;
    final current = account.username == _currentUsername;
    return _buildTargetShell(
      key: key,
      hovered: hovered,
      current: current,
      semanticLabel: account.username,
      child: _AccountAvatar(account: account, radius: 20),
    );
  }

  Widget _buildTargetShell({
    required Key? key,
    required bool hovered,
    required String semanticLabel,
    required Widget child,
    bool current = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: key,
      width: 62,
      height: 58,
      child: Center(
        child: AnimatedScale(
          scale: hovered ? 1.08 : 1,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hovered
                  ? scheme.primaryContainer
                  : current
                  ? scheme.secondaryContainer.withValues(alpha: 0.6)
                  : Colors.transparent,
              border: current
                  ? Border.all(color: scheme.primary, width: 1.5)
                  : hovered
                  ? Border.all(
                      color: scheme.primary.withValues(alpha: 0.28),
                      width: 1,
                    )
                  : null,
            ),
            child: Semantics(label: semanticLabel, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}

class _QuickAccountSwitchCover extends StatelessWidget {
  const _QuickAccountSwitchCover({required this.account});

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
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.94, end: 1),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.scale(
                    scale: value,
                    child: child,
                  ),
                ),
                child: Semantics(
                  liveRegion: true,
                  label: context.l10n.accountManage_switching,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AccountAvatar(account: account, radius: 30),
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
        ),
      ),
    );
  }
}

Future<bool> _performAccountSwitch(
  BuildContext context,
  AccountManager manager,
  SavedAccount account,
) async {
  // 先取 container，异步切换完成后不再依赖可能变化的 Overlay context。
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

class _AccountSwitcherBody extends StatefulWidget {
  const _AccountSwitcherBody();

  @override
  State<_AccountSwitcherBody> createState() => _AccountSwitcherBodyState();
}

class _AccountSwitcherBodyState extends State<_AccountSwitcherBody> {
  final AccountManager _manager = AccountManager();
  List<SavedAccount> _accounts = const [];
  String? _currentUsername;
  bool _loading = true;
  String? _switchingUsername;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
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
  }

  Future<void> _switchTo(SavedAccount account) async {
    if (_switchingUsername != null) return;
    setState(() => _switchingUsername = account.username);
    final switched = await _performAccountSwitch(context, _manager, account);
    if (!mounted) return;
    if (switched) {
      Navigator.of(context).pop();
    } else {
      setState(() => _switchingUsername = null);
    }
  }

  Future<void> _openManagePage() async {
    final navigator = Navigator.of(context);
    navigator.pop();
    unawaited(
      navigator.push(
        MaterialPageRoute(builder: (_) => const AccountManagePage()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: LoadingSpinner(),
        ),
      );
    }

    if (_switchingUsername != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LoadingSpinner(),
              const SizedBox(height: 16),
              Text(l10n.accountManage_switching, style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final account in _accounts)
          _AccountTile(
            key: ValueKey('account-switcher-tile-${account.username}'),
            account: account,
            isCurrent: account.username == _currentUsername,
            onTap: account.username == _currentUsername
                ? null
                : () => unawaited(_switchTo(account)),
          ),
        if (_accounts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              l10n.accountManage_empty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const Divider(height: 1),
        InkWell(
          onTap: _openManagePage,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  Symbols.manage_accounts_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    l10n.accountManage_title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Icon(
                  Symbols.chevron_right_rounded,
                  size: 20,
                  color: theme.colorScheme.outline.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    super.key,
    required this.account,
    required this.isCurrent,
    required this.onTap,
  });

  final SavedAccount account;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _AccountAvatar(account: account, radius: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                account.username,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (isCurrent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  l10n.accountManage_currentChip,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.account, required this.radius});

  final SavedAccount account;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final template = account.avatarTemplate;
    final imageUrl = template != null && template.isNotEmpty
        ? UrlHelper.resolveUrlWithCdn(template.replaceAll('{size}', '96'))
        : null;

    // 统一走 SmartAvatar → BlobImageProvider。BlobImageCache 的根目录和
    // ImageProvider key 都不含 profile，因此同一 URL 在所有账号间只有一份
    // 磁盘文件和一份 Flutter ImageCache 身份；账号 cookie/session 不参与缓存键。
    return SmartAvatar(
      imageUrl: imageUrl,
      radius: radius,
      fallbackText: account.username,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}
