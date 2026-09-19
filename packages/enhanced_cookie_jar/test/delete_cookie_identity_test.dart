import 'dart:io';

import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late EnhancedPersistCookieJar jar;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'enhanced_cookie_identity_delete_test_',
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

  test('exact identity delete preserves same-name cookies on other paths',
      () async {
    final uri = Uri.parse('https://example.com/');
    await jar.saveCanonicalCookies(
      uri,
      [
        CanonicalCookie(
          name: 'sid',
          value: 'root',
          domain: 'example.com',
          path: '/',
          hostOnly: true,
          originUrl: uri.toString(),
        ),
        CanonicalCookie(
          name: 'sid',
          value: 'account',
          domain: '.example.com',
          path: '/account',
          hostOnly: false,
          originUrl: uri.toString(),
        ),
      ],
      trusted: true,
    );

    final removed = await jar.deleteCookieIdentity(
      name: 'sid',
      domain: '.EXAMPLE.com',
      path: '/account',
    );

    expect(removed, 1);
    final remaining = await jar.readAllCookies();
    expect(
      remaining.where((cookie) => cookie.name == 'sid').map((c) => c.path),
      equals(['/']),
    );
  });

  test('exact identity delete removes partition variants together', () async {
    final uri = Uri.parse('https://example.com/');
    await jar.saveCanonicalCookies(
      uri,
      [
        CanonicalCookie(
          name: 'chips',
          value: 'plain',
          domain: 'example.com',
          path: '/app',
          hostOnly: false,
          originUrl: uri.toString(),
        ),
        CanonicalCookie(
          name: 'chips',
          value: 'partitioned',
          domain: 'example.com',
          path: '/app',
          hostOnly: false,
          partitioned: true,
          partitionKey: 'https://top.example',
          originUrl: uri.toString(),
        ),
      ],
      trusted: true,
    );

    final removed = await jar.deleteCookieIdentity(
      name: 'chips',
      domain: 'example.com',
      path: '/app',
    );

    expect(removed, 2);
    expect(
      (await jar.readAllCookies()).where((cookie) => cookie.name == 'chips'),
      isEmpty,
    );
  });
}
