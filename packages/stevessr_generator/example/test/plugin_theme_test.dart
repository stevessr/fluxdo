import 'package:common_ui/common_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('host palette and shape tokens survive cross-APK roundtrip', () {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff447766),
      brightness: Brightness.dark,
    );
    final original = ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xff112233),
      extensions: const [UiShapes(scale: 0.5, max: 8)],
    );
    final received = PluginTheme.decode(PluginTheme.encode(original))!;
    expect(received.brightness, Brightness.dark);
    expect(received.colorScheme.primary, scheme.primary);
    expect(received.colorScheme.surfaceContainer, scheme.surfaceContainer);
    expect(received.scaffoldBackgroundColor, original.scaffoldBackgroundColor);
    expect(received.extension<UiShapes>(), const UiShapes(scale: 0.5, max: 8));
  });

  test('missing, corrupt and unsupported snapshots fall back', () {
    for (final value in [null, 'bad json', '{}', '{"version":2}', '{"version":1,"dark":true,"colors":{}}']) {
      expect(PluginTheme.decode(value), isNull);
    }
  });
}
