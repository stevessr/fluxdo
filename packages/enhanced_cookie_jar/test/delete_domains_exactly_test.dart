import 'dart:io';

import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late EnhancedPersistCookieJar jar;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'enhanced_cookie_exact_delete_test_',
    );
    jar = EnhancedPersistCookieJar(
      store: FileCookieStore(tempDir.path),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('删除子域不会删除父域 Cookie', () async {
    await jar.saveFromSetCookieHeaders(
      Uri.parse('https://linux.do'),
      ['parent=1; Domain=.linux.do; Path=/'],
    );
    await jar.saveFromSetCookieHeaders(
      Uri.parse('https://credit.linux.do'),
      ['child=1; Path=/'],
    );

    final removed = await jar.deleteDomainsExactly({'credit.linux.do'});

    expect(removed, 1);
    expect(
      (await jar.loadForRequest(Uri.parse('https://linux.do')))
          .map((cookie) => cookie.name),
      contains('parent'),
    );
    expect(
      (await jar.readAllCookies()).map((cookie) => cookie.name),
      isNot(contains('child')),
    );
  });

  test('批量删除只影响被选中的域名', () async {
    await jar.saveFromSetCookieHeaders(
      Uri.parse('https://linux.do'),
      ['root=1; Path=/'],
    );
    await jar.saveFromSetCookieHeaders(
      Uri.parse('https://credit.linux.do'),
      ['credit=1; Path=/'],
    );
    await jar.saveFromSetCookieHeaders(
      Uri.parse('https://cdk.linux.do'),
      ['cdk=1; Path=/'],
    );

    final removed = await jar.deleteDomainsExactly({
      '.linux.do',
      'credit.linux.do',
    });

    expect(removed, 2);
    final remaining = await jar.readAllCookies();
    expect(remaining.map((cookie) => cookie.name), contains('cdk'));
    expect(remaining.map((cookie) => cookie.name), isNot(contains('root')));
    expect(remaining.map((cookie) => cookie.name), isNot(contains('credit')));
  });
}
