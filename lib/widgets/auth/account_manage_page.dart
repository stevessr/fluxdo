import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../../providers/account_providers.dart';
import '../../providers/discourse_providers.dart';
import '../../services/account_manager.dart';
import '../../services/discourse/discourse_service.dart';
import '../../services/toast_service.dart';
import '../../utils/dialog_utils.dart';
import '../common/smart_avatar.dart';
import '../../pages/login_page.dart';

/// 账号管理页面（应用设置内）
///
/// 展示所有已保存账号，支持切换、删除、添加。
/// 取代原来的底部弹出面板 [showAccountSwitchSheet]。
class AccountManagePage extends ConsumerStatefulWidget {
  const AccountManagePage({super.key});

  @override
  ConsumerState<AccountManagePage> createState() => _AccountManagePageState();
}

class _AccountManagePageState extends ConsumerState<AccountManagePage> {
  bool _switching = false;

  Future<void> _switchTo(String username) async {
    setState(() => _switching = true);
    try {
      final ok = await switchToAccount(username: username, ref: ref);
      if (!mounted) return;
      if (ok) {
        ToastService.showSuccess('已切换到 $username');
      } else {
        ToastService.showError('切换失败，账号 token 可能已过期');
      }
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _removeAccount(String username) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账号'),
        content: Text('确定要删除账号 $username 吗？'),
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
    if (confirmed == true && mounted) {
      await AccountManager().removeAccount(username);
      ref.invalidate(accountListProvider);
      if (mounted) {
        ToastService.showSuccess('已删除账号 $username');
      }
    }
  }

  Future<void> _logoutCurrent() async {
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
      final currentUser = ref.read(currentUserProvider).value;
      if (currentUser?.username != null) {
        try {
          await AccountManager().removeAccount(currentUser!.username);
        } catch (e) {
          debugPrint('[AccountManage] 移除账号失败: $e');
        }
      }
      final service = DiscourseService();
      await service.logout();
      if (mounted) {
        ref.invalidate(accountListProvider);
        ToastService.showSuccess('已退出登录');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accountsAsync = ref.watch(accountListProvider);
    final currentUser = ref.watch(currentUserProvider).value;
    final currentUsername = currentUser?.username;

    return Scaffold(
      appBar: AppBar(
        title: const Text('账号管理'),
        actions: [
          // 添加账号
          IconButton(
            icon: const Icon(Symbols.person_add_rounded),
            tooltip: '添加账号',
            onPressed: _switching
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const _LoginPageForwarder(),
                      ),
                    );
                  },
          ),
        ],
      ),
      body: accountsAsync.when(
        data: (accounts) {
          if (accounts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Symbols.person_off_rounded,
                      size: 64,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '暂无保存的账号',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '点击右上角 + 添加账号',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const _LoginPageForwarder(),
                          ),
                        );
                      },
                      icon: const Icon(Symbols.add_rounded, size: 20),
                      label: const Text('添加账号'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // 当前账号提示
              if (currentUser != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    '当前账号',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              // 账号列表
              ...accounts.map((account) {
                final isActive = account.username == currentUsername;
                return _AccountTile(
                  account: account,
                  isActive: isActive,
                  switching: _switching,
                  onTap: isActive ? null : () => _switchTo(account.username),
                  onDelete: isActive
                      ? null
                      : () => _removeAccount(account.username),
                );
              }),
              const Divider(height: 32, indent: 16, endIndent: 16),
              // 添加账号按钮
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  onPressed: _switching
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const _LoginPageForwarder(),
                            ),
                          );
                        },
                  icon: const Icon(Symbols.add_rounded, size: 20),
                  label: const Text('添加账号'),
                ),
              ),
              const SizedBox(height: 8),
              // 退出当前账号
              if (currentUser != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextButton.icon(
                    onPressed: _switching ? null : _logoutCurrent,
                    icon: const Icon(Symbols.logout_rounded, size: 20),
                    label: const Text('退出当前账号'),
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: LoadingSpinner(size: 24)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '加载失败: $e',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(accountListProvider),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 添加账号的跳板 widget —— 渲染后立即 push LoginPage，
/// 让当前页面先关闭，由同一 Navigator 打开登录页。
class _LoginPageForwarder extends StatefulWidget {
  const _LoginPageForwarder();

  @override
  State<_LoginPageForwarder> createState() => _LoginPageForwarderState();
}

class _LoginPageForwarderState extends State<_LoginPageForwarder> {
  @override
  void initState() {
    super.initState();
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

/// 单个账号列表项
class _AccountTile extends StatelessWidget {
  final StoredAccount account;
  final bool isActive;
  final bool switching;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const _AccountTile({
    required this.account,
    required this.isActive,
    required this.switching,
    this.onTap,
    this.onDelete,
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
          if (!isActive && onDelete != null)
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
