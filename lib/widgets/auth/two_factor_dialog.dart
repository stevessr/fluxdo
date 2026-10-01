import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Discourse 支持的非 WebAuthn 二步验证方式。
enum DirectTwoFactorMethod {
  totp(1),
  backupCode(2);

  const DirectTwoFactorMethod(this.discourseValue);

  final int discourseValue;
}

/// 直接登录使用的二步验证提交值。
class TwoFactorSubmission {
  const TwoFactorSubmission({required this.token, required this.method});

  final String token;
  final DirectTwoFactorMethod method;
}

/// 二步验证输入对话框。
///
/// 直接支持 TOTP 与备用码。安全密钥 / Passkey 仍交给完整 Web 登录流程，
/// 避免在原生表单里复制 WebAuthn ceremony。
Future<TwoFactorSubmission?> showTwoFactorDialog(
  BuildContext context, {
  String? hint,
  bool totpEnabled = true,
  bool backupEnabled = false,
  bool securityKeyEnabled = false,
  VoidCallback? onUseWebLogin,
}) {
  return showDialog<TwoFactorSubmission>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TwoFactorDialog(
      hint: hint,
      totpEnabled: totpEnabled,
      backupEnabled: backupEnabled,
      securityKeyEnabled: securityKeyEnabled,
      onUseWebLogin: onUseWebLogin,
    ),
  );
}

class _TwoFactorDialog extends StatefulWidget {
  const _TwoFactorDialog({
    this.hint,
    required this.totpEnabled,
    required this.backupEnabled,
    required this.securityKeyEnabled,
    this.onUseWebLogin,
  });

  final String? hint;
  final bool totpEnabled;
  final bool backupEnabled;
  final bool securityKeyEnabled;
  final VoidCallback? onUseWebLogin;

  @override
  State<_TwoFactorDialog> createState() => _TwoFactorDialogState();
}

class _TwoFactorDialogState extends State<_TwoFactorDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late DirectTwoFactorMethod _method;

  bool get _isTotp => _method == DirectTwoFactorMethod.totp;

  bool get _hasDirectMethod => widget.totpEnabled || widget.backupEnabled;

  @override
  void initState() {
    super.initState();
    _method = widget.totpEnabled
        ? DirectTwoFactorMethod.totp
        : DirectTwoFactorMethod.backupCode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_hasDirectMethod) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _isValid(String raw) {
    final token = raw.trim();
    if (_isTotp) {
      return RegExp(r'^\d{6}$').hasMatch(token);
    }
    return token.isNotEmpty;
  }

  void _switchMethod(DirectTwoFactorMethod method) {
    if (_method == method) return;
    setState(() {
      _method = method;
      _controller.clear();
    });
    _focusNode.requestFocus();
  }

  void _submit() {
    final token = _controller.text.trim();
    if (!_isValid(token)) return;
    Navigator.of(context)
        .pop(TwoFactorSubmission(token: token, method: _method));
  }

  void _useWebLogin() {
    Navigator.of(context).pop();
    widget.onUseWebLogin?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasMethodSwitcher = widget.totpEnabled && widget.backupEnabled;
    final directUnavailable = !_hasDirectMethod;

    return AlertDialog(
      title: const Text('二步验证'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.hint ??
                (directUnavailable
                    ? '此账号需要使用安全密钥完成二步验证'
                    : _isTotp
                    ? '请输入身份验证器 App 显示的 6 位验证码'
                    : '请输入一个备用验证码'),
            style: theme.textTheme.bodySmall,
          ),
          if (hasMethodSwitcher) ...[
            const SizedBox(height: 14),
            SegmentedButton<DirectTwoFactorMethod>(
              segments: const [
                ButtonSegment(
                  value: DirectTwoFactorMethod.totp,
                  label: Text('验证器'),
                  icon: Icon(Icons.password_rounded),
                ),
                ButtonSegment(
                  value: DirectTwoFactorMethod.backupCode,
                  label: Text('备用码'),
                  icon: Icon(Icons.key_rounded),
                ),
              ],
              selected: {_method},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  _switchMethod(selection.first);
                }
              },
            ),
          ],
          if (!directUnavailable) ...[
            const SizedBox(height: 16),
            TextField(
              key: ValueKey(_method),
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: _isTotp ? TextInputType.number : TextInputType.text,
              textAlign: TextAlign.center,
              autofillHints: _isTotp ? const [AutofillHints.oneTimeCode] : null,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(
                fontSize: _isTotp ? 24 : 18,
                letterSpacing: _isTotp ? 8 : 2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              inputFormatters: _isTotp
                  ? [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ]
                  : [LengthLimitingTextInputFormatter(64)],
              decoration: InputDecoration(
                hintText: _isTotp ? '000000' : '备用验证码',
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                if (_isTotp && _isValid(value)) {
                  _submit();
                }
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (widget.securityKeyEnabled && widget.onUseWebLogin != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _useWebLogin,
                icon: const Icon(Icons.usb_rounded),
                label: const Text('使用安全密钥 / Passkey 登录'),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        if (!directUnavailable)
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (_, value, _) {
              final enabled = _isValid(value.text);
              return FilledButton(
                onPressed: enabled ? _submit : null,
                child: const Text('验证'),
              );
            },
          )
        else if (widget.onUseWebLogin != null)
          FilledButton(onPressed: _useWebLogin, child: const Text('使用 Web 登录')),
      ],
    );
  }
}
