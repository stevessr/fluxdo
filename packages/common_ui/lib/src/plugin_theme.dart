import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import 'ui_shapes.dart';

/// Versioned, presentation-only snapshot for independently installed plugins.
/// No account, wallpaper path, or session data crosses the APK boundary.
class PluginTheme {
  static String encode(ThemeData theme) {
    final scheme = theme.colorScheme;
    final shapes = theme.extension<UiShapes>() ?? UiShapes.standard;
    final border = theme.inputDecorationTheme.border ??
        theme.inputDecorationTheme.enabledBorder;
    return jsonEncode({
      'version': 1,
      'dark': scheme.brightness == Brightness.dark,
      'colors': {
        'primary': scheme.primary.toARGB32(),
        'onPrimary': scheme.onPrimary.toARGB32(),
        'primaryContainer': scheme.primaryContainer.toARGB32(),
        'onPrimaryContainer': scheme.onPrimaryContainer.toARGB32(),
        'secondary': scheme.secondary.toARGB32(),
        'onSecondary': scheme.onSecondary.toARGB32(),
        'secondaryContainer': scheme.secondaryContainer.toARGB32(),
        'onSecondaryContainer': scheme.onSecondaryContainer.toARGB32(),
        'tertiary': scheme.tertiary.toARGB32(),
        'onTertiary': scheme.onTertiary.toARGB32(),
        'tertiaryContainer': scheme.tertiaryContainer.toARGB32(),
        'onTertiaryContainer': scheme.onTertiaryContainer.toARGB32(),
        'error': scheme.error.toARGB32(),
        'onError': scheme.onError.toARGB32(),
        'errorContainer': scheme.errorContainer.toARGB32(),
        'onErrorContainer': scheme.onErrorContainer.toARGB32(),
        'surface': scheme.surface.toARGB32(),
        'onSurface': scheme.onSurface.toARGB32(),
        'onSurfaceVariant': scheme.onSurfaceVariant.toARGB32(),
        'outline': scheme.outline.toARGB32(),
        'outlineVariant': scheme.outlineVariant.toARGB32(),
        'shadow': scheme.shadow.toARGB32(),
        'scrim': scheme.scrim.toARGB32(),
        'inverseSurface': scheme.inverseSurface.toARGB32(),
        'onInverseSurface': scheme.onInverseSurface.toARGB32(),
        'inversePrimary': scheme.inversePrimary.toARGB32(),
        'surfaceTint': scheme.surfaceTint.toARGB32(),
        'surfaceDim': scheme.surfaceDim.toARGB32(),
        'surfaceBright': scheme.surfaceBright.toARGB32(),
        'surfaceContainerLowest': scheme.surfaceContainerLowest.toARGB32(),
        'surfaceContainerLow': scheme.surfaceContainerLow.toARGB32(),
        'surfaceContainer': scheme.surfaceContainer.toARGB32(),
        'surfaceContainerHigh': scheme.surfaceContainerHigh.toARGB32(),
        'surfaceContainerHighest': scheme.surfaceContainerHighest.toARGB32(),
      },
      'background': (theme.scaffoldBackgroundColor.a < 1
          ? Color.alphaBlend(theme.scaffoldBackgroundColor, scheme.surface)
          : theme.scaffoldBackgroundColor).toARGB32(),
      'shapeScale': shapes.scale,
      'shapeMax': shapes.max,
      'inputBorder': border is UnderlineInputBorder
          ? 'underline'
          : border is OutlineInputBorder ? 'outline' : 'none',
    });
  }

  /// Unknown or malformed snapshots safely fall back to the platform theme.
  static ThemeData? decode(String? payload) {
    if (payload == null || payload.length > 8192) return null;
    try {
      final data = jsonDecode(payload);
      if (data is! Map || data['version'] != 1 || data['dark'] is! bool) {
        return null;
      }
      final colors = data['colors'];
      if (colors is! Map) return null;
      Color? color(Object? value) =>
          value is int && value >= 0 && value <= 0xffffffff
              ? Color(value)
              : null;
      final primary = color(colors['primary']);
      if (primary == null) return null;
      final brightness =
          data['dark'] == true ? Brightness.dark : Brightness.light;
      final scheme = ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
      ).copyWith(
        primary: color(colors['primary']),
        onPrimary: color(colors['onPrimary']),
        primaryContainer: color(colors['primaryContainer']),
        onPrimaryContainer: color(colors['onPrimaryContainer']),
        secondary: color(colors['secondary']),
        onSecondary: color(colors['onSecondary']),
        secondaryContainer: color(colors['secondaryContainer']),
        onSecondaryContainer: color(colors['onSecondaryContainer']),
        tertiary: color(colors['tertiary']),
        onTertiary: color(colors['onTertiary']),
        tertiaryContainer: color(colors['tertiaryContainer']),
        onTertiaryContainer: color(colors['onTertiaryContainer']),
        error: color(colors['error']),
        onError: color(colors['onError']),
        errorContainer: color(colors['errorContainer']),
        onErrorContainer: color(colors['onErrorContainer']),
        surface: color(colors['surface']),
        onSurface: color(colors['onSurface']),
        onSurfaceVariant: color(colors['onSurfaceVariant']),
        outline: color(colors['outline']),
        outlineVariant: color(colors['outlineVariant']),
        shadow: color(colors['shadow']),
        scrim: color(colors['scrim']),
        inverseSurface: color(colors['inverseSurface']),
        onInverseSurface: color(colors['onInverseSurface']),
        inversePrimary: color(colors['inversePrimary']),
        surfaceTint: color(colors['surfaceTint']),
        surfaceDim: color(colors['surfaceDim']),
        surfaceBright: color(colors['surfaceBright']),
        surfaceContainerLowest: color(colors['surfaceContainerLowest']),
        surfaceContainerLow: color(colors['surfaceContainerLow']),
        surfaceContainer: color(colors['surfaceContainer']),
        surfaceContainerHigh: color(colors['surfaceContainerHigh']),
        surfaceContainerHighest: color(colors['surfaceContainerHighest']),
      );
      double? dimension(Object? value) =>
          value is num && value.isFinite && value >= 0 && value <= 10000
              ? value.toDouble()
              : null;
      final shapes = UiShapes(
        scale: dimension(data['shapeScale']) ?? 1,
        max: dimension(data['shapeMax']),
      );
      final radius = shapes.borderRadius(12);
      final InputBorder border = switch (data['inputBorder']) {
        'underline' => UnderlineInputBorder(borderRadius: radius),
        'outline' => OutlineInputBorder(borderRadius: radius),
        _ => InputBorder.none,
      };
      final shape = RoundedSuperellipseBorder(
        borderRadius: shapes.borderRadius(16),
      );
      final buttonStyle = ButtonStyle(
        shape: WidgetStatePropertyAll(RoundedSuperellipseBorder(
          borderRadius: shapes.borderRadius(9999),
        )),
      );
      return ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: color(data['background']) ?? scheme.surface,
        extensions: [shapes],
        cardTheme: CardThemeData(shape: shape),
        filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
        outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
        textButtonTheme: TextButtonThemeData(style: buttonStyle),
        inputDecorationTheme: InputDecorationThemeData(
          border: border,
          enabledBorder: border == InputBorder.none ? border : border.copyWith(
            borderSide: BorderSide(color: scheme.outline),
          ),
          focusedBorder: border == InputBorder.none ? border : border.copyWith(
            borderSide: BorderSide(color: scheme.primary, width: 2),
          ),
        ),
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}
