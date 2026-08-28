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

/// 长按底栏「我的」弹出的快速切换账号入口。
///
/// 手机/平板触摸场景使用 Telegram 风格的悬浮纵向胶囊：保持手指按下并
/// 滑过目标时只高亮，只有松手时才确认切换；桌面端继续使用普通 bottom
/// sheet。两种展示只共享真正的账号切换动作，不复用彼此的 UI，避免快捷
/// 入口背后再次渲染一份账号选择框。
abstract final class AccountSwitcherSheet {
  static Future<void> show(BuildContext context) {
    if (_preferTouchQuickSwitcher) {
      return _TouchAccountSwitcherEntry.show(context);
    }
    return _showClassic(context);
  }

  static bool get _preferTouchQuickSwitcher {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => true,
      _ => false,
    };
  }

  static Future<void> _showClassic(BuildContext context) {
    return AppBottomSheet.show(
      context: context,
      title: context.l10n.accountManage_title,
      builder: (_) => const _AccountSwitcherBody(),
    );
  }
}

/// 在 Overlay 真正 build 之前就开始接收当前长按序列的后续事件。
///
/// onLongPress 是 deadline timer 回调，OverlayEntry 插入后通常要到下一帧才
/// build；如果用户恰好在这 1 帧内松手，等 State.initState 再注册 route 会
/// 丢掉 PointerUp，导致悬浮层残留。这个 controller 在 show() 同步注册全局
/// route，并把 build 前最后一条有效事件暂存给 State 重放。
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

