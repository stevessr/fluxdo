import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/s.dart';
import '../services/qr_login_service.dart';
import '../services/toast_service.dart';
import 'package:m3e_ui/m3e_ui.dart';

/// 已登录设备:展示用于另一台设备扫码登录的二维码。
///
/// 二维码携带当前 `_t` 会话,短时有效;过期后可一键刷新。
class QrLoginDisplayPage extends StatefulWidget {
  const QrLoginDisplayPage({super.key, this.username});

  /// 可选,展示用用户名(不传则服务里再取)
  final String? username;

  @override
  State<QrLoginDisplayPage> createState() => _QrLoginDisplayPageState();
}

class _QrLoginDisplayPageState extends State<QrLoginDisplayPage> {
  String? _raw;
  QrLoginPayload? _payload;
  String? _error;
  bool _loading = true;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await QrLoginService.instance.buildPayload(
        username: widget.username,
      );
      if (!mounted) return;
      setState(() {
        _raw = result.raw;
        _payload = result.payload;
        _loading = false;
      });
      _restartTicker();
    } on QrLoginException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
        _raw = null;
        _payload = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = S.current.login_qrGenerateFailed;
        _loading = false;
        _raw = null;
        _payload = null;
      });
      debugPrint('[QrLoginDisplay] 生成失败: $e');
    }
  }

  void _restartTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final payload = _payload;
      if (payload == null) return;
      if (payload.isExpired) {
        setState(() {}); // 触发"已过期"UI
        _ticker?.cancel();
        return;
      }
      setState(() {}); // 刷新倒计时
    });
  }

  String _formatRemaining(Duration d) {
    final total = d.inSeconds;
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final payload = _payload;
    final expired = payload?.isExpired ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.login_qrDisplayTitle),
        actions: [
          IconButton(
            tooltip: context.l10n.login_qrRefresh,
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Symbols.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.login_qrDisplayHint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildQrCard(theme, scheme, expired),
                  const SizedBox(height: 20),
                  if (payload != null && !expired)
                    Text(
                      context.l10n.login_qrExpiresIn(
                        _formatRemaining(payload.remaining),
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (payload != null && expired) ...[
                    Text(
                      context.l10n.login_qrExpired,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loading ? null : _refresh,
                      icon: const Icon(Symbols.refresh_rounded),
                      label: Text(context.l10n.login_qrRefresh),
                    ),
                  ],
                  if (payload != null && payload.username.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.login_qrAccount(payload.username),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Symbols.warning_rounded,
                          size: 20,
                          color: scheme.error,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            context.l10n.login_qrSecurityWarning,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQrCard(ThemeData theme, ColorScheme scheme, bool expired) {
    if (_loading) {
      return const SizedBox(
        height: 280,
        child: Center(child: LoadingSpinner(size: 40)),
      );
    }
    if (_error != null) {
      return Column(
        children: [
          Icon(Symbols.error_rounded, size: 48, color: scheme.error),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _refresh,
            child: Text(context.l10n.common_retry),
          ),
        ],
      );
    }
    final raw = _raw;
    if (raw == null) {
      return const SizedBox.shrink();
    }

    return AnimatedOpacity(
      opacity: expired ? 0.35 : 1,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.35 : 0.08,
              ),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: QrImageView(
          data: raw,
          version: QrVersions.auto,
          size: 260,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Colors.black,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.black,
          ),
          errorStateBuilder: (context, error) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ToastService.showError(S.current.login_qrGenerateFailed);
              }
            });
            return Center(
              child: Text(
                S.current.login_qrGenerateFailed,
                style: const TextStyle(color: Colors.red),
              ),
            );
          },
        ),
      ),
    );
  }
}
