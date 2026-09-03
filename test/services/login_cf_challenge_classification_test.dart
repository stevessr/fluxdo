import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/login_token_redeemer.dart';
import 'package:fluxdo/services/network/exceptions/api_exception.dart';
import 'package:fluxdo/services/network/interceptors/cf_challenge_terminal_interceptor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CF challenge 终态类型化', () {
    test('裸 403 challenge 不再泄漏为权限错误', () {
      final request = RequestOptions(path: '/session/current.json');
      final response = Response<dynamic>(
        requestOptions: request,
        statusCode: 403,
        data: '<html>Just a moment...</html>',
        headers: Headers.fromMap({
          'cf-mitigated': ['challenge'],
          'content-type': ['text/html; charset=UTF-8'],
        }),
      );
      final error = DioException(
        requestOptions: request,
        response: response,
        type: DioExceptionType.badResponse,
      );

      final normalized = CfChallengeTerminalInterceptor.normalize(error);

      expect(normalized.error, isA<CfChallengeException>());
      expect(
        normalized.response,
        isNull,
        reason: '业务层不应再看到 statusCode=403 并映射成“无权限访问资源”',
      );
      expect(LoginTokenRedeemer.isChallengeError(normalized), isTrue);
    });

    test('普通 Discourse 403 保留原始权限语义', () {
      final request = RequestOptions(path: '/admin/users/list/active.json');
      final response = Response<dynamic>(
        requestOptions: request,
        statusCode: 403,
        data: {'errors': ['You are not permitted to view this resource.']},
        headers: Headers.fromMap({
          'content-type': ['application/json'],
        }),
      );
      final error = DioException(
        requestOptions: request,
        response: response,
        type: DioExceptionType.badResponse,
      );

      final normalized = CfChallengeTerminalInterceptor.normalize(error);

      expect(identical(normalized, error), isTrue);
      expect(LoginTokenRedeemer.isChallengeError(normalized), isFalse);
      expect(normalized.response?.statusCode, 403);
    });

    test('已经类型化的 CF 异常保持不变', () {
      final request = RequestOptions(path: '/session/csrf');
      final error = DioException(
        requestOptions: request,
        error: CfChallengeException(userCancelled: true),
        type: DioExceptionType.unknown,
      );

      final normalized = CfChallengeTerminalInterceptor.normalize(error);

      expect(identical(normalized, error), isTrue);
      expect(LoginTokenRedeemer.isChallengeError(normalized), isTrue);
    });
  });
}
