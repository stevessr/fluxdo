import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discourse_providers.dart';
import '../services/discourse/user_preferences_api.dart';
import '../services/discourse/user_security_extras_api.dart';
import '../services/preloaded_data_service.dart';
import '../services/toast_service.dart';

class DiscoursePasskeysManagementPage extends ConsumerStatefulWidget {
  final String username;

  const DiscoursePasskeysManagementPage({
    super.key,
    required this.username,
  });

  @override
  ConsumerState<DiscoursePasskeysManagementPage> createState() =>
      _DiscoursePasskeysManagementPageState();
}

class _DiscoursePasskeysManagementPageState
    extends ConsumerState<DiscoursePasskeysManagementPage> {
  Map<String, dynamic>? _user;
  Map<String, dynamic> _settings = const {};
  bool _loading = true;
  bool _busy = false;
  bool _isCurrentUser = false;
  Object? _error;

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';
  String _tr(String zh, String en) => _isZh ? zh : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> get _passkeys {
    final raw = _user?['user_passkeys'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = ref.read(discourseServiceProvider);
      final results = await Future.wait<dynamic>([
        service.getUserPreferences(widget.username),
        PreloadedDataService().getSiteSettings(),
        service.getCurrentUsername(),
      ]);
      if (!mounted) return;
      final currentUsername = results[2]?.toString();
      setState(() {
        _user = Map<String, dynamic>.from(results[0] as Map);
        _settings = results[1] is Map
            ? Map<String, dynamic>.from(results[1] as Map)
            : <String, dynamic>{};
        _isCurrentUser = currentUsername != null &&
            currentUsername.toLowerCase() == widget.username.toLowerCase();
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

  Future<bool> _trusted() async {
    try {
      final result = await ref.read(discourseServiceProvider).getTrustedSession();
      if (result['success'] == true) return true;
      if (mounted) {
        ToastService.showError(
          _tr(
            '删除 Passkey 前 Discourse 要求先完成“确认访问”。请在近期重新登录后再试。',
            'Discourse requires a trusted session before deleting a Passkey. Sign in again recently and retry.',
          ),
        );
      }
      return false;
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
      return false;
    }
  }

  Future<void> _rename(Map<String, dynamic> passkey) async {
    if (_busy || !_isCurrentUser) return;
    final id = passkey['id'];
    if (id is! int) return;
    final controller = TextEditingController(
      text: passkey['name']?.toString() ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tr('重命名 Passkey', 'Rename Passkey')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: _tr('名称', 'Name'),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (text) => Navigator.pop(dialogContext, text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(_tr('保存', 'Save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(discourseServiceProvider).renamePreferencePasskey(id, value);
      if (!mounted) return;
      ToastService.showSuccess(_tr('Passkey 已重命名', 'Passkey renamed'));
      await _load();
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> passkey) async {
    if (_busy || !_isCurrentUser) return;
    final id = passkey['id'];
    if (id is! int) return;
    if (!await _trusted() || !mounted) return;

    final name = passkey['name']?.toString() ?? 'Passkey';
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(_tr('删除 Passkey？', 'Delete Passkey?')),
            content: Text(
              _tr(
                '将删除“$name”。如果它是账户最后一个可用的第一因素 Passkey，Discourse 可能拒绝删除以避免账户被锁定。',
                'This will delete “$name”. If it is the final first-factor Passkey, Discourse may refuse the operation to prevent account lockout.',
              ),
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
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(_tr('删除', 'Delete')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(discourseServiceProvider).deletePreferencePasskey(id);
      await ref.read(currentUserProvider.notifier).refreshSilently(force: true);
      if (!mounted) return;
      ToastService.showSuccess(_tr('Passkey 已删除', 'Passkey deleted'));
      await _load();
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('已有 Passkey', 'Existing Passkeys')),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
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

    final passkeys = _passkeys;
    final enabled = _settings['enable_passkeys'] == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _tr(
                '这里仅管理已经存在于 Discourse 账户中的 Passkey。重命名和删除使用官方专用接口；Fluxdo 不在此恢复 WebAuthn/Passkey 创建实验。',
                'This page manages Passkeys already registered with the Discourse account. Rename/delete use official endpoints; Fluxdo does not reintroduce experimental WebAuthn/Passkey creation here.',
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!enabled)
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(_tr('站点当前未启用 Passkey', 'Passkeys are disabled on this site')),
            ),
          )
        else if (passkeys.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.key_off_outlined),
              title: Text(_tr('没有已注册 Passkey', 'No registered Passkeys')),
            ),
          )
        else
          for (final passkey in passkeys) ...[
            _passkeyCard(passkey),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _passkeyCard(Map<String, dynamic> passkey) {
    final name = passkey['name']?.toString() ?? 'Passkey';
    final created = _formatDate(passkey['created_at']);
    final lastUsed = _formatDate(passkey['last_used']);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.key_outlined),
        title: Text(name),
        subtitle: Text(
          [
            if (created != null) _tr('添加：$created', 'Added: $created'),
            lastUsed == null
                ? _tr('从未使用', 'Never used')
                : _tr('最近使用：$lastUsed', 'Last used: $lastUsed'),
          ].join('\n'),
        ),
        isThreeLine: created != null,
        trailing: !_isCurrentUser
            ? null
            : PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'rename') _rename(passkey);
                  if (value == 'delete') _delete(passkey);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text(_tr('重命名', 'Rename')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(_tr('删除', 'Delete')),
                  ),
                ],
              ),
      ),
    );
  }

  String? _formatDate(dynamic value) {
    if (value == null) return null;
    final date = DateTime.tryParse(value.toString())?.toLocal();
    if (date == null) return value.toString();
    return MaterialLocalizations.of(context).formatMediumDate(date);
  }
}
