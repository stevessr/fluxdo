import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/cookie/site_cookie_manager_service.dart';

void main() {
  group('SiteCookieManagerService cookie identity', () {
    test('normalizes domain casing, leading dot and path slash', () {
      final a = SiteCookieManagerService.cookieIdentityKey(
        name: 'sid',
        domain: '.Example.COM',
        path: 'account',
      );
      final b = SiteCookieManagerService.cookieIdentityKey(
        name: 'sid',
        domain: 'example.com',
        path: '/account',
      );

      expect(a, b);
    });

    test('keeps same-name cookies on different paths distinct', () {
      final root = SiteCookieManagerService.cookieIdentityKey(
        name: 'sid',
        domain: 'example.com',
        path: '/',
      );
      final nested = SiteCookieManagerService.cookieIdentityKey(
        name: 'sid',
        domain: 'example.com',
        path: '/account',
      );

      expect(root, isNot(nested));
    });
  });
}
