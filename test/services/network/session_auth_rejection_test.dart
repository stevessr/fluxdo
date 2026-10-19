import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/session_auth_rejection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Response<dynamic> forbidden({
    Object? data,
    Map<String, List<String>> headers = const {},
  }) {
    return Response<dynamic>(
      requestOptions: RequestOptions(path: '/session/current.json'),
      statusCode: 403,
      headers: Headers.fromMap(headers),
      data: data,
    );
  }

  group('403 session rejection classification', () {
    test('a bare 403 never proves that the account expired', () {
      expect(SessionAuthRejection.isExplicitLogout403(forbidden()), isFalse);
    });

    test('Cloudflare WAF headers without an auth signal are inconclusive', () {
      final response = forbidden(
        headers: {
          'server': ['cloudflare'],
          'cf-ray': ['1234567890abcdef-LAX'],
          'content-type': ['text/html'],
        },
        data: '<html>Forbidden</html>',
      );
      expect(SessionAuthRejection.isExplicitLogout403(response), isFalse);
    });

    test('ordinary Discourse permission-denied JSON is not logout', () {
      final response = forbidden(
        headers: {
          'content-type': ['application/json'],
        },
        data: {
          'errors': ['You are not permitted to view this resource.'],
        },
      );
      expect(SessionAuthRejection.isExplicitLogout403(response), isFalse);
    });

    test('an explicit Discourse logged-out header can confirm logout', () {
      final response = forbidden(
        headers: {
          'discourse-logged-out': ['1'],
          'content-type': ['application/json'],
        },
      );
      expect(SessionAuthRejection.isExplicitLogout403(response), isTrue);
    });

    test('Discourse not_logged_in error body can confirm logout', () {
      final response = forbidden(
        data: {'error_type': 'not_logged_in'},
        headers: {
          'content-type': ['application/json'],
        },
      );
      expect(SessionAuthRejection.isExplicitLogout403(response), isTrue);
    });

    test('Cloudflare cf-mitigated header takes precedence over auth signal', () {
      final response = forbidden(
        headers: {
          'cf-mitigated': ['challenge'],
          'discourse-logged-out': ['1'],
          'content-type': ['text/plain'],
        },
        data: {'error_type': 'not_logged_in'},
      );
      expect(SessionAuthRejection.isExplicitLogout403(response), isFalse);
    });

    test('Cloudflare challenge HTML is not a logout signal', () {
      final response = forbidden(
        headers: {
          'content-type': ['text/html'],
        },
        data: '<html><script>window.cf_chl_opt={};</script></html>',
      );
      expect(SessionAuthRejection.isExplicitLogout403(response), isFalse);
    });
  });
}
