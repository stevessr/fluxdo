import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/user_api_key_login_flow.dart';

void main() {
  group('Session identity probe failure classification', () {
    DioException probeError(int? status) {
      final request = RequestOptions(path: '/session/current.json');
      return DioException(
        requestOptions: request,
        response: status == null
            ? null
            : Response<dynamic>(
                requestOptions: request,
                statusCode: status,
              ),
      );
    }

    test('transient network and server failures permit OTP reconciliation', () {
      expect(
        UserApiKeyLoginFlow.isTransientCurrentUserProbeError(
          probeError(null),
        ),
        isTrue,
      );
      expect(
        UserApiKeyLoginFlow.isTransientCurrentUserProbeError(
          probeError(503),
        ),
        isTrue,
      );
    });

    test('explicit authorization rejection is never a login success', () {
      for (final status in [401, 403]) {
        expect(
          UserApiKeyLoginFlow.isTransientCurrentUserProbeError(
            probeError(status),
          ),
          isFalse,
        );
      }
    });
  });

  group('User API Key browser login classification', () {
    test('existing _t must not swallow a new authorization OTP', () {
      expect(
        UserApiKeyLoginFlow.isSupplementalAuthorization(
          existingToken: 'old-user-session',
          otp: '123abc',
          guestSession: false,
        ),
        isFalse,
      );
    });

    test('fresh OTP stays a login during guest account creation', () {
      expect(
        UserApiKeyLoginFlow.isSupplementalAuthorization(
          existingToken: 'stale-cookie',
          otp: '123abc',
          guestSession: true,
        ),
        isFalse,
      );
    });

    test('without OTP, existing non-guest session is authorization only', () {
      expect(
        UserApiKeyLoginFlow.isSupplementalAuthorization(
          existingToken: 'current-session',
          otp: null,
          guestSession: false,
        ),
        isTrue,
      );
    });

    test('without an existing session, missing OTP cannot finish login', () {
      expect(
        UserApiKeyLoginFlow.isSupplementalAuthorization(
          existingToken: null,
          otp: null,
          guestSession: false,
        ),
        isFalse,
      );
    });
  });
}
