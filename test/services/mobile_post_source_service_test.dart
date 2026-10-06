import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/mobile_post_source_service.dart';

void main() {
  group('MobilePostSourceService', () {
    const info = MobilePostSourceInfo(
      platform: 'android',
      brand: 'Xiaomi',
      model: '24129PN74C',
    );

    test('builds Linux.do ios_device_name protocol fields', () {
      expect(
        MobilePostSourceService.buildFields(info: info),
        {
          'via_ios_app': true,
          'ios_device_name': '24129PN74C',
        },
      );
    });

    test('custom model overrides detected model', () {
      expect(
        MobilePostSourceService.buildFields(
          info: info,
          customModel: 'Xiaomi 15 Ultra',
        )['ios_device_name'],
        'Xiaomi 15 Ultra',
      );
    });

    test('blank custom model falls back to detected model', () {
      expect(
        MobilePostSourceService.buildFields(
          info: info,
          customModel: '   ',
        )['ios_device_name'],
        '24129PN74C',
      );
    });

    test('desktop models also use ios_device_name for server compatibility', () {
      const desktop = MobilePostSourceInfo(
        platform: 'windows',
        brand: 'LENOVO',
        model: '83DF',
      );
      expect(
        MobilePostSourceService.buildFields(info: desktop),
        {
          'via_ios_app': true,
          'ios_device_name': '83DF',
        },
      );
    });
  });
}
