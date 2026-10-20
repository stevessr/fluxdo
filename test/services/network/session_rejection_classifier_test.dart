import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/exceptions/api_exception.dart';
import 'package:fluxdo/services/network/session_rejection_classifier.dart';

void main() {
  DioException failure(
    int status, {
    Object? body,
    Map<String, List<String>> headers = const {},
  }) {
    final request = RequestOptions(
      baseUrl: 'https://linux.do',
      path: '/session/current.json',
    );
    return DioException(
      requestOptions: request,
      response: Response<dynamic>(
        requestOptions: request,
        statusCode: status,
        headers: Headers.fromMap(headers),
        data: body,
      ),
      type: DioExceptionType.badResponse,
    );
  }

  group('403 会话拒绝识别', () {
    test('CF challenge 头优先于任何 Discourse 登录失效信号', () {
      final error = failure(
        403,
        body: {'error_type': 'not_logged_in'},
        headers: {
          'cf-mitigated': ['challenge'],
          'discourse-logged-out': ['true'],
          'content-type': ['application/json'],
        },
      );
      expect(
        SessionRejectionClassifier.classify(error),
        SessionRejectionKind.cloudflareBlocked,
      );
    });

    test('CF block 头即使不叫 challenge 也不能触发账号失效', () {
      expect(
        SessionRejectionClassifier.classify(
          failure(
            403,
            headers: {
              'cf-mitigated': ['block'],
            },
          ),
        ),
        SessionRejectionKind.cloudflareBlocked,
      );
    });

    test('挑战页面体兜底识别', () {
      final error = failure(
        403,
        body: '<html><script>var cf_chl_opt = {};</script></html>',
        headers: {
          'content-type': ['text/html'],
        },
      );
      expect(
        SessionRejectionClassifier.classify(error),
        SessionRejectionKind.cloudflareBlocked,
      );
    });

    test('仅有 403/CF 代理通用响应头，不足以说明账号失效', () {
      final error = failure(
        403,
        body: {
          'errors': ['You are not permitted to view this resource.'],
        },
        headers: {
          'content-type': ['application/json'],
          'cf-ray': ['example-edge-ray'],
          'server': ['cloudflare'],
        },
      );
      expect(
        SessionRejectionClassifier.classify(error),
        SessionRejectionKind.inconclusive,
      );
    });

    test('Discourse 明确报告 not_logged_in 才视为失效', () {
      final error = failure(403, body: {'error_type': 'not_logged_in'});
      expect(
        SessionRejectionClassifier.classify(error),
        SessionRejectionKind.confirmedInvalid,
      );
    });

    test('Discourse 的 discourse-logged-out 头是认证信号', () {
      final error = failure(
        403,
        headers: {
          'discourse-logged-out': ['true'],
        },
      );
      expect(
        SessionRejectionClassifier.classify(error),
        SessionRejectionKind.confirmedInvalid,
      );
    });
  });

  test('401 和源站 404 保留已有的明确失效语义', () {
    expect(
      SessionRejectionClassifier.classify(failure(401)),
      SessionRejectionKind.confirmedInvalid,
    );
    expect(
      SessionRejectionClassifier.classify(failure(404)),
      SessionRejectionKind.confirmedInvalid,
    );
  });

  test('CF 已类型化的异常不应重走 auth invalid 链', () {
    final request = RequestOptions(path: '/session/current.json');
    final error = DioException(
      requestOptions: request,
      error: CfChallengeException(autoVerifyDisabled: true),
      type: DioExceptionType.unknown,
    );
    expect(
      SessionRejectionClassifier.classify(error),
      SessionRejectionKind.cloudflareBlocked,
    );
  });

  test('429 普通限流不等于登录失效', () {
    expect(
      SessionRejectionClassifier.classify(failure(429)),
      SessionRejectionKind.inconclusive,
    );
  });
}
