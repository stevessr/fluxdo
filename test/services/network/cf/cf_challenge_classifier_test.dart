import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/cf/cf_challenge_classifier.dart';
import 'package:fluxdo/services/network/exceptions/api_exception.dart';

void main() {
  test('cf-mitigated 是权威信号，不依赖 content-type', () {
    expect(CfChallengeClassifier.isChallenge(statusCode: 429, cfMitigated: 'challenge', contentType: 'text/plain'), isTrue);
    expect(CfChallengeClassifier.isChallenge(statusCode: 503, cfMitigated: 'Challenge', contentType: 'application/json'), isTrue);
  });
  test('503 的挑战响应与普通 503、业务 403、404 可区分', () {
    expect(CfChallengeClassifier.isChallenge(statusCode: 503, contentType: 'text/html', body: 'cf_chl_opt'), isTrue);
    expect(CfChallengeClassifier.isChallenge(statusCode: 503, body: 'unavailable'), isFalse);
    expect(CfChallengeClassifier.isChallenge(statusCode: 403, contentType: 'application/json', body: 'cf_chl_opt'), isFalse);
    expect(CfChallengeClassifier.isChallenge(statusCode: 404, contentType: 'text/html', body: 'cf_chl_opt'), isFalse);
  });
  test('Dio 响应和包装后的异常均可识别', () {
    final options = RequestOptions(path: 'https://linux.do/latest.json');
    final response = Response<dynamic>(requestOptions: options, statusCode: 503, headers: Headers.fromMap({Headers.contentTypeHeader: ['text/html']}), data: 'cf_chl_opt');
    expect(CfChallengeClassifier.isChallengeResponse(response), isTrue);
    expect(CfChallengeClassifier.isChallengeFailure(DioException(requestOptions: options, response: response)), isTrue);
    expect(CfChallengeClassifier.isChallengeFailure(DioException(requestOptions: options, error: CfChallengeException())), isTrue);
  });
}
