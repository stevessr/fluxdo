import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/flux_request_spec.dart';
import 'package:fluxdo/services/network/interceptors/redirect_interceptor.dart';

void main() {
  group('RedirectInterceptor origin boundary', () {
    test('treats default and explicit ports as the same origin', () {
      expect(
        RedirectInterceptor.isSameOrigin(
          Uri.parse('https://forum.example.com/forum/t/1'),
          Uri.parse('https://FORUM.example.com:443/forum/login'),
        ),
        isTrue,
      );
      expect(
        RedirectInterceptor.isSameOrigin(
          Uri.parse('http://forum.example.com/forum'),
          Uri.parse('http://forum.example.com:80/other'),
        ),
        isTrue,
      );
    });

    test('scheme host or port changes are cross-origin', () {
      final source = Uri.parse('https://forum.example.com/forum');
      expect(
        RedirectInterceptor.isSameOrigin(
          source,
          Uri.parse('http://forum.example.com/forum'),
        ),
        isFalse,
      );
      expect(
        RedirectInterceptor.isSameOrigin(
          source,
          Uri.parse('https://cdn.example.com/forum'),
        ),
        isFalse,
      );
      expect(
        RedirectInterceptor.isSameOrigin(
          source,
          Uri.parse('https://forum.example.com:8443/forum'),
        ),
        isFalse,
      );
    });
  });

  group('RedirectInterceptor credential isolation', () {
    final headers = <String, dynamic>{
      'Cookie': '_t=session',
      'Authorization': 'Bearer secret',
      'Proxy-Authorization': 'Basic secret',
      'X-CSRF-Token': 'csrf-secret',
      'User-Api-Key': 'api-secret',
      'User-Api-Client-Id': 'client-secret',
      'X-Shared-Session-Key': 'messagebus-secret',
      'X-Requested-With': 'XMLHttpRequest',
      'Origin': 'https://forum.example.com',
      'Referer': 'https://forum.example.com/forum/',
      'Discourse-Present': 'true',
      'Sec-Fetch-Site': 'same-origin',
      'Accept': 'application/json',
    };

    test(
      'same-origin redirect only refreshes Cookie through CookieManager',
      () {
        final sanitized = RedirectInterceptor.sanitizedHeadersForRedirect(
          headers,
          sameOrigin: true,
        );

        expect(sanitized.containsKey('Cookie'), isFalse);
        expect(sanitized['X-CSRF-Token'], 'csrf-secret');
        expect(sanitized['User-Api-Key'], 'api-secret');
        expect(sanitized['X-Shared-Session-Key'], 'messagebus-secret');
        expect(sanitized['X-Requested-With'], 'XMLHttpRequest');
        expect(sanitized['Accept'], 'application/json');
      },
    );

    test(
      'cross-origin redirect strips site credentials and fetch metadata',
      () {
        final sanitized = RedirectInterceptor.sanitizedHeadersForRedirect(
          headers,
          sameOrigin: false,
        );

        for (final name in [
          'Cookie',
          'Authorization',
          'Proxy-Authorization',
          'X-CSRF-Token',
          'User-Api-Key',
          'User-Api-Client-Id',
          'X-Shared-Session-Key',
          'X-Requested-With',
          'Origin',
          'Referer',
          'Discourse-Present',
          'Sec-Fetch-Site',
        ]) {
          expect(sanitized.containsKey(name), isFalse, reason: name);
        }
        expect(sanitized['Accept'], 'application/json');
      },
    );

    test('cross-origin redirect disables discourse auth side effects', () {
      final extra = RedirectInterceptor.redirectExtra(
        const {'requestTag': 'original'},
        sameOrigin: false,
        redirectCount: 0,
      );

      expect(extra[FluxRequestKeys.skipCsrf], isTrue);
      expect(extra[FluxRequestKeys.skipAuthCheck], isTrue);
      expect(extra[FluxRequestKeys.skipSessionStateSync], isTrue);
      expect(extra[FluxRequestKeys.skipCfChallenge], isTrue);
      expect(extra[FluxRequestKeys.noRecovery], isTrue);
      expect(extra[FluxRequestKeys.skipScheduler], isTrue);
      expect(extra['requestTag'], 'original');
    });
  });
}
