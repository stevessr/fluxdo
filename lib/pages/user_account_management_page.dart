import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discourse_providers.dart';
import '../services/discourse/user_preferences_api.dart';
import '../services/toast_service.dart';

/// Native management for the Discourse account/security actions that do not
/// map cleanly to a simple preference field.
class UserAccountManagementPage extends ConsumerStatefulWidget {
  final String username;

  const UserAccountManagementPage({super.key, required this.username});

  @override
  ConsumerState<UserAccountManagementPage> createState() =>
      _UserAccountManagementPageState();
}

class _UserAccountManagementPageState
    extends ConsumerState<UserAccountManagementPage> {
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _secondFactors;
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  String _t(String zh, String en) => _zh ? zh : en;

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
      final service = ref.read(discourseServiceProvider);
      final user = await service.getUserPreferences(widget.username);
      Map<String, dynamic>? factors;
      try {
        factors = await service.loadPreferenceSecondFactors();
      } catch (_) {
        // Discourse may require a trusted session before exposing factor detail.
      }
      if (!mounted) return;
      setState(() {
        _user = user;
        _secondFactors = factors;
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

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (success != null) ToastService.showSuccess(success);
      await _load();
    } catch (e) {
      ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askText({
    required String title,
    required String label,
    TextInputType? keyboardType,
  }) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: keyboardType,
            decoration: InputDecoration(labelText: label),
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(_t('确定', 'OK')),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_t('确定', 'Confirm')),
            ),
          ],
        ),
      ) ??
      false;

  List<dynamic> _list(String key) =>
      _user?[key] is List ? List<dynamic>.from(_user![key] as List) : const [];

  Future<void> _addEmail() async {
    final email = await _askText(
      title: _t('添加辅助邮箱', 'Add email'),
      label: _t('邮箱地址', 'Email address'),
      keyboardType: TextInputType.emailAddress,
    );
    if (email == null || email.isEmpty) return;
    await _run(
      () => ref
          .read(discourseServiceProvider)
          .addPreferenceEmail(widget.username, email),
      success: _t('已提交邮箱，请按邮件完成验证', 'Email submitted for verification'),
    );
  }

  Future<void> _makePrimary(String email) async {
    if (!await _confirm(
      _t('设为主邮箱？', 'Make primary email?'),
      email,
    )) return;
    await _run(
      () => ref
          .read(discourseServiceProvider)
          .setPreferencePrimaryEmail(widget.username, email),
      success: _t('主邮箱已更新', 'Primary email updated'),
    );
  }

  Future<void> _removeEmail(String email) async {
    if (!await _confirm(
      _t('删除辅助邮箱？', 'Remove email?'),
      email,
    )) return;
    await _run(
      () => ref
          .read(discourseServiceProvider)
          .deletePreferenceEmail(widget.username, email),
      success: _t('邮箱已删除', 'Email removed'),
    );
  }

  Future<void> _revokeAccount(Map<String, dynamic> account) async {
    final provider =
        account['provider_name']?.toString() ?? account['name']?.toString();
    if (provider == null || provider.isEmpty) return;
    if (!await _confirm(
      _t('解除关联账号？', 'Disconnect account?'),
      provider,
    )) return;
    await _run(
      () => ref
          .read(discourseServiceProvider)
          .revokePreferenceAssociatedAccount(widget.username, provider),
      success: _t('关联账号已解除', 'Account disconnected'),
    );
  }

  Future<void> _addTotp() async {
    final service = ref.read(discourseServiceProvider);
    try {
      final trusted = await service.getTrustedSession();
      if (trusted['success'] != true) {
        ToastService.showError(
          _t(
            'Discourse 要求先完成“确认访问”才能添加二次验证。请在近期重新登录后再试。',
            'Discourse requires a trusted session before adding 2FA. Sign in again recently and retry.',
          ),
        );
        return;
      }
      final setup = await service.createPreferenceTotp();
      final key = setup['key']?.toString();
      if (key == null || key.isEmpty) {
        throw Exception(setup['error']?.toString() ?? 'Missing TOTP key');
      }
      if (!mounted) return;
      final enabled = await _showTotpSetup(key);
      if (enabled == true) await _load();
    } catch (e) {
      ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<bool?> _showTotpSetup(String key) async {
    final name = TextEditingController(text: 'Fluxdo');
    final token = TextEditingController();
    try {
      return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_t('添加验证器', 'Add authenticator')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_t(
                  '在验证器应用中输入以下密钥，然后填写生成的 6 位代码。',
                  'Enter this key in your authenticator, then type the generated 6-digit code.',
                )),
                const SizedBox(height: 12),
                SelectableText(key),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: key));
                      ToastService.showSuccess(_t('密钥已复制', 'Key copied'));
                    },
                    icon: const Icon(Icons.copy),
                    label: Text(_t('复制密钥', 'Copy key')),
                  ),
                ),
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: _t('名称', 'Name')),
                ),
                TextField(
                  controller: token,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: _t('验证码', 'Code')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty || token.text.trim().isEmpty) return;
                try {
                  final response = await ref
                      .read(discourseServiceProvider)
                      .enablePreferenceTotp(
                        token: token.text.trim(),
                        name: name.text.trim(),
                      );
                  if (response['error'] != null) {
                    throw Exception(response['error'].toString());
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                  ToastService.showSuccess(_t('二次验证已启用', 'Two-factor authentication enabled'));
                } catch (e) {
                  ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
                }
              },
              child: Text(_t('启用', 'Enable')),
            ),
          ],
        ),
      );
    } finally {
      name.dispose();
      token.dispose();
    }
  }

  Future<void> _disableFactor(Map<String, dynamic> factor) async {
    final id = factor['id'];
    final method = factor['method'];
    if (id is! int || method is! int) return;
    final name = factor['name']?.toString() ?? '';
    if (!await _confirm(
      _t('删除二次验证方式？', 'Remove second factor?'),
      name,
    )) return;
    await _run(
      () => ref.read(discourseServiceProvider).updatePreferenceSecondFactor(
        id: id,
        name: name,
        disable: true,
        targetMethod: method,
      ),
      success: _t('二次验证方式已删除', 'Second factor removed'),
    );
  }

  Future<void> _backupCodes() async {
    try {
      final response = await ref
          .read(discourseServiceProvider)
          .generatePreferenceBackupCodes();
      final codes = (response['backup_codes'] as List? ??
              response['codes'] as List? ??
              const [])
          .map((e) => e.toString())
          .toList();
      if (!mounted) return;
      if (codes.isEmpty) {
        ToastService.showError(response['error']?.toString() ?? _t('未返回备份码', 'No backup codes returned'));
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_t('备份码', 'Backup codes')),
          content: SelectableText(codes.join('\n')),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: codes.join('\n')));
                ToastService.showSuccess(_t('备份码已复制', 'Backup codes copied'));
              },
              icon: const Icon(Icons.copy),
              label: Text(_t('复制', 'Copy')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_t('完成', 'Done')),
            ),
          ],
        ),
      );
    } catch (e) {
      ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Widget _section(String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('账户与安全管理', 'Account & security')),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(_t('重试', 'Retry')),
              ),
            )
          : _content(),
    );
  }

  Widget _content() {
    final primary = _user?['email']?.toString();
    final secondary = _list('secondary_emails').map((e) => e.toString()).toList();
    final unconfirmed = _list('unconfirmed_emails').map((e) => e.toString()).toList();
    final accounts = _list('associated_accounts')
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final totps = (_secondFactors?['totps'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final securityKeys = (_secondFactors?['security_keys'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _section(_t('邮箱', 'Email'), [
          if (primary != null)
            ListTile(
              leading: const Icon(Icons.mark_email_read_outlined),
              title: Text(primary),
              subtitle: Text(_t('主邮箱', 'Primary email')),
            ),
          for (final email in secondary)
            ListTile(
              leading: const Icon(Icons.alternate_email),
              title: Text(email),
              subtitle: Text(_t('辅助邮箱', 'Secondary email')),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'primary') _makePrimary(email);
                  if (value == 'remove') _removeEmail(email);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'primary', child: Text(_t('设为主邮箱', 'Make primary'))),
                  PopupMenuItem(value: 'remove', child: Text(_t('删除', 'Remove'))),
                ],
              ),
            ),
          for (final email in unconfirmed)
            ListTile(
              leading: const Icon(Icons.hourglass_top),
              title: Text(email),
              subtitle: Text(_t('等待验证', 'Awaiting verification')),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(_t('添加辅助邮箱', 'Add secondary email')),
            onTap: _busy ? null : _addEmail,
          ),
        ]),
        if (accounts.isNotEmpty)
          _section(_t('关联账号', 'Connected accounts'), [
            for (final account in accounts)
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(
                  account['description']?.toString() ??
                      account['provider_name']?.toString() ??
                      _t('关联账号', 'Connected account'),
                ),
                subtitle: Text(account['provider_name']?.toString() ?? ''),
                trailing: IconButton(
                  tooltip: _t('解除关联', 'Disconnect'),
                  onPressed: _busy ? null : () => _revokeAccount(account),
                  icon: const Icon(Icons.link_off),
                ),
              ),
          ]),
        _section(_t('二次验证', 'Two-factor authentication'), [
          if (_secondFactors == null)
            ListTile(
              leading: const Icon(Icons.lock_clock_outlined),
              title: Text(_t('需要确认访问后才能读取详细信息', 'A trusted session is required for details')),
            ),
          for (final factor in [...totps, ...securityKeys])
            ListTile(
              leading: Icon(totps.contains(factor) ? Icons.pin_outlined : Icons.key_outlined),
              title: Text(factor['name']?.toString() ?? _t('验证方式', 'Second factor')),
              trailing: IconButton(
                tooltip: _t('删除', 'Remove'),
                onPressed: _busy ? null : () => _disableFactor(factor),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.add_moderator_outlined),
            title: Text(_t('添加验证器（TOTP）', 'Add authenticator (TOTP)')),
            onTap: _busy ? null : _addTotp,
          ),
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: Text(_t('生成新的备份码', 'Generate new backup codes')),
            onTap: _busy ? null : _backupCodes,
          ),
        ]),
        _section(_t('数据', 'Data'), [
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: Text(_t('导出我的数据', 'Export my data')),
            subtitle: Text(_t('Discourse 会生成用户归档并通过站内消息/邮件提供下载。', 'Discourse will generate a user archive and provide the download when ready.')),
            onTap: _busy
                ? null
                : () => _run(
                      () => ref.read(discourseServiceProvider).exportPreferenceUserArchive(),
                      success: _t('数据导出请求已提交', 'Data export requested'),
                    ),
          ),
        ]),
      ],
    );
  }
}
