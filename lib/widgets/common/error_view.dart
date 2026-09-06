import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';

import '../../l10n/s.dart';
import '../../pages/network_settings_page/network_settings_page.dart';
import '../../services/cf_challenge_service.dart';
import '../../services/network/cookie/boundary_sync_service.dart';
import '../../services/network/cookie/cookie_jar_service.dart';
import '../../services/network/exceptions/api_exception.dart';
import '../../services/toast_service.dart';
import '../../utils/dialog_utils.dart';
import 'app_bottom_sheet.dart';
import '../../utils/error_utils.dart';

/// 通用错误页面组件
/// 显示语义化的错误提示，并提供查看详情和重试功能
class ErrorView extends StatefulWidget {
  const ErrorView({
    super.key,
    required this.error,
    this.stackTrace,
    this.onRetry,
    this.icon,
    this.iconSize = 48,
    this.title,
    this.retryLabel,
    this.showDetails = true,
  });

  /// 错误对象
  final Object error;

  /// 堆栈跟踪（可选）
  final StackTrace? stackTrace;

  /// 重试回调
  final VoidCallback? onRetry;

  /// 自定义图标
  final IconData? icon;

  /// 图标大小
  final double iconSize;

  /// 自定义标题（默认为"加载失败"）
  final String? title;

  /// 自定义重试按钮文案（默认为"重试"）
  final String? retryLabel;

  /// 是否显示"查看详情"按钮
  final bool showDetails;

  @override
  State<ErrorView> createState() => _ErrorViewState();
}

class _ErrorViewState extends State<ErrorView> {
  bool _actionInProgress = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorInfo = ErrorUtils.getErrorInfo(widget.error);
    final isCfChallengeError = _isCfChallengeError(widget.error);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ErrorIconBadge(icon: widget.icon ?? errorInfo.icon),
              const SizedBox(height: 24),
              Text(
                widget.title ?? errorInfo.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                errorInfo.message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              ..._buildActions(
                context,
                theme: theme,
                errorInfo: errorInfo,
                isCfChallengeError: isCfChallengeError,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(
    BuildContext context, {
    required ThemeData theme,
    required ErrorInfo errorInfo,
    required bool isCfChallengeError,
  }) {
    final widgets = <Widget>[];

    // 主按钮：CF 验证 / 重试
    if (isCfChallengeError) {
      widgets.add(
        _PrimaryButton(
          label: context.l10n.cf_manualVerifyAction,
          isLoading: _actionInProgress,
          onPressed: _actionInProgress
              ? null
              : () => _runManualCfVerify(context),
        ),
      );
    } else if (widget.onRetry != null) {
      widgets.add(
        _PrimaryButton(
          label: widget.retryLabel ?? context.l10n.common_retry,
          isLoading: _actionInProgress,
          onPressed: _actionInProgress ? null : _runRetry,
        ),
      );
    }

    // 辅助操作：横向排列的扁平 icon+文字按钮。
    // CF 验证 + 重试 / 网络设置 / 查看详情都收纳到这里，
    // 形成"一个主按钮 + 一排快捷入口"的清爽布局。
    final helperActions = <Widget>[
      if (isCfChallengeError && widget.onRetry != null)
        _HelperAction(
          icon: Symbols.refresh_rounded,
          label: context.l10n.common_retry,
          isLoading: _actionInProgress,
          onPressed: _actionInProgress ? null : _runCfRetry,
        ),
      if (errorInfo.isNetworkError)
        _HelperAction(
          icon: Symbols.tune_rounded,
          label: context.l10n.error_openNetworkSettings,
          onPressed: _actionInProgress
              ? null
              : () => _openNetworkSettings(context),
        ),
      if (widget.showDetails)
        _HelperAction(
          icon: Symbols.info_rounded,
          label: context.l10n.common_viewDetails,
          onPressed: _actionInProgress
              ? null
              : () => _showErrorDetails(context),
        ),
    ];

    if (helperActions.isNotEmpty) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 16));
      widgets.add(
        Wrap(
          spacing: 4,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: helperActions,
        ),
      );
    }

