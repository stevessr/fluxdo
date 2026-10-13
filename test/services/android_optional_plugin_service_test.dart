import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/android_optional_plugin_service.dart';

void main() {
  group('Android optional plugin account partition', () {
    test('guest is explicit and never hashes into a remembered user slot', () {
      expect(AndroidOptionalPluginService.sessionSlotForUsername(null), 'guest');
      expect(AndroidOptionalPluginService.sessionSlotForUsername(''), 'guest');
      expect(AndroidOptionalPluginService.sessionSlotForUsername('   '), 'guest');
    });

    test('same username maps to the same opaque 64 character slot', () {
      final a = AndroidOptionalPluginService.sessionSlotForUsername(' Alice ');
      final b = AndroidOptionalPluginService.sessionSlotForUsername('alice');
      expect(a, b);
      expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(a, isNot(contains('alice')));
    });

    test('different users do not share the same WebView session slot', () {
      final a = AndroidOptionalPluginService.sessionSlotForUsername('alice');
      final b = AndroidOptionalPluginService.sessionSlotForUsername('bob');
      expect(a, isNot(b));
      expect(a, isNot('guest'));
      expect(b, isNot('guest'));
    });
  });
}
