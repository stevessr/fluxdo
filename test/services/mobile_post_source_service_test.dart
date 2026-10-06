import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/mobile_post_source_service.dart';

void main() {
  group('MobilePostSourceService', () {
    const info = MobilePostSourceInfo(
      platform: 'android',
      brand: 'Xiaomi',
      model: '24129PN74C',
    );

    test('builds the mobile_source protocol fields', () {
      expect(
        MobilePostSourceService.buildFields(info: info),
        {
          'mobile_source_platform': 'android',
          'mobile_source_brand': 'Xiaomi',
          'mobile_source_model': '24129PN74C',
        },
      );
    });

    test('custom model overrides detected model', () {
      expect(
        MobilePostSourceService.buildFields(
          info: info,
          customModel: 'Xiaomi 15 Ultra',
        )['mobile_source_model'],
        'Xiaomi 15 Ultra',
      );
    });

    test('blank custom model falls back to detected model', () {
      expect(
        MobilePostSourceService.buildFields(
          info: info,
          customModel: '   ',
        )['mobile_source_model'],
        '24129PN74C',
      );
    });

    test('desktop models use the same wire protocol', () {
      const desktop = MobilePostSourceInfo(
        platform: 'windows',
        brand: 'LENOVO',
        model: '83DF',
      );
      expect(
        MobilePostSourceService.buildFields(info: desktop),
        {
          'mobile_source_platform': 'windows',
          'mobile_source_brand': 'LENOVO',
          'mobile_source_model': '83DF',
        },
      );
    });
  });
}
