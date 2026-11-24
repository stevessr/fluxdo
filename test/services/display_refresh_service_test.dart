import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/display_refresh_service.dart';

void main() {
  test('legacy zero and invalid values migrate to a distinct auto sentinel', () {
    expect(DisplayRefreshService.normalize(null), -1);
    expect(DisplayRefreshService.normalize(0), -1);
    expect(DisplayRefreshService.normalize(-99), -1);
    expect(DisplayRefreshService.normalize(-2), -2);
    expect(DisplayRefreshService.normalize(120), 120);
  });
}