    return widgets;
  }

  bool _isCfChallengeError(Object error) {
    if (error is CfChallengeException) return true;
    if (error is DioException && error.error is CfChallengeException) {
      return true;
    }
    return false;
  }

  Future<void> _runManualCfVerify(BuildContext context) async {
    if (_actionInProgress) return;
    _setActionInProgress(true);
    HapticFeedback.selectionClick();

    try {
      final result = await CfChallengeService().showManualVerifyNow(
        context,
        true,
      );
      if (!mounted) return;

      if (result == true) {
        // showManualVerify 的少数快速完成路径会先返回 true，再异步把
        // WebView 的 cf_clearance 落到 CookieJar。错误页若立刻 onRetry，
        // 原请求就可能继续携带旧/空 Cookie 再次撞盾，看起来像“验证通过但
        // 重试没反应”。这里在离开错误态前显式等待边界同步收敛。
        await _syncCfClearanceAfterVerify();
        if (!mounted) return;
        ToastService.showSuccess(S.current.cfVerify_success);
        widget.onRetry?.call();
        return;
      }

      if (result == false) {
        ToastService.showError(S.current.cf_verifyIncomplete);
        return;
      }

      ToastService.showError(S.current.cf_cannotOpenVerifyPage);
    } finally {
      _setActionInProgress(false);
    }
  }

  Future<void> _runCfRetry() async {
    if (_actionInProgress || widget.onRetry == null) return;
    _setActionInProgress(true);
    HapticFeedback.selectionClick();

    try {
      // 用户可能已经在验证页完成挑战，只是上一轮快速返回时 CookieJar 还
      // 没追上 WebView。重试前做一次短暂的 best-effort 同步，避免继续拿
      // 旧 Cookie 重放请求；即使同步最终没读到值，也仍尊重用户的“重试”。
      await _syncCfClearanceBestEffort();
      if (!mounted) return;
      widget.onRetry?.call();
      await Future<void>.delayed(const Duration(milliseconds: 450));
    } finally {
      _setActionInProgress(false);
    }
  }

  Future<void> _runRetry() async {
    if (_actionInProgress || widget.onRetry == null) return;
    _setActionInProgress(true);
    HapticFeedback.selectionClick();

    try {
      widget.onRetry?.call();
      // onRetry 的历史 API 是 VoidCallback，无法可靠 await 调用方的异步加载。
      // 保留一个很短的忙碌态，至少给用户明确的点击反馈并阻止连点风暴；
      // 页面正常进入 loading / data 状态后本 ErrorView 通常会直接卸载。
      await Future<void>.delayed(const Duration(milliseconds: 450));
    } finally {
      _setActionInProgress(false);
    }
  }

  Future<bool> _syncCfClearanceAfterVerify() async {
    final cookieJar = CookieJarService();

    // 验证流程开始时会删除已失效的 cf_clearance，所以成功后的非空值可以
    // 作为“新 clearance 已真正进入网络层”的信号。WebView/原生 Cookie
    // 提交存在轻微时序差，最多给 4 次短重试，总额约 1.5 秒。
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      await BoundarySyncService.instance.syncFromWebView(
        cookieNames: const {'cf_clearance'},
        trusted: true,
      );
      final clearance = await cookieJar.getCfClearance();
      if (clearance != null && clearance.isNotEmpty) {
        return true;
      }
    }

    return false;
  }

  Future<void> _syncCfClearanceBestEffort() async {
    try {
      await BoundarySyncService.instance.syncFromWebView(
        cookieNames: const {'cf_clearance'},
        trusted: true,
      );
    } catch (_) {
      // 重试按钮本身不能因为边界同步失败而失效。真正请求会继续走统一的
      // CF interceptor，并在仍被盾拦截时重新进入验证流程。
    }
  }

  void _setActionInProgress(bool value) {
    if (!mounted || _actionInProgress == value) return;
    setState(() {
      _actionInProgress = value;
    });
  }

  void _openNetworkSettings(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NetworkSettingsPage()));
  }

  void _showErrorDetails(BuildContext context) {
    final details = ErrorUtils.getErrorDetails(
      widget.error,
      widget.stackTrace,
    );

    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ErrorDetailsSheet(details: details),
    );
  }
}

/// 错误详情底部弹窗
///
/// 风格对齐项目通用 sheet（书签/打赏/AI 模型选择等）：
/// 外层 margin 16 + 圆角 16 + surface 背景 + drag handle + 标题栏。
class ErrorDetailsSheet extends StatelessWidget {
  const ErrorDetailsSheet({super.key, required this.details});

