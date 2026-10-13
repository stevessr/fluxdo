import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluxdo/services/network/interceptors/https_security_interceptor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final st = Headers.fromMap({
    'strict-transport-security': ['max-age=60; includeSubDomains'],
  });

  test('HSTS is learned from HTTPS only and upgrades matching subdomains', () {
    final policy = HttpsSecurityPolicy();
    policy.observe(Uri.parse('http://example.org'), st);
    expect(policy.upgrade(Uri.parse('http://example.org/a')).scheme, 'http');

    policy.observe(Uri.parse('https://example.org'), st);
    expect(policy.upgrade(Uri.parse('http://example.org/a?x=1')).toString(),
        'https://example.org/a?x=1');
    expect(policy.upgrade(Uri.parse('http://a.example.org/')).scheme, 'https');
    expect(policy.upgrade(Uri.parse('http://notexample.org/')).scheme, 'http');
    expect(policy.upgrade(Uri.parse('http://example.org:8080/p')).toString(),
        'https://example.org:8080/p');
  });

  test('HSTS expiry, includeSubDomains, and max-age=0 are honored', () {
    var now = DateTime.utc(2026, 10, 13);
    final policy = HttpsSecurityPolicy(now: () => now);
    policy.observe(Uri.parse('https://example.org'),
        Headers.fromMap({'strict-transport-security': ['max-age="5"']}));
    expect(policy.upgrade(Uri.parse('http://a.example.org')).scheme, 'http');
    expect(policy.upgrade(Uri.parse('http://example.org')).scheme, 'https');
    now = now.add(const Duration(seconds: 6));
    expect(policy.upgrade(Uri.parse('http://example.org')).scheme, 'http');

    policy.observe(Uri.parse('https://example.org'), st);
    policy.observe(Uri.parse('https://example.org'),
        Headers.fromMap({'strict-transport-security': ['max-age=0']}));
    expect(policy.upgrade(Uri.parse('http://a.example.org')).scheme, 'http');
  });

  test('invalid HSTS and IP-localhost policies are ignored', () {
    final policy = HttpsSecurityPolicy();
    const domains = ['localhost', '127.0.0.1', '[::1]'];
    for (final domain in domains) {
      policy.observe(Uri.parse('https://$domain/'), st);
      expect(policy.upgrade(Uri.parse('http://$domain/')).scheme, 'http');
    }
    policy.observe(Uri.parse('https://example.org'),
        Headers.fromMap({'strict-transport-security': ['max-age=-1']}));
    expect(policy.upgrade(Uri.parse('http://example.org')).scheme, 'http');
  });

  test('Cloudflare 103 Early Hints cannot install an HSTS policy', () async {
    final policy = HttpsSecurityPolicy();
    final dio = Dio(BaseOptions(
      baseUrl: 'https://example.org',
      validateStatus: (status) => true,
    ))..httpClientAdapter = _HstsAdapter(statusCode: 103);
    dio.interceptors.add(HttpsSecurityInterceptor(policy: policy));

    await dio.get<void>('/hint');
    expect(policy.upgrade(Uri.parse('http://example.org')).scheme, 'http');
    dio.close(force: true);
  });

  test('an untrusted TLS certificate error cannot install HSTS', () async {
    final policy = HttpsSecurityPolicy();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.org'))
      ..httpClientAdapter = _HstsAdapter();
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.badCertificate,
          response: Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            headers: st,
          ),
        ));
      },
    ));
    dio.interceptors.add(HttpsSecurityInterceptor(policy: policy));

    await expectLater(dio.get<void>('/untrusted'),
        throwsA(isA<DioException>()));
    expect(policy.upgrade(Uri.parse('http://example.org')).scheme, 'http');
    dio.close(force: true);
  });

  test('interceptor learns secure response and upgrades following HTTP URL',
      () async {
    final policy = HttpsSecurityPolicy();
    final adapter = _HstsAdapter();
    final dio = Dio(BaseOptions(
      baseUrl: 'https://example.org',
      validateStatus: (status) => status != null && status < 400,
    ));
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(HttpsSecurityInterceptor(policy: policy));

    await dio.get<void>('/initial');
    await dio.get<void>('http://example.org/next',
        queryParameters: {'page': '1'});
    expect(adapter.urls, [
      'https://example.org/initial',
      'https://example.org/next?page=1',
    ]);
    dio.close(force: true);
  });

  test('HSTS upgrade keeps queries with a relative path and HTTP baseUrl',
      () async {
    final policy = HttpsSecurityPolicy();
    policy.observe(
      Uri.parse('https://example.org'),
      Headers.fromMap({
        'strict-transport-security': ['max-age=60'],
      }),
    );
    final adapter = _HstsAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://example.org'))
      ..httpClientAdapter = adapter;
    dio.interceptors.add(HttpsSecurityInterceptor(policy: policy));

    await dio.get<void>(
      '/latest.json?sort=created',
      queryParameters: {'page': 2},
    );
    expect(adapter.urls, ['https://example.org/latest.json?sort=created&page=2']);
    dio.close(force: true);
  });

  test('HSTS survives restart and max-age=0 removes the persisted policy',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final first = HttpsSecurityPolicy(persist: true);
    await first.ensureLoaded();
    first.observe(Uri.parse('https://example.org'),
        Headers.fromMap({
          'strict-transport-security': ['max-age=3600; includeSubDomains'],
        }));
    await first.flushPending();

    final restored = HttpsSecurityPolicy(persist: true);
    await restored.ensureLoaded();
    expect(restored.upgrade(Uri.parse('http://example.org/p')).scheme,
        'https');
    expect(restored.upgrade(Uri.parse('http://a.example.org')).scheme,
        'https');
    restored.observe(Uri.parse('https://example.org'),
        Headers.fromMap({
          'strict-transport-security': ['max-age=0'],
        }));
    await restored.flushPending();

    final afterRemoval = HttpsSecurityPolicy(persist: true);
    await afterRemoval.ensureLoaded();
    expect(afterRemoval.upgrade(Uri.parse('http://example.org')).scheme,
        'http');
    expect(afterRemoval.upgrade(Uri.parse('http://a.example.org')).scheme,
        'http');
  });

  test('first request applies persisted HSTS before touching the adapter',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final previousProcess = HttpsSecurityPolicy(persist: true);
    await previousProcess.ensureLoaded();
    previousProcess.observe(Uri.parse('https://example.org'), st);
    await previousProcess.flushPending();

    // Simulate an app restart and an initial plaintext URL.
    final policy = HttpsSecurityPolicy(persist: true);
    final adapter = _HstsAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://example.org'))
      ..httpClientAdapter = adapter;
    dio.interceptors.add(HttpsSecurityInterceptor(policy: policy));
    await dio.get<void>('/first');
    expect(adapter.urls, ['https://example.org/first']);
    dio.close(force: true);
  });

  test('corrupt saved HSTS JSON does not disable new policy persistence',
      () async {
    SharedPreferences.setMockInitialValues({
      'network_hsts_policies_v1': 'not-json',
    });
    final policy = HttpsSecurityPolicy(persist: true);
    await policy.ensureLoaded();
    policy.observe(Uri.parse('https://example.org'), st);
    await policy.flushPending();

    final restored = HttpsSecurityPolicy(persist: true);
    await restored.ensureLoaded();
    expect(restored.upgrade(Uri.parse('http://sub.example.org')).scheme,
        'https');
  });

  test('live max-age=0 before cache load cannot resurrect old HSTS',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final original = HttpsSecurityPolicy(persist: true);
    await original.ensureLoaded();
    original.observe(Uri.parse('https://example.org'), st);
    await original.flushPending();

    // Another verified response may arrive before the lazy disk restoration
    // finishes. Removal must win over the old persisted snapshot.
    final policy = HttpsSecurityPolicy(persist: true);
    policy.observe(
      Uri.parse('https://example.org'),
      Headers.fromMap({
        'strict-transport-security': ['max-age=0'],
      }),
    );
    await policy.ensureLoaded();
    await policy.flushPending();
    expect(policy.upgrade(Uri.parse('http://example.org')).scheme, 'http');

    final next = HttpsSecurityPolicy(persist: true);
    await next.ensureLoaded();
    expect(next.upgrade(Uri.parse('http://example.org')).scheme, 'http');
  });

  test('invalid, expired or impossible persisted HSTS entries are ignored',
      () async {
    SharedPreferences.setMockInitialValues({
      'network_hsts_policies_v1': '[{"host":"example.org","until":1,'
          '"includeSubDomains":true},'
          '{"host":"127.0.0.1","until":9999999999999,'
          '"includeSubDomains":true}]',
    });
    final policy = HttpsSecurityPolicy(persist: true);
    await policy.ensureLoaded();
    expect(policy.upgrade(Uri.parse('http://example.org')).scheme,
        'http');
    expect(policy.upgrade(Uri.parse('http://127.0.0.1')).scheme,
        'http');
  });

  test('duplicate HSTS age directives do not override an existing policy',
      () {
    final policy = HttpsSecurityPolicy();
    policy.observe(Uri.parse('https://example.org'), st);
    policy.observe(
      Uri.parse('https://example.org'),
      Headers.fromMap({
        'strict-transport-security': ['max-age=0; max-age=10'],
      }),
    );
    expect(policy.upgrade(Uri.parse('http://example.org/')).scheme, 'https');
  });
}

class _HstsAdapter implements HttpClientAdapter {
  _HstsAdapter({this.statusCode = 200});

  final int statusCode;
  final List<String> urls = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    urls.add(options.uri.toString());
    return ResponseBody.fromString('ok', statusCode, headers: {
      Headers.contentTypeHeader: ['text/plain'],
      'strict-transport-security': ['max-age=60; includeSubDomains'],
    });
  }

  @override
  void close({bool force = false}) {}
}
