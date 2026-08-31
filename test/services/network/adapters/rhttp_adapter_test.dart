import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/adapters/rhttp_adapter.dart';

void main() {
  RequestOptions options(
    String scheme, {
    String method = 'GET',
  }) {
    return RequestOptions(
      path: '/latest.json',
      baseUrl: '$scheme://linux.do',
      method: method,
    );
  }

  group('requestCanProbeRhttpHttp3', () {
    test('allows replay-safe HTTPS requests', () {
      expect(requestCanProbeRhttpHttp3(options('https')), isTrue);
      expect(
        requestCanProbeRhttpHttp3(options('https', method: 'HEAD')),
        isTrue,
      );
      expect(
        requestCanProbeRhttpHttp3(options('https', method: 'OPTIONS')),
        isTrue,
      );
    });

    test('rejects plaintext, unsafe methods and request streams', () {
      expect(requestCanProbeRhttpHttp3(options('http')), isFalse);
      expect(
        requestCanProbeRhttpHttp3(options('https', method: 'POST')),
        isFalse,
      );
      expect(
        requestCanProbeRhttpHttp3(
          options('https'),
          hasRequestStream: true,
        ),
        isFalse,
      );
    });
  });
}
