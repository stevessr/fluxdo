import 'package:flutter_test/flutter_test.dart';

import 'package:fluxdo/services/network/doh/custom_hosts_service.dart';

void main() {
  test('parses system-style hosts records and aliases', () {
    final result = CustomHostsService.parse('''
# comment
127.0.0.1 example.test example.test
::1 example.test localhost # inline comment
invalid not-an-ip

''');

    expect(result.hostCount, 2);
    expect(result.addressCount, 3);
    expect(result.hosts['example.test'], ['127.0.0.1', '::1']);
    expect(result.hosts['localhost'], ['::1']);
  });

  test('normalizes persisted mappings and drops invalid addresses', () {
    final result = CustomHostsService.normalizeOverrides({
      'Example.COM.': ['192.0.2.1', '192.0.2.1', 'not-an-ip'],
      'bad/host': ['192.0.2.2'],
      'empty.example': <String>[],
    });

    expect(result, {
      'example.com': ['192.0.2.1'],
    });
  });
}
