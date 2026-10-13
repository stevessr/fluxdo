import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/adapters/rhttp_adapter.dart';

void main() {
  RequestOptions options(String scheme, {String method = 'GET'}) {
    return RequestOptions(
      path: '/latest.json',
      baseUrl: '$scheme://linux.do',
      method: method,
    );
  }

  group('rhttp HTTP/3 Alt-Svc discovery', () {
    test('recognizes valid modern H3 advertisements case-insensitively', () {
      expect(http3AltSvcAdvertised({
        'Alt-Svc': ['h2=":443"; ma=60, h3=":443"; ma=86400'],
      }), isTrue);
      expect(http3AltSvcAdvertised({
        'ALT-SVC': ['H3=":443"; ma=60'],
      }), isTrue);
    });

    test('ignores expired hints, old protocol IDs and unrelated headers', () {
      expect(http3AltSvcAdvertised({
        'alt-svc': ['h3=":443"; ma=0'],
      }), isFalse);
      expect(http3AltSvcAdvertised({
        'alt-svc': ['h3-29=":443"; ma=86400'],
      }), isFalse);
      expect(http3AltSvcAdvertised({
        'content-type': ['h3=":443"'],
      }), isFalse);
    });

    test('does not probe unsupported alternative host or port', () {
      expect(http3AltSvcAdvertised({
        'Alt-Svc': ['h3=":8443"; ma=3600'],
      }), isFalse);
      expect(http3AltSvcAdvertised({
        'Alt-Svc': ['h3="alt.example.org:443"; ma=3600'],
      }), isFalse);
      expect(http3AltSvcAdvertised({
        'Alt-Svc': ['h3=":8443"; ma=3600'],
      }, originPort: 8443), isTrue);
      expect(http3AltSvcAdvertised({
        'Alt-Svc': ['h3=":443"; ma=3600'],
      }, originPort: 8443), isFalse);
    });

    test('a different-port revocation cannot clear this origin', () {
      expect(http3AltSvcRevoked({
        'Alt-Svc': ['h3=":8443"; ma=0'],
      }), isFalse);
      expect(http3AltSvcRevoked({
        'Alt-Svc': ['h3=":8443"; ma=0'],
      }, originPort: 8443), isTrue);
    });

    test('Alt-Svc clear invalidates the cached advertisement', () {
      expect(http3AltSvcCleared({
        'Alt-Svc': ['clear'],
      }), isTrue);
      expect(http3AltSvcCleared({
        'Alt-Svc': ['h3=":443"; ma=3600'],
      }), isFalse);
      expect(http3AltSvcRevoked({
        'Alt-Svc': ['h3=":443"; ma=0'],
      }), isTrue);
      expect(http3AltSvcRevoked({
        'Alt-Svc': ['h3=":443"; ma=3600'],
      }), isFalse);
      expect(http3AltSvcRevoked({
        'Alt-Svc': ['h2=":443"; ma=0'],
      }), isFalse);
    });
  });

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
        requestCanProbeRhttpHttp3(options('https'), hasRequestStream: true),
        isFalse,
      );
    });
  });
}
