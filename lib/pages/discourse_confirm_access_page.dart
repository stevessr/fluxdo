import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discourse_providers.dart';
import '../services/discourse/user_preferences_api.dart';
import '../services/discourse/user_security_extras_api.dart';
import '../services/preloaded_data_service.dart';
import '../services/toast_service.dart';

/// Native counterpart of Discourse's ConfirmSession dialog.
///
/// This deliberately implements the official password path only. Passkey-based
/// confirmation requires a platform WebAuthn assertion and stays out of Fluxdo
/// until there is a deliberate native credential implementation.
class DiscourseConfirmAccessPage extends ConsumerStatefulWidget {
  final String username;

  const DiscourseConfirmAccessPage({super.key, required this.username});

  @override
  ConsumerState<DiscourseConfirmAccessPage> createState() =>
      _DiscourseConfirmAccessPageState();
}

class _DiscourseConfirmAccessPageState
    extends ConsumerState<DiscourseConfirmAccessPage> {
  final TextEditingController _password = TextEditingController();

  Map<String, dynamic>? _user;
  Map<String, dynamic> _settings = const {};
  bool _loading = true;
  bool _busy = false;
  bool _trusted = false;
  bool _isCurrentUser = false;
  bool _obscure = true;
  Object? _error;

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';
  String _tr(String zh, String en) => _isZh ? zh : en;

  bool get _canConfirmWithPassword =>
      _isCurrentUser &&
      _settings['enable_discourse_connect'] != true &&
      _settings['enable_local_logins'] == true &&
      _user?['no_password'] != true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
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
        service.getTrustedSession(),
        PreloadedDataService().getSiteSettings(),
        service.getCurrentUsername(),
      ]);
      if (!mounted) return;
      final currentUsername = results[3]?.toString();
      setState(() {
        _user = Map<String, dynamic>.from(results[0] as Map);
        final trusted = results[1] is Map
            ? Map<String, dynamic>.from(results[1] as Map)
            : <String, dynamic>{};
        _trusted = trusted['success'] == true;
        _settings = results[2] is Map
            ? Map<String, dynamic>.from(results[2] as Map)
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

  Future<void> _confirm() async {
    if (_busy || !_canConfirmWithPassword) return;
    final password = _password.text;
    if (password.isEmpty) {
      ToastService.showError(_tr('请输入当前密码', 'Enter your current password'));
      return;
    }

    setState(() => _busy = true);
    try {
      final result = await ref
          .read(discourseServiceProvider)
          .confirmPreferenceSessionWithPassword(password);
      if (!mounted) return;
      if (result['success'] == true) {
        _password.clear();
        setState(() => _trusted = true);
        ToastService.showSuccess(
          _tr('访问已确认，可以执行敏感账户操作', 'Access confirmed for sensitive account actions'),
        );
      } else {
        ToastService.showError(
          result['error']?.toString() ??
              _tr('密码不正确', 'Incorrect password'),
        );
      }
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final email = _user?['email']?.toString().trim();
      await ref.read(discourseServiceProvider).requestPreferencePasswordReset(
            login: email != null && email.isNotEmpty ? email : widget.username,
          );
      if (!mounted) return;
      ToastService.showSuccess(
        _tr('密码设置/重置邮件已发送', 'Password setup/reset email sent'),
      );
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
        title: Text(_tr('确认访问', 'Confirm access')),
        actions: [
          IconButton(
            tooltip: _tr('重新检查状态', 'Recheck status'),
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Card(
          child: ListTile(
            leading: Icon(
              _trusted ? Icons.verified_user_outlined : Icons.shield_outlined,
            ),
            title: Text(
              _trusted
                  ? _tr('当前会话已确认', 'Current session is confirmed')
                  : _tr('当前会话需要确认', 'Current session needs confirmation'),
            ),
            subtitle: Text(
              _trusted
                  ? _tr(
                      'TOTP、安全密钥、删除 Passkey、移除密码等敏感操作现在可以继续。',
                      'Sensitive actions such as TOTP, security keys, Passkey deletion, and password removal can proceed.',
                    )
                  : _tr(
                      '与 Discourse 官方 ConfirmSession 一致，确认后只提升当前服务器会话的安全级别，不会保存密码。',
                      'Matches Discourse ConfirmSession: confirmation only elevates the current server session and never stores your password.',
                    ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!_isCurrentUser)
          Card(
            child: ListTile(
              leading: const Icon(Icons.block_outlined),
              title: Text(
                _tr(
                  '只能确认当前登录账户',
                  'Only the currently signed-in account can be confirmed',
                ),
              ),
            ),
          )
        else if (_trusted)
          Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(_tr('无需再次输入密码', 'No password entry is needed')),
              subtitle: Text(
                _tr(
                  'Discourse 会按服务器策略让 trusted session 自动过期。',
                  'Discourse will expire the trusted session according to server policy.',
                ),
              ),
            ),
          )
        else if (!_canConfirmWithPassword)
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(
                    _user?['no_password'] == true
                        ? _tr('当前账户没有本地密码', 'This account has no local password')
                        : _tr(
                            '当前站点认证配置不支持密码确认',
                            'This site does not support password confirmation',
                          ),
                  subtitle: Text(
                    _tr(
                      'Discourse Connect / SSO 或无本地密码场景需要由站点认证方式重新确认；Fluxdo 不会伪造该流程。',
                      'Discourse Connect / SSO or passwordless accounts must be re-confirmed through the site authentication method; Fluxdo does not emulate it.',
                    ),
                ),
                if (_user?['no_password'] == true)
                  ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: Text(_tr('设置本地密码', 'Set a local password')),
                    onTap: _busy ? null : _sendPasswordReset,
                  ),
              ],
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _tr('已登录为 @${widget.username}', 'Signed in as @${widget.username}'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password,
                    autofocus: true,
                    obscureText: _obscure,
                    enableSuggestions: false,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _confirm(),
                    decoration: InputDecoration(
                      labelText: _tr('当前密码', 'Current password'),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _obscure
                            ? _tr('显示密码', 'Show password')
                            : _tr('隐藏密码', 'Hide password'),
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _confirm,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_user_outlined),
                    label: Text(_tr('确认访问', 'Confirm access')),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _sendPasswordReset,
                    child: Text(_tr('忘记密码？', 'Forgot password?')),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
