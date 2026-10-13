import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/interceptors/https_security_interceptor.dart';

void main() {
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
    await dio.get<void>('http://example.org/next');
    expect(adapter.urls, [
      'https://example.org/initial',
      'https://example.org/next',
    ]);
    dio.close(force: true);
  });
}

class _HstsAdapter implements HttpClientAdapter {
  final List<String> urls = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    urls.add(options.uri.toString());
    return ResponseBody.fromString('ok', 200, headers: {
      Headers.contentTypeHeader: ['text/plain'],
      'strict-transport-security': ['max-age=60; includeSubDomains'],
    });
  }

  @override
  void close({bool force = false}) {}
}
