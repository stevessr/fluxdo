import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/config/discourse_instance_runtime.dart';
import 'package:fluxdo/services/network/interceptors/request_header_interceptor.dart';

void main() {
  tearDown(DiscourseInstanceRuntime.reset);

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

  group('RequestHeaderInterceptor credential boundary', () {
    test('only current instance path may receive discourse credentials', () {
      DiscourseInstanceRuntime.activate(
        instanceId: 'ignored',
        baseUrl: 'https://forum.example.com/forum',
      );

      expect(
        RequestHeaderInterceptor.targetsActiveDiscourse(
          Uri.parse('https://forum.example.com/forum/posts.json'),
        ),
        isTrue,
      );
      expect(
        RequestHeaderInterceptor.targetsActiveDiscourse(
          Uri.parse('https://forum.example.com/other/posts.json'),
        ),
        isFalse,
      );
      expect(
        RequestHeaderInterceptor.targetsActiveDiscourse(
          Uri.parse('https://messagebus.example.com/poll'),
        ),
        isFalse,
      );
      expect(
        RequestHeaderInterceptor.targetsActiveDiscourse(
          Uri.parse('http://forum.example.com/forum/posts.json'),
        ),
        isFalse,
      );
    });

    test('default linux.do credentials stay on the main host', () {
      expect(
        RequestHeaderInterceptor.targetsActiveDiscourse(
          Uri.parse('https://linux.do/session/csrf'),
        ),
        isTrue,
      );
      expect(
        RequestHeaderInterceptor.targetsActiveDiscourse(
          Uri.parse('https://credit.linux.do/session/csrf'),
        ),
        isFalse,
      );
    });
  });
}
