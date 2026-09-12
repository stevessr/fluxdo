import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/interceptors/request_header_interceptor.dart';

void main() {
  group('RequestHeaderInterceptor XHR base URL contract', () {
    test('origin excludes discourse relative-url-root', () {
      expect(
        RequestHeaderInterceptor.xhrOriginForBaseUrl(
          'https://forum.example.com/forum',
        ),
        'https://forum.example.com',
      );
      expect(
        RequestHeaderInterceptor.xhrOriginForBaseUrl(
          'http://localhost:3000/forum',
        ),
        'http://localhost:3000',
      );
    });

    test('referer keeps discourse relative-url-root', () {
      expect(
        RequestHeaderInterceptor.xhrRefererForBaseUrl(
          'https://forum.example.com/forum',
        ),
        'https://forum.example.com/forum/',
      );
      expect(
        RequestHeaderInterceptor.xhrRefererForBaseUrl(
          'https://forum.example.com',
        ),
        'https://forum.example.com/',
      );
    });
  });
}
