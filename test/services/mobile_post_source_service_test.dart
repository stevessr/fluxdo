import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/mobile_post_source_service.dart';

void main() {
  group('MobilePostSourceService', () {
    test('does not claim public posts can send verified iOS source fields', () {
      expect(MobilePostSourceService.canSendVerifiedPostSource, isFalse);
    });

    test('normalizes a custom device model for future verified transport', () {
      expect(
        MobilePostSourceService.normalizeCustomModel(
          '  Xiaomi 15 Ultra\nSpecial Edition  ',
        ),
        'Xiaomi 15 Ultra Special Edition',
      );
    });

    test('blank custom device model becomes null', () {
      expect(MobilePostSourceService.normalizeCustomModel('   \n '), isNull);
    });
  });
}
