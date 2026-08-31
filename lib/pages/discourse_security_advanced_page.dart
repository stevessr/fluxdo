import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discourse_providers.dart';
import '../services/discourse/user_preferences_api.dart';
import '../services/discourse/user_security_extras_api.dart';
import '../services/preloaded_data_service.dart';
import '../services/toast_service.dart';

class DiscourseSecurityAdvancedPage extends ConsumerStatefulWidget {
  final String username;

  const DiscourseSecurityAdvancedPage({super.key, required this.username});

  @override
  ConsumerState<DiscourseSecurityAdvancedPage> createState() =>
      _DiscourseSecurityAdvancedPageState();
}

class _DiscourseSecurityAdvancedPageState
    extends ConsumerState<DiscourseSecurityAdvancedPage> {
  Map<String, dynamic>? _user;
  Map<String, dynamic> _settings = const {};
  bool _loading = true;
  bool _busy = false;
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
      final results = await Future.wait<dynamic>([
        ref.read(discourseServiceProvider).getUserPreferences(widget.username),
        PreloadedDataService().getSiteSettings(),
      ]);
      if (!mounted) return;
      setState(() {
        _user = Map<String, dynamic>.from(results[0] as Map);
        _settings = results[1] is Map
            ? Map<String, dynamic>.from(results[1] as Map)
            : <String, dynamic>{};
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

  List<dynamic> _list(String key) =>
      _user?[key] is List ? List<dynamic>.from(_user![key] as List) : const [];

  Future<bool> _confirm(String title, String message, {bool destructive = false}) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    )
                  : null,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_tr('确定', 'Confirm')),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _requestPasswordChange() async {
    if (_busy || !_canChangePassword) return;
    setState(() => _busy = true);
    try {
      final login = _user?['email']?.toString().trim();
      await ref.read(discourseServiceProvider).requestPreferencePasswordReset(
            login: login != null && login.isNotEmpty ? login : widget.username,
          );
      if (!mounted) return;
      ToastService.showSuccess(
        _user?['no_password'] == true
            ? _tr('设置密码邮件已发送', 'Set-password email sent')
            : _tr('修改密码邮件已发送', 'Password-change email sent'),
      );
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canChangePassword {
    if (_user?['is_anonymous'] == true) return false;
    return _settings['enable_discourse_connect'] != true &&
        _settings['enable_local_logins'] == true;
  }

  bool get _canRemovePassword {
    if (!_canChangePassword || _user?['no_password'] == true) return false;
    if (_user?['can_remove_password'] == true) return true;
    if (_list('associated_accounts').isNotEmpty) return true;
    final passkeys = _list('user_passkeys');
    return _settings['enable_passkeys'] == true && passkeys.isNotEmpty;
  }

  Future<void> _removePassword() async {
    if (_busy || !_canRemovePassword) return;
    final trusted = await _ensureTrustedSession(
      _tr(
        '移除密码前，Discourse 要求先完成“确认访问”。请在近期重新登录后再试。',
        'Discourse requires a trusted session before removing your password. Sign in again recently and retry.',
      ),
    );
    if (!trusted || !mounted) return;

    final confirmed = await _confirm(
      _tr('移除本地密码？', 'Remove local password?'),
      _tr(
        '之后必须通过已关联账号或其他可用认证方式登录。此操作不会删除账户。',
        'You will need a linked account or another available sign-in method afterwards. This does not delete the account.',
      ),
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(discourseServiceProvider)
          .removePreferencePassword(widget.username);
      await ref.read(currentUserProvider.notifier).refreshSilently(force: true);
      if (!mounted) return;
      ToastService.showSuccess(_tr('本地密码已移除', 'Local password removed'));
      await _load();
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _ensureTrustedSession(String failureMessage) async {
    try {
      final trusted = await ref.read(discourseServiceProvider).getTrustedSession();
      if (trusted['success'] == true) return true;
      if (mounted) ToastService.showError(failureMessage);
      return false;
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
      return false;
    }
  }

  Future<void> _resendEmail(String email) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(discourseServiceProvider)
          .addPreferenceEmail(widget.username, email);
      if (!mounted) return;
      ToastService.showSuccess(_tr('验证邮件已重新发送', 'Verification email resent'));
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleApiKey(Map<String, dynamic> key) async {
    if (_busy) return;
    final id = key['id'];
    if (id is! int) return;
    final revoked = key['revoked'] == true;
    final appName = key['application_name']?.toString() ?? '#$id';
    if (!revoked) {
      final confirmed = await _confirm(
        _tr('撤销授权？', 'Revoke authorization?'),
        appName,
        destructive: true,
      );
      if (!confirmed || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final service = ref.read(discourseServiceProvider);
      if (revoked) {
        await service.undoRevokePreferenceApiKey(id);
      } else {
        await service.revokePreferenceApiKey(id);
      }
      if (!mounted) return;
      ToastService.showSuccess(
        revoked
            ? _tr('授权已恢复', 'Authorization restored')
            : _tr('授权已撤销', 'Authorization revoked'),
      );
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
        title: Text(_tr('密码与授权应用', 'Password & authorized apps')),
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 12),
              Text(_error.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(_tr('重试', 'Retry')),
              ),
            ],
          ),
        ),
      );
    }

    final unconfirmed = _list('unconfirmed_emails').map((e) => e.toString()).toList();
    final apiKeys = _list('user_api_keys')
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final passkeys = _list('user_passkeys')
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _section(
          _tr('密码', 'Password'),
          [
            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: Text(
                _user?['no_password'] == true
                    ? _tr('设置本地密码', 'Set local password')
                    : _tr('修改本地密码', 'Change local password'),
              ),
              subtitle: Text(
                !_canChangePassword
                    ? _tr(
                        '当前 Discourse 认证配置不允许修改本地密码。',
                        'The current Discourse authentication configuration does not allow local password changes.',
                      )
                    : _tr(
                        'Discourse 会向账户邮箱发送安全的密码设置链接。',
                        'Discourse will send a secure password-change link to your account email.',
                      ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy || !_canChangePassword ? null : _requestPasswordChange,
            ),
            if (_user?['no_password'] != true)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: _canRemovePassword
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                title: Text(_tr('移除本地密码', 'Remove local password')),
                subtitle: Text(
                  _canRemovePassword
                      ? _tr(
                          '需要 Discourse trusted session，并且必须保留其它登录方式。',
                          'Requires a trusted Discourse session and another sign-in method.',
                        )
                      : _tr(
                          '当前账户没有满足 Discourse 的安全移除条件。',
                          'This account does not currently meet Discourse’s safe-removal requirements.',
                        ),
                ),
                onTap: _busy || !_canRemovePassword ? null : _removePassword,
              ),
          ],
        ),
        if (unconfirmed.isNotEmpty)
          _section(
            _tr('等待验证的邮箱', 'Unconfirmed emails'),
            [
              for (final email in unconfirmed)
                ListTile(
                  leading: const Icon(Icons.mark_email_unread_outlined),
                  title: Text(email),
                  subtitle: Text(_tr('尚未验证', 'Not yet verified')),
                  trailing: TextButton(
                    onPressed: _busy ? null : () => _resendEmail(email),
                    child: Text(_tr('重发', 'Resend')),
                  ),
                ),
            ],
          ),
        if (apiKeys.isNotEmpty)
          _section(
            _tr('授权应用 / User API Keys', 'Authorized apps / User API Keys'),
            [
              for (final key in apiKeys) _apiKeyTile(key),
            ],
            subtitle: _tr(
              '这些授权来自 Discourse User API。撤销后对应应用将无法继续以该授权访问账户。',
              'These are Discourse User API authorizations. Revoking one prevents that app from continuing to use the authorization.',
            ),
          ),
        if (passkeys.isNotEmpty)
          _section(
            _tr('Passkey', 'Passkeys'),
            [
              for (final passkey in passkeys)
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: Text(
                    passkey['name']?.toString() ??
                        passkey['credential_id']?.toString() ??
                        _tr('Passkey', 'Passkey'),
                  ),
                  subtitle: Text(
                    _tr(
                      '仅显示已有 Passkey；Fluxdo 不在此重新引入 WebAuthn 创建流程。',
                      'Existing Passkeys are shown read-only; Fluxdo does not reintroduce WebAuthn creation here.',
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _apiKeyTile(Map<String, dynamic> key) {
    final revoked = key['revoked'] == true;
    final scopes = key['scopes'] is List
        ? (key['scopes'] as List).map((e) => e.toString()).toList()
        : const <String>[];
    final details = <String>[
      if (key['created_at'] != null)
        '${_tr('批准', 'Approved')}: ${key['created_at']}',
      if (key['last_used_at'] != null)
        '${_tr('最近使用', 'Last used')}: ${key['last_used_at']}',
      if (key['expires_at'] != null)
        '${_tr('到期', 'Expires')}: ${key['expires_at']}',
      if (scopes.isNotEmpty) '${_tr('权限', 'Scopes')}: ${scopes.join(', ')}',
    ];
    return ListTile(
      leading: Icon(revoked ? Icons.block_outlined : Icons.apps_outlined),
      title: Text(
        key['application_name']?.toString() ??
            _tr('已授权应用', 'Authorized app'),
      ),
      subtitle: Text(
        details.isEmpty
            ? (revoked ? _tr('已撤销', 'Revoked') : _tr('有效', 'Active'))
            : details.join('\n'),
        maxLines: 5,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: TextButton(
        onPressed: _busy ? null : () => _toggleApiKey(key),
        child: Text(
          revoked ? _tr('恢复', 'Restore') : _tr('撤销', 'Revoke'),
        ),
      ),
    );
  }

  Widget _section(
    String title,
    List<Widget> children, {
    String? subtitle,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(children: _withDividers(children)),
            ),
          ],
        ),
      );

  List<Widget> _withDividers(List<Widget> children) {
    final result = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) result.add(const Divider(height: 1, indent: 16, endIndent: 16));
      result.add(children[i]);
    }
    return result;
  }
}
