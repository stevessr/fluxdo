import 'dart:async';
import 'dart:convert';
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
    expect(redirected.extra['skipAuthCheck'], isTrue);
    expect(redirected.extra['skipSessionStateSync'], isTrue);
    expect(redirected.extra['skipCfChallenge'], isTrue);
    expect(redirected.extra['noRecovery'], isTrue);
    dio.close(force: true);
  });

  test('same-origin redirects discard validators and old cache snapshots',
      () async {
    final adapter = _ScenarioAdapter(301, '/different-resource.json');
    final dio = _redirectDio(adapter);
    await dio.get<void>('/old.json', options: Options(
      headers: {
        'If-None-Match': '"etag-for-old"',
        'If-Modified-Since': 'Wed, 21 Oct 2015 07:28:00 GMT',
        'If-Match': '"old"',
      },
      extra: {
        '_fluxHttpRevalidationEntry': 'old-response',
        '_fluxHttpRevalidationKey': 'old-cache-key',
        '_schedulerCounted': true,
      },
    ));

    final redirected = adapter.seen.last;
    for (final name in [
      'if-none-match', 'if-modified-since', 'if-match'
    ]) {
      expect(redirected.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains(name)));
    }
    expect(redirected.extra.containsKey('_fluxHttpRevalidationEntry'), isFalse);
    expect(redirected.extra.containsKey('_fluxHttpRevalidationKey'), isFalse);
    expect(redirected.extra['_schedulerCounted'], isTrue);
    dio.close(force: true);
  });

  test('BaseOptions credentials are not reintroduced on a foreign origin',
      () async {
    final adapter = _ScenarioAdapter(
      302,
      'https://external.example/resource?one=1',
    );
    final dio = Dio(BaseOptions(
      baseUrl: 'https://linux.do',
      headers: {
        'Authorization': 'Bearer from-global-defaults',
        'Cookie': '_t=from-global-defaults',
        'Api-Key': 'from-global-defaults',
        'X-Requested-With': 'XMLHttpRequest',
        'X-Custom-Secret': 'private-default',
        'Accept-Encoding': 'br, zstd',
        'Accept': 'application/json',
      },
      validateStatus: (status) => status != null && status < 400,
    ))..httpClientAdapter = adapter;
    dio.interceptors.add(RedirectInterceptor(dio));

    await dio.get<void>('/private?old=1', queryParameters: {'page': 2});
    expect(adapter.seen, hasLength(2));
    final redirected = adapter.seen.last;
    expect(
      redirected.uri.toString(),
      'https://external.example/resource?one=1',
    );
    final sentHeaders = redirected.headers.keys
        .map((name) => name.toLowerCase())
        .toSet();
    for (final secret in [
      'authorization',
      'cookie',
      'api-key',
      'x-requested-with',
      'x-custom-secret',
      'accept-encoding',
    ]) {
      expect(sentHeaders, isNot(contains(secret)));
    }
    expect(
      redirected.headers.entries.any((header) =>
          header.key.toLowerCase() == 'accept' &&
          header.value == 'application/json'),
      isTrue,
    );
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

  test('301/302 POST follows as GET without original entity headers', () async {
    for (final code in [301, 302]) {
      final adapter = _ScenarioAdapter(code, '/after');
      final dio = _redirectDio(adapter);
      await dio.post<void>(
        '/write',
        data: {'message': 'hello'},
        options: Options(headers: {
          'Content-MD5': 'digest-of-old-body',
          'Digest': 'sha-256=old',
          'Expect': '100-continue',
          'Content-Language': 'en',
          'Trailer': 'checksum',
        }),
      );
      final target = adapter.seen.last;
      expect(target.method, 'GET');
      expect(target.data, isNull);
      final headerNames =
          target.headers.keys.map((name) => name.toLowerCase()).toSet();
      for (final name in [
        'content-md5', 'digest', 'expect', 'content-language', 'trailer',
        'content-type', 'content-length', 'transfer-encoding',
      ]) {
        expect(headerNames, isNot(contains(name)));
      }
      dio.close(force: true);
    }
  });

  test('303 HEAD stays HEAD and does not invent a GET payload', () async {
    final adapter = _ScenarioAdapter(303, '/resource');
    final dio = _redirectDio(adapter);
    await dio.head<void>('/original');
    expect(adapter.seen.last.method, 'HEAD');
    expect(adapter.seen.last.data, isNull);
    dio.close(force: true);
  });

  test('307 multipart redirect regenerates its content-type boundary', () async {
    final adapter = _ScenarioAdapter(307, '/upload/finish');
    final dio = _redirectDio(adapter);

    await dio.post<void>(
      '/upload/start',
      data: FormData.fromMap({'text': 'hello'}),
    );

    expect(adapter.seen, hasLength(2));
    final firstType = adapter.seen.first.headers[Headers.contentTypeHeader]
        ?.toString();
    final secondType = adapter.seen.last.headers[Headers.contentTypeHeader]
        ?.toString();
    expect(firstType, contains('boundary='));
    expect(adapter.seen.last.data, isA<FormData>());
    final replay = adapter.seen.last.data as FormData;
    expect(secondType, contains('boundary=${replay.boundary}'));
    dio.close(force: true);
  });

  test('307/308 multipart redirect replays actual uploaded file bytes',
      () async {
    for (final code in [307, 308]) {
      final adapter = _CapturedMultipartAdapter(code);
      final dio = Dio(BaseOptions(
        baseUrl: 'https://linux.do',
        validateStatus: (status) => status != null && status < 400,
      ))..httpClientAdapter = adapter;
      dio.interceptors.add(RedirectInterceptor(dio));

      final payload = FormData.fromMap({
        'note': 'keep-this-field',
        'upload': MultipartFile.fromBytes(
          utf8.encode('file-payload-that-must-survive'),
          filename: 'sample.txt',
        ),
      });
      await dio.post<void>('/upload', data: payload);
      expect(adapter.payloads, hasLength(2));
      for (final body in adapter.payloads) {
        expect(body, contains('keep-this-field'));
        expect(body, contains('file-payload-that-must-survive'));
        expect(body, contains('sample.txt'));
      }
      dio.close(force: true);
    }
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

class _CapturedMultipartAdapter implements HttpClientAdapter {
  _CapturedMultipartAdapter(this.statusCode);

  final int statusCode;
  final List<String> payloads = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final chunks = <int>[];
    if (requestStream != null) {
      await for (final bytes in requestStream) {
        chunks.addAll(bytes);
      }
    }
    payloads.add(utf8.decode(chunks));
    if (payloads.length == 1) {
      return ResponseBody.fromString('', statusCode, headers: {
        'location': ['/upload-destination'],
      });
    }
    return ResponseBody.fromString('{"ok":true}', 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}