/// 只负责 OverlayEntry 的装卸；Overlay 本身没有 ModalBarrier，也不会在
/// 背景构建第二份账号选择 UI。正在进行的长按 pointer 通过 PointerRouter
/// 的 global route 继续追踪，因此 Overlay 无需接管命中测试。
abstract final class _TouchAccountSwitcherEntry {
  static Future<void> show(BuildContext context) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return AccountSwitcherSheet._showClassic(context);
    }

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
    required this.pointerRoute,
    required this.onRemove,
    required this.onComplete,
  });

  final BuildContext hostContext;
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
  int? _trackingPointer;
  bool _loading = true;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 110),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _opacity = curve;
    _scale = Tween<double>(begin: 0.82, end: 1).animate(curve);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(curve);

    _pointerListener = _handlePointerEvent;
    widget.pointerRoute.attach(_pointerListener);
    unawaited(_controller.forward());
    unawaited(_reload());
  }

  @override
  void dispose() {
    widget.pointerRoute.detach(_pointerListener);
    widget.pointerRoute.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      // 与账号管理页一致：先固化当前登录态，保证切走后还能切回来。
      await _manager.syncCurrentAccount();
      final accountsFuture = _manager.listAccounts();
      final currentFuture = _manager.getCurrentUsername();
      final accounts = await accountsFuture;
      final current = await currentFuture;
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _currentUsername = current;
        _accountKeys = {
          for (final account in accounts)
            account.username: GlobalKey(
              debugLabel: 'quick-account-${account.username}',
            ),
        };
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _handlePointerEvent(PointerEvent event) {
    if (_finishing) return;

    // 手机也可能外接鼠标。桌面平台本来就不会进入这个 Overlay；移动端如果
    // 真的是鼠标长按，则在它松开时恢复原 bottom sheet。仅在尚未锁定触摸
    // pointer 时处理，避免外接鼠标的无关事件污染正在滑选的手指。
    if (event.kind != PointerDeviceKind.touch) {
      if (_trackingPointer == null &&
          (event is PointerUpEvent || event is PointerCancelEvent)) {
        unawaited(_finish(null, fallbackToClassic: true));
      }
      return;
    }

    // Overlay 是在长按已经成立后才插入的，因此这里看到的新 PointerDown
    // 必然是第二根手指，不应抢走原长按 pointer。原指针的下一条事件只能是
    // Move / Up / Cancel，从其中第一条锁定 pointer id。
    if (_trackingPointer == null) {
      if (event is PointerDownEvent) return;
      _trackingPointer = event.pointer;
    }
    if (event.pointer != _trackingPointer) return;

    if (event is PointerMoveEvent) {
      _updateHoveredTarget(event.position);
    } else if (event is PointerUpEvent) {
      // 即使手指最后一段没有产生 Move，也以松手坐标做最后一次 hit-test。
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
    setState(() => _hoveredTarget = next);
    if (haptic && next != null) {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  String? _targetAt(Offset globalPosition) {
    if (_containsGlobalPoint(_manageKey, globalPosition)) {
      return _manageTarget;
    }
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

    final hostContext = widget.hostContext;
    final remove = widget.onRemove;
    final complete = widget.onComplete;
    final currentUsername = _currentUsername;
    final account = _accountForTarget(target);

    if (target != null && !fallbackToClassic) {
      unawaited(HapticFeedback.lightImpact());
    }

    try {
      await _controller.reverse();
    } catch (_) {
      // Overlay 被宿主同步移除时 controller 可能已 dispose；收口仍需继续。
    }
    remove();

    try {
      if (fallbackToClassic) {
        if (hostContext.mounted) {
          await AccountSwitcherSheet._showClassic(hostContext);
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

      // 松在当前账号、空白处或数据尚未加载完成时只收起，不产生副作用。
      if (account == null || account.username == currentUsername) return;
      if (hostContext.mounted) {
        await _performAccountSwitch(hostContext, _manager, account);
      }
    } finally {
      complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    final bottom = media.padding.bottom + 72.0;
    final maxHeight = (media.size.height - media.padding.top - bottom - 12)
        .clamp(120.0, 520.0)
        .toDouble();

    // IgnorePointer 是刻意的：当前长按序列已经在旧 hit-test route 上，快捷
    // 面板只负责绘制；全屏区域既不拦截背景，也不会再生成一个可点击选项框。
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned(
              right: 12,
              bottom: bottom,
              child: FadeTransition(
                opacity: _opacity,
                child: SlideTransition(
                  position: _slide,
                  child: ScaleTransition(
                    scale: _scale,
                    alignment: Alignment.bottomRight,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxHeight),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh.withValues(
                            alpha: 0.97,
                          ),
                          borderRadius: BorderRadius.circular(36),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.55),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.shadow.withValues(alpha: 0.18),
                              blurRadius: 22,
                              offset: const Offset(0, 8),
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
                                _buildManageTarget(context),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 3,
                                  ),
                                  child: Divider(
                                    height: 1,
                                    color: scheme.outlineVariant.withValues(
                                      alpha: 0.55,
                                    ),
                                  ),
                                ),
                                if (_loading)
                                  const SizedBox(
                                    height: 58,
                                    child: Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  )
                                else if (_accounts.isEmpty)
                                  SizedBox(
                                    height: 52,
                                    child: Center(
                                      child: Icon(
                                        Symbols.person_off_rounded,
                                        size: 22,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  )
                                else
                                  for (final account in _accounts)
                                    _buildAccountTarget(context, account),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
          scale: hovered ? 1.1 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
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

Future<bool> _performAccountSwitch(
  BuildContext context,
  AccountManager manager,
  SavedAccount account,
) async {
  // 先取得 container，避免异步切换完成时再依赖可能已变化的 Overlay context。
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

  /// 正在切换的目标用户名；非 null 时列表被进度态替换。
  String? _switchingUsername;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    // 与账号管理页一致：先固化当前登录态，保证切走后还能切回来
    await _manager.syncCurrentAccount();
    final accounts = await _manager.listAccounts();
    final current = await _manager.getCurrentUsername();
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
              Text(
                l10n.accountManage_switching,
                style: theme.textTheme.titleMedium,
              ),
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
    final theme = Theme.of(context);
    final template = account.avatarTemplate;
    if (template != null && template.isNotEmpty) {
      final url = UrlHelper.resolveUrlWithCdn(
        template.replaceAll('{size}', '96'),
      );
      return CircleAvatar(
        radius: radius,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        foregroundImage: NetworkImage(url),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      child: Text(
        account.username.isNotEmpty ? account.username[0].toUpperCase() : '?',
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
