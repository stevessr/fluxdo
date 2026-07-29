import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../../providers/account_providers.dart';
import '../../providers/discourse_providers.dart';
import '../../services/account_manager.dart';
import '../../services/toast_service.dart';
import '../../utils/dialog_utils.dart';
import '../common/smart_avatar.dart';
import '../../pages/login_page.dart';

/// 多账号切换底部弹出面板
///
/// 显示所有已保存账号，支持切换/删除/添加账号。
Future<void> showAccountSwitchSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _AccountSwitchSheet(),
  );
}

class _AccountSwitchSheet extends ConsumerStatefulWidget {
  const _AccountSwitchSheet();

  @override
  ConsumerState<_AccountSwitchSheet> createState() =>
      _AccountSwitchSheetState();
}

class _AccountSwitchSheetState extends ConsumerState<_AccountSwitchSheet> {
  bool _switching = false;

  Future<void> _switchTo(String username) async {
    if (_switching) return;
    setState(() => _switching = true);
    try {
      final ok = await switchToAccount(username: username, ref: ref);
      if (!mounted) return;
      if (ok) {
        ToastService.showSuccess('已切换到 $username');
        Navigator.of(context).pop();
      } else {
        ToastService.showError('切换账号失败，请重新登录');
      }
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _removeAccount(String username) async {
    if (_switching) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账号'),
        content: Text('确定要删除账号 "$username" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(accountListProvider.notifier).removeAccount(username);
      if (!mounted) return;
      ToastService.showSuccess('已删除账号 $username');
    } catch (e) {
      if (!mounted) return;
      ToastService.showError('删除失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accountsAsync = ref.watch(accountListProvider);
    final currentUser = ref.watch(currentUserProvider).value;
    final currentUsername = currentUser?.username;

    final child = SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          Center(
            child: Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            '切换账号',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          // 账号列表
          accountsAsync.when(
            data: (accounts) {
              if (accounts.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      '暂无保存的账号',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }

              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: accounts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final account = accounts[index];
                    final isActive = account.username == currentUsername;
                    return _AccountTile(
                      account: account,
                      isActive: isActive,
                      switching: _switching,
                      onTap: isActive
                          ? null
                          : () => _switchTo(account.username),
                      onDelete: () => _removeAccount(account.username),
                    );
                  },
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: LoadingSpinner(size: 24)),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  '加载失败: $e',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // 添加账号按钮
          FilledButton.icon(
            onPressed: _switching
                ? null
                : () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const _LoginPageForwarder(),
                      ),
                    );
                  },
            icon: const Icon(Symbols.add_rounded, size: 20),
            label: const Text('添加账号'),
          ),

          if (currentUser != null) ...[
            const SizedBox(height: 8),
            // 退出当前账号
            TextButton.icon(
              onPressed: _switching
                  ? null
                  : () async {
                      final navigator = Navigator.of(context);
                      final confirmed = await showAppDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('退出登录'),
                          content: const Text('确定要退出当前账号吗？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('退出'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && mounted) {
                        final service = ref.read(discourseServiceProvider);
                        final currentUser = ref.read(currentUserProvider).value;
                        if (currentUser?.username != null) {
                          try {
                            await AccountManager().removeAccount(
                              currentUser!.username,
                            );
                          } catch (e) {
                            debugPrint('[AccountSwitch] 移除账号失败: $e');
                          }
                        }
                        await service.logout();
                        if (mounted) {
                          navigator.pop();
                        }
                      }
                    },
              icon: const Icon(Symbols.logout_rounded, size: 20),
              label: const Text('退出当前账号'),
              style: TextButton.styleFrom(foregroundColor: scheme.error),
            ),
          ],
        ],
      ),
    );

    // 最小高度给 loading 态
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 200),
      child: child,
    );
  }
}

/// 添加账号的跳板 widget —— 渲染后立即 push LoginPage，
/// 让底栏弹出的切换面板先关闭，再由同一 Navigator 打开登录页。
class _LoginPageForwarder extends StatefulWidget {
  const _LoginPageForwarder();

  @override
  State<_LoginPageForwarder> createState() => _LoginPageForwarderState();
}

class _LoginPageForwarderState extends State<_LoginPageForwarder> {
  @override
  void initState() {
    super.initState();
    // 用 post-frame 确保 sheet 关闭动画首帧无卡顿、路由不会中间态闪现
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _AccountTile extends StatelessWidget {
  final StoredAccount account;
  final bool isActive;
  final bool switching;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  const _AccountTile({
    required this.account,
    required this.isActive,
    required this.switching,
    this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTile(
      leading: SmartAvatar(radius: 20, fallbackText: account.username),
      title: Text(
        account.username,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        isActive ? '当前账号' : _formatTime(account.lastLoginAt),
        style: theme.textTheme.bodySmall?.copyWith(
          color: isActive
              ? scheme.primary
              : scheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive)
            Icon(Symbols.check_circle_rounded, color: scheme.primary, size: 20),
          if (!isActive)
            IconButton(
              icon: Icon(
                Symbols.delete_rounded,
                size: 18,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              onPressed: switching ? null : onDelete,
              tooltip: '删除',
            ),
        ],
      ),
      onTap: switching ? null : onTap,
      enabled: !isActive,
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${dt.month}/${dt.day}';
  }
}
