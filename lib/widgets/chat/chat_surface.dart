import 'package:common_ui/common_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/theme_style.dart';

/// 频道与消息串共用的消息表面。保留发送方的语义色对，
/// 其余容器随主题风格换档，避免素色主题仍出现厚重的色块。
class ChatSurface {
  const ChatSurface._();

  static Color incomingColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (context.themeStyle.surfaces) {
      SurfaceStyle.filled => scheme.surfaceContainerHighest,
      SurfaceStyle.outlined => scheme.surface,
      SurfaceStyle.flat => scheme.surfaceContainerLow,
      SurfaceStyle.raised => raisedSurfaceColor(scheme),
    };
  }

  static BorderSide outline(BuildContext context) {
    return context.themeStyle.surfaces.hasOutline
        ? BorderSide(color: Theme.of(context).colorScheme.outlineVariant)
        : BorderSide.none;
  }

  static BoxDecoration bubble(
    BuildContext context, {
    required bool isOwn,
    bool isOriginal = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final side = isOriginal
        ? BorderSide(color: context.emphasis.selected.withValues(alpha: 0.6))
        : outline(context);
    return BoxDecoration(
      color: isOwn ? scheme.primaryContainer : incomingColor(context),
      borderRadius: context.shapes.borderRadius(18).copyWith(
        bottomLeft: context.shapes.radius(isOwn ? 18 : 4),
        bottomRight: context.shapes.radius(isOwn ? 4 : 18),
      ),
      border: side == BorderSide.none ? null : Border.fromBorderSide(side),
    );
  }

  static ShapeBorder previewShape(BuildContext context) =>
      RoundedSuperellipseBorder(
        borderRadius: context.shapes.borderRadius(16),
        side: outline(context),
      );
}
