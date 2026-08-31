import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discourse_providers.dart';
import '../services/discourse/user_preferences_api.dart';
import '../services/discourse/user_security_extras_api.dart';
import '../services/toast_service.dart';

class DiscourseAccountDangerPage extends ConsumerStatefulWidget {
  final String username;

  const DiscourseAccountDangerPage({super.key, required this.username});

  @override
  ConsumerState<DiscourseAccountDangerPage> createState() =>
      _DiscourseAccountDangerPageState();
}

class _DiscourseAccountDangerPageState
    extends ConsumerState<DiscourseAccountDangerPage> {
  Map<String, dynamic>? _user;
  bool _loading = true;
  bool _deleting = false;
  Object? _error;

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';
  String _tr(String zh, String en) => _isZh ? zh : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(discourseServiceProvider)
          .getUserPreferences(widget.username);
      if (!mounted) return;
      setState(() {
        _user = user;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _deleteAccount() async {
    if (_deleting || _user?['can_delete_account'] != true) return;

    final typed = TextEditingController();
    final expected = widget.username;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(_tr('永久删除账户', 'Permanently delete account')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _tr(
                    'Discourse 会删除此账户，并按服务器规则删除该账户的帖子。这项操作不可撤销。请输入用户名确认：',
                    'Discourse will delete this account and its posts according to the server rules. This cannot be undone. Type the username to confirm:',
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(expected),
                const SizedBox(height: 12),
                TextField(
                  controller: typed,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: _tr('用户名', 'Username'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => Navigator.pop(
                  dialogContext,
                  typed.text.trim().toLowerCase() == expected.toLowerCase(),
                ),
                child: Text(_tr('永久删除', 'Delete permanently')),
              ),
            ],
          ),
        ) ??
        false;
    typed.dispose();
    if (!confirmed || !mounted) return;

    setState(() => _deleting = true);
    final service = ref.read(discourseServiceProvider);
    try {
      await service.deletePreferenceAccount(widget.username);
      // The server-side account/session is gone. Clear Fluxdo's local auth
      // without issuing another logout request against a deleted account.
      await service.logout(callApi: false);
      if (!mounted) return;
      ToastService.showSuccess(_tr('账户已删除', 'Account deleted'));
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_tr('账户危险操作', 'Account danger zone'))),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text(_tr('重试', 'Retry')),
        ),
      );
    }

    final canDelete = _user?['can_delete_account'] == true;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _tr('永久删除 Discourse 账户', 'Permanently delete Discourse account'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  canDelete
                      ? _tr(
                          '服务器已明确允许当前账户自助删除。删除成功后 Fluxdo 会同步清理本地登录状态。',
                          'The server explicitly allows self-deletion for this account. Fluxdo will clear its local session after deletion succeeds.',
                        )
                      : _tr(
                          '服务器当前不允许此账户自助删除。可能受帖子数量、账户权限、站点策略或其它安全条件限制。',
                          'The server currently does not allow self-deletion for this account. Post count, permissions, site policy, or other safety conditions may prevent it.',
                        ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  onPressed: !canDelete || _deleting ? null : _deleteAccount,
                  icon: _deleting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_forever_outlined),
                  label: Text(_tr('永久删除账户', 'Delete account permanently')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
