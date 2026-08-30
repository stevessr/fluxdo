import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../services/account_manager.dart';
import '../../utils/url_helper.dart';
import '../common/smart_avatar.dart';

/// Unified visual feedback used while switching accounts.
///
/// Every account-switch entry point should render this instead of maintaining
/// its own spinner/cover so the target account stays obvious during the
/// session/cache transition.
class AccountSwitchLoading extends StatelessWidget {
  const AccountSwitchLoading({
    super.key,
    required this.account,
    this.padding = EdgeInsets.zero,
    this.avatarRadius = 30,
    this.progressWidth = 168,
  });

  final SavedAccount account;
  final EdgeInsetsGeometry padding;
  final double avatarRadius;
  final double progressWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final template = account.avatarTemplate;
    final imageUrl = template != null && template.isNotEmpty
        ? UrlHelper.resolveUrlWithCdn(template.replaceAll('{size}', '128'))
        : null;

    return Semantics(
      liveRegion: true,
      label: context.l10n.accountManage_switching,
      child: Padding(
        padding: padding,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.94, end: 1),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            final opacity = ((value - 0.94) / 0.06)
                .clamp(0.0, 1.0)
                .toDouble();
            return Opacity(
              opacity: opacity,
              child: Transform.scale(scale: value, child: child),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SmartAvatar(
                imageUrl: imageUrl,
                radius: avatarRadius,
                fallbackText: account.username,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
              const SizedBox(height: 14),
              Text(
                account.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: progressWidth,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen account-switch cover for overlay-based quick switchers.
class AccountSwitchLoadingCover extends StatelessWidget {
  const AccountSwitchLoadingCover({super.key, required this.account});

  final SavedAccount account;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Material(
          color: scheme.surface.withValues(alpha: 0.96),
          child: SafeArea(
            child: Center(child: AccountSwitchLoading(account: account)),
          ),
        ),
      ),
    );
  }
}
