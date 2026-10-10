import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/config/discourse_instance_runtime.dart';
import 'package:fluxdo/services/network/cookie/app_cookie_manager.dart';
import 'package:fluxdo/services/network/flux_request_spec.dart';
import 'package:fluxdo/services/network/interceptors/redirect_interceptor.dart';

void main() {
  tearDown(DiscourseInstanceRuntime.reset);
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

  group('RedirectInterceptor instance boundary', () {
    test('same-origin sibling paths are outside a sub-path forum', () {
      DiscourseInstanceRuntime.activate(
        instanceId: 'ignored',
        baseUrl: 'https://forum.example.com/forum',
      );
      final source = Uri.parse('https://forum.example.com/forum/posts.json');

      expect(
        RedirectInterceptor.isSameDiscourseScope(
          source,
          Uri.parse('https://forum.example.com/forum/t/1'),
        ),
        isTrue,
      );
      expect(
        RedirectInterceptor.isSameOrigin(
          source,
          Uri.parse('https://forum.example.com/other/login'),
        ),
        isTrue,
      );
      expect(
        RedirectInterceptor.isSameDiscourseScope(
          source,
          Uri.parse('https://forum.example.com/other/login'),
        ),
        isFalse,
      );
      expect(
        RedirectInterceptor.isSameDiscourseScope(
          source,
          Uri.parse('https://forum.example.com/forum-other/login'),
        ),
        isFalse,
      );
    });

    test('a redirect from outside the forum cannot regain its credentials', () {
      DiscourseInstanceRuntime.activate(
        instanceId: 'ignored',
        baseUrl: 'https://forum.example.com/forum',
      );
      expect(
        RedirectInterceptor.isSameDiscourseScope(
          Uri.parse('https://forum.example.com/other/login'),
          Uri.parse('https://forum.example.com/forum/session'),
        ),
        isFalse,
      );
    });
  });

  group('RedirectInterceptor subpath cookie isolation', () {
    test(
      'redirect through sibling path cannot reload the forum session',
      () async {
        DiscourseInstanceRuntime.activate(
          instanceId: 'ignored',
          baseUrl: 'https://forum.example.com/forum',
        );
        final jar = CookieJar();
        await jar.saveFromResponse(
          Uri.parse('https://forum.example.com/forum/session'),
          [Cookie('_t', 'forum-secret')..path = '/'],
        );
        final adapter = _SubpathRedirectAdapter();
        final dio = Dio(
          BaseOptions(
            baseUrl: 'https://forum.example.com',
            followRedirects: false,
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
          ),
        )..httpClientAdapter = adapter;
        dio.interceptors.add(AppCookieManager(jar));
        dio.interceptors.add(RedirectInterceptor(dio));

        final result = await dio.get<dynamic>('/forum/start');
        expect(result.statusCode, 200);
        expect(adapter.requestedPaths, [
          '/forum/start',
          '/other/redirect',
          '/forum/finished',
        ]);
        expect(adapter.requestedCookies[0], contains('_t=forum-secret'));
        expect(adapter.requestedCookies[1], isEmpty);
        expect(adapter.requestedCookies[2], isEmpty);

        await dio.get<dynamic>('/forum/fresh');
        expect(adapter.requestedCookies.last, contains('_t=forum-secret'));
      },
    );
  });

  group('RedirectInterceptor method handling', () {
    test('303 converts writes to GET but keeps HEAD', () {
      expect(RedirectInterceptor.redirectedMethod(303, 'POST'), 'GET');
      expect(RedirectInterceptor.redirectedMethod(303, 'PUT'), 'GET');
      expect(RedirectInterceptor.redirectedMethod(303, 'HEAD'), 'HEAD');
    });

    test('301/302 convert POST, but 307/308 preserve methods and body', () {
      expect(RedirectInterceptor.redirectedMethod(301, 'POST'), 'GET');
      expect(RedirectInterceptor.redirectedMethod(302, 'POST'), 'GET');
      expect(RedirectInterceptor.redirectedMethod(302, 'PUT'), 'PUT');
      expect(RedirectInterceptor.redirectedMethod(307, 'POST'), 'POST');
      expect(RedirectInterceptor.redirectedMethod(308, 'PUT'), 'PUT');
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

class _SubpathRedirectAdapter implements HttpClientAdapter {
  final List<String> requestedPaths = [];
  final List<String> requestedCookies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.uri.path);
    requestedCookies.add(
      options.headers.entries
          .where((entry) => entry.key.toLowerCase() == 'cookie')
          .map((entry) => entry.value?.toString() ?? '')
          .join('; '),
    );
    switch (options.uri.path) {
      case '/forum/start':
        return ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['/other/redirect'],
          },
        );
      case '/other/redirect':
        return ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['/forum/finished'],
          },
        );
      default:
        return ResponseBody.fromString(
          '{}',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
    }
  }

  @override
  void close({bool force = false}) {}
}
