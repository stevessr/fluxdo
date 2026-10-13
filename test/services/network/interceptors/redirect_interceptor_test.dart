import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/interceptors/redirect_interceptor.dart';
import 'package:fluxdo/services/network/interceptors/https_security_interceptor.dart';

void main() {
  test('内部重定向绕过调度器并保留原请求计数标记', () async {
    final adapter = _RedirectOnceAdapter();
    final requestExtras = <Map<String, dynamic>>[];
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://linux.do',
        validateStatus: (status) => status != null && status < 400,
      ),
    )..httpClientAdapter = adapter;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestExtras.add(Map<String, dynamic>.from(options.extra));
          handler.next(options);
        },
      ),
    );
    dio.interceptors.add(RedirectInterceptor(dio));

    final response = await dio.get(
      '/',
      options: Options(extra: {'_schedulerCounted': true}),
    );

    expect(response.statusCode, 200);
    expect(adapter.fetchCount, 2);
    expect(requestExtras, hasLength(2));
    expect(requestExtras.last['skipScheduler'], isTrue);
    expect(requestExtras.last['_redirectCount'], 1);
    expect(requestExtras.last['_schedulerCounted'], isTrue);
  });
  test('cross-origin redirects never forward forum authentication headers', () async {
    final adapter = _ScenarioAdapter(302, 'https://other.example/landing');
    final dio = _redirectDio(adapter);
    await dio.get<void>('/from', options: Options(headers: {
      'Authorization': 'Bearer secret',
      'Cookie': '_t=secret',
      'X-CSRF-Token': 'private-token',
      'Api-Key': 'private-key',
      'X-Requested-With': 'XMLHttpRequest',
      'Origin': 'https://linux.do',
      'Referer': 'https://linux.do/private',
      'Sec-Fetch-Site': 'same-origin',
      'X-Unrecognized-Secret': 'private',
    }));
    expect(adapter.seen, hasLength(2));
    final redirected = adapter.seen.last;
    expect(redirected.uri.toString(), 'https://other.example/landing');
    for (final sensitive in [
      'authorization', 'cookie', 'x-csrf-token', 'api-key',
      'x-requested-with', 'origin', 'referer', 'sec-fetch-site',
      'x-unrecognized-secret',
    ]) {
      expect(redirected.headers.keys.map((e) => e.toLowerCase()),
          isNot(contains(sensitive)));
    }
    expect(redirected.extra['skipCsrf'], isTrue);
    dio.close(force: true);
  });

  test('cross-origin redirects discard private cache and cookie metadata',
      () async {
    final adapter = _ScenarioAdapter(302, 'https://other.example/final');
    final dio = _redirectDio(adapter);

    await dio.get<void>('/cached', options: Options(extra: {
      '_fluxHttpRevalidationEntry': 'cache-for-original-host',
      '_fluxHttpRevalidationKey': 'original',
      '_sessionGeneration': 41,
      'allowRedirectSetCookie': true,
      'skipScheduler': false,
      'isSilent': true,
    }));

    final forwarded = adapter.seen.last.extra;
    expect(forwarded.containsKey('_fluxHttpRevalidationEntry'), isFalse);
    expect(forwarded.containsKey('_fluxHttpRevalidationKey'), isFalse);
    expect(forwarded.containsKey('_sessionGeneration'), isFalse);
    expect(forwarded.containsKey('allowRedirectSetCookie'), isFalse);
    expect(forwarded['isSilent'], isTrue);
    expect(forwarded['skipScheduler'], isTrue);
    expect(forwarded['skipCsrf'], isTrue);
    dio.close(force: true);
  });

  test('303 converts POST to bodyless GET and 307 preserves same-origin body',
      () async {
    final adapter303 = _ScenarioAdapter(303, '/finish');
    final dio303 = _redirectDio(adapter303);
    await dio303.post<void>('/from', data: {'hello': 'world'});
    expect(adapter303.seen.last.method, 'GET');
    expect(adapter303.seen.last.data, isNull);
    dio303.close(force: true);

    final adapter307 = _ScenarioAdapter(307, '/finish');
    final dio307 = _redirectDio(adapter307);
    await dio307.post<void>('/from', data: {'hello': 'world'});
    expect(adapter307.seen.last.method, 'POST');
    expect(adapter307.seen.last.data, {'hello': 'world'});
    dio307.close(force: true);
  });

  test('HTTPS downgrade and cross-origin body forwarding are rejected', () async {
    final insecure = _ScenarioAdapter(302, 'http://linux.do/plain');
    final dio = _redirectDio(insecure);
    await expectLater(dio.get<void>('/start'), throwsA(isA<DioException>()));
    expect(insecure.seen, hasLength(1));
    dio.close(force: true);

    final exfil = _ScenarioAdapter(307, 'https://other.example/upload');
    final dioExfil = _redirectDio(exfil);
    await expectLater(dioExfil.post<void>('/submit', data: {'token': 'private'}),
        throwsA(isA<DioException>()));
    expect(exfil.seen, hasLength(1));
    dioExfil.close(force: true);
  });

  test('streaming bodies are not silently dropped on 307', () async {
    final adapter = _ScenarioAdapter(307, '/again');
    final dio = _redirectDio(adapter);
    await expectLater(
      dio.post<void>('/submit', data: Stream<Uint8List>.value(Uint8List.fromList([1, 2, 3]))),
      throwsA(isA<DioException>()),
    );
    expect(adapter.seen, hasLength(1));
    dio.close(force: true);
  });

  test('learned HSTS upgrades a redirected HTTP location', () async {
    final policy = HttpsSecurityPolicy();
    policy.observe(
      Uri.parse('https://linux.do'),
      Headers.fromMap({
        'strict-transport-security': ['max-age=60'],
      }),
    );
    final adapter = _ScenarioAdapter(301, 'http://linux.do/finish');
    final dio = _redirectDio(adapter, httpsPolicy: policy);
    await dio.get<void>('/start');
    expect(adapter.seen.last.uri.scheme, 'https');
    dio.close(force: true);
  });

}

class _RedirectOnceAdapter implements HttpClientAdapter {
  int fetchCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount++;
    if (fetchCount == 1) {
      return ResponseBody.fromString(
        '',
        301,
        headers: {
          'location': ['https://linux.do/final'],
        },
      );
    }
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _redirectDio(_ScenarioAdapter adapter, {HttpsSecurityPolicy? httpsPolicy}) {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://linux.do',
    validateStatus: (status) => status != null && status < 400,
  ));
  dio.httpClientAdapter = adapter;
  dio.interceptors.add(RedirectInterceptor(dio, httpsPolicy: httpsPolicy));
  return dio;
}

class _ScenarioAdapter implements HttpClientAdapter {
  _ScenarioAdapter(this.statusCode, this.location);

  final int statusCode;
  final String location;
  final List<RequestOptions> seen = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    if (seen.length == 1) {
      return ResponseBody.fromString('', statusCode, headers: {
        'location': [location],
      });
    }
    return ResponseBody.fromString('{"ok":true}', 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}