  final String details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppSheetScaffold(
      contentPadding: EdgeInsets.zero,
      showTitleDivider: true,
      titleWidget: Row(
        children: [
          Icon(
            Symbols.bug_report_rounded,
            size: 20,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Text(
            context.l10n.common_errorDetails,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Symbols.content_copy_rounded, size: 20),
          tooltip: context.l10n.common_copy,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: details));
            ToastService.showSuccess(S.current.common_copiedToClipboard);
          },
        ),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: SelectableText(
          details,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

/// Sliver 版本的错误视图（用于 CustomScrollView）
class SliverErrorView extends StatelessWidget {
  const SliverErrorView({
    super.key,
    required this.error,
    this.stackTrace,
    this.onRetry,
    this.icon,
    this.iconSize = 48,
    this.title,
    this.retryLabel,
    this.showDetails = true,
  });

  final Object error;
  final StackTrace? stackTrace;
  final VoidCallback? onRetry;
  final IconData? icon;
  final double iconSize;
  final String? title;
  final String? retryLabel;
  final bool showDetails;

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: ErrorView(
        error: error,
        stackTrace: stackTrace,
        onRetry: onRetry,
        icon: icon,
        iconSize: iconSize,
        title: title,
        retryLabel: retryLabel,
        showDetails: showDetails,
      ),
    );
  }
}

/// 行内错误视图：用于卡片内/列表项内的局部错误，不占满整屏。
///
/// 风格：errorContainer 淡色底 + 圆角 12 + Row(icon + 文字 + 可选重试)。
/// 与 ErrorView 共享同一套错误信息源（ErrorUtils.getErrorInfo），
/// 但形态更紧凑，适合 topic summary 卡、AI 消息气泡、stats 卡等场景。
class InlineErrorView extends StatelessWidget {
  const InlineErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.message,
    this.compact = false,
  });

  /// 错误对象
  final Object error;

  /// 重试回调
  final VoidCallback? onRetry;

  /// 自定义错误文案。null 时取 ErrorUtils.getErrorInfo(error).title。
  final String? message;

  /// 紧凑模式：更小的图标和内边距，适合放在小卡片里。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorInfo = ErrorUtils.getErrorInfo(error);
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
        : const EdgeInsets.all(16);
    final iconSize = compact ? 18.0 : 20.0;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.error.withValues(alpha: 0.08)
            : theme.colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(errorInfo.icon, size: iconSize, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message ?? errorInfo.title,
              style:
                  (compact
                          ? theme.textTheme.bodySmall
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: theme.colorScheme.primary,
                textStyle: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(context.l10n.common_retry),
            ),
          ],
        ],
      ),
    );
  }
}

/// 错误图标徽章：圆角方形容器 + 淡色背景 + 主色图标。
/// 给图标一个"家"，是整页的视觉焦点。
class _ErrorIconBadge extends StatelessWidget {
  const _ErrorIconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // 暗色模式下用更高对比的容器色，浅色用 errorContainer
    final bgColor = isDark
        ? theme.colorScheme.error.withValues(alpha: 0.12)
        : theme.colorScheme.errorContainer.withValues(alpha: 0.6);
    final fgColor = isDark
        ? theme.colorScheme.error
        : theme.colorScheme.onErrorContainer;

    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Icon(icon, size: 36, color: fgColor),
    );
  }
}

/// 主操作按钮：内嵌胶囊（自适应宽度），48 高，加粗文字。
/// 不强求全宽，让按钮回归"自然尺寸"，更精致。
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 36),
          textStyle: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          elevation: 0,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: isLoading
              ? const SizedBox(
                  key: ValueKey('loading'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : Text(label, key: const ValueKey('label')),
        ),
      ),
    );
  }
}

/// 辅助操作：上 icon + 下小字的扁平按钮。
/// 多个时横向排列，视觉权重低，类似 Notion / 微信错误页底部的快捷入口。
class _HelperAction extends StatelessWidget {
  const _HelperAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    final color = enabled
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: isLoading
                  ? CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    )
                  : Icon(icon, size: 20, color: color),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
