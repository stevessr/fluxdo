import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';

import 'package:m3e_ui/m3e_ui.dart';

import '../../l10n/s.dart';
import '../../services/auth_session.dart';
import '../../services/cf_challenge_service.dart';
import '../../services/discourse/discourse_service.dart';
import '../../services/network/cookie/boundary_sync_service.dart';
import '../../services/network/cookie/cookie_jar_service.dart';
import '../../services/toast_service.dart';
import 'passkey_login_dialog.dart';

/// username/email + password 输入表单。提交逻辑 (调 DiscourseService 登录 +
/// 处理 hcaptcha/2FA/跳转) 由父组件持有,form 本身只负责 UI 和数据校验。
class LoginForm extends StatefulWidget {
  const LoginForm({
    super.key,
    required this.onSubmit,
    this.onForgotPassword,
    this.savedUsername,
    this.savedPassword,
  });

  /// 提交回调。父组件返 true = 成功 (form 清空 password), false = 失败 (form 保留)。
  final Future<bool> Function({
    required String identifier,
    required String password,
    required bool rememberCredentials,
  }) onSubmit;

  /// 忘记密码点击 (一般跳 webview)。
  final VoidCallback? onForgotPassword;

  /// 上次保存的账号 (来自 [CredentialStoreService])。
  final String? savedUsername;
  final String? savedPassword;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _passwordCtrl;
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  bool _obscure = true;
  bool _remember = false;
  bool _submitting = false;
  bool _passkeySubmitting = false;

  bool get _busy => _submitting || _passkeySubmitting;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(text: widget.savedUsername ?? '');
    _passwordCtrl = TextEditingController(text: widget.savedPassword ?? '');
    _remember =
        (widget.savedPassword != null && widget.savedPassword!.isNotEmpty);
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final identifier = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (identifier.isEmpty || password.isEmpty) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _submitting = true);
    try {
      final ok = await widget.onSubmit(
        identifier: identifier,
        password: password,
        rememberCredentials: _remember,
      );
      if (ok && mounted) {
        _passwordCtrl.clear();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<bool> _ensureCfClearance() async {
    final jar = CookieJarService();
    var clearance = await jar.getCfClearance();
    if (clearance != null && clearance.isNotEmpty) return true;
    if (!mounted) return false;

    final requestGeneration = AuthSession().generation;
    final ok = await CfChallengeService().showManualVerify(context, true);
    if (ok != true) return false;

    await Future<void>.delayed(const Duration(milliseconds: 1500));
    for (var i = 0; i < 3; i++) {
      await BoundarySyncService.instance.syncFromWebView(
        cookieNames: null,
        excludeCookieNames: CookieJarService.authCookieNames,
        requestGeneration: requestGeneration,
      );
      clearance = await jar.getCfClearance();
      if (clearance != null && clearance.isNotEmpty) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// Passkey 直连登录测试入口。
  ///
  /// 不打开 linux.do 登录页面；真正的 WebAuthn ceremony 在轻量同源 WebView
  /// 中完成，成功后复用现有 CookieJar / native login 收口。
  Future<void> _loginWithPasskey() async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _passkeySubmitting = true);
    try {
      if (!await _ensureCfClearance()) {
        if (mounted) {
          ToastService.showError('Cloudflare 验证未完成,请重试');
        }
        return;
      }
      if (!mounted) return;

      final result = await showPasskeyLoginDialog(context);
      if (!mounted ||
          result == null ||
          result.status == PasskeyLoginStatus.canceled) {
        return;
      }

      if (result.status == PasskeyLoginStatus.success) {
        final username = result.username;
        if (username == null || username.isEmpty) {
          ToastService.showError('Passkey 登录成功但无法读取用户名');
          return;
        }
        await DiscourseService().finalizeNativeLoginSuccess(username);
        if (!mounted) return;
        ToastService.showSuccess(S.current.webviewLogin_loginSuccess);
        Navigator.of(context).pop(true);
        return;
      }

      ToastService.showError(result.errorMessage ?? 'Passkey 登录失败');
    } finally {
      if (mounted) setState(() => _passkeySubmitting = false);
    }
  }

  InputDecoration _inputDecoration(
    ColorScheme scheme, {
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      border: border(Colors.transparent, 0),
      enabledBorder: border(Colors.transparent, 0),
      focusedBorder: border(scheme.primary, 1.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _usernameCtrl,
            focusNode: _usernameFocus,
            enabled: !_busy,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: _inputDecoration(
              scheme,
              label: '用户名 / 邮箱',
              icon: Symbols.person_rounded,
            ),
            onSubmitted: (_) => _passwordFocus.requestFocus(),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passwordCtrl,
            focusNode: _passwordFocus,
            enabled: !_busy,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.go,
            obscureText: _obscure,
            decoration: _inputDecoration(
              scheme,
              label: '密码',
              icon: Symbols.lock_rounded,
              suffixIcon: IconButton(
                tooltip: _obscure ? '显示密码' : '隐藏密码',
                icon: Icon(
                  _obscure
                      ? Symbols.visibility_rounded
                      : Symbols.visibility_off_rounded,
                ),
                onPressed: _busy
                    ? null
                    : () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Checkbox(
                value: _remember,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _remember = v ?? false),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _busy
                      ? null
                      : () => setState(() => _remember = !_remember),
                  child: const Text('记住密码'),
                ),
              ),
              if (widget.onForgotPassword != null)
                TextButton(
                  onPressed: _busy ? null : widget.onForgotPassword,
                  child: const Text('忘记密码?'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              elevation: 8,
              shadowColor: scheme.primary.withValues(alpha: 0.4),
            ),
            child: _submitting
                ? LoadingSpinner(size: 24, color: scheme.onPrimary)
                : const Text(
                    '登录',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _loginWithPasskey,
            icon: _passkeySubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: LoadingSpinner(size: 20),
                  )
                : const Icon(Symbols.fingerprint_rounded, size: 20),
            label: const Text('Passkey 登录'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
