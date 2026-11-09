import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/login_token_redeemer.dart';

void main() {
  Response<dynamic> otpResponse({
    String host = 'linux.do',
    String path = '/session/otp/abcdef0123',
    String method = 'POST',
    int status = 302,
    List<String>? setCookies,
  }) {
    return Response<dynamic>(
      requestOptions: RequestOptions(
        baseUrl: 'https://$host',
        path: path,
        method: method,
      ),
      statusCode: status,
      headers: Headers.fromMap({
        'set-cookie': setCookies ?? ['_t=new-session-token; Path=/; HttpOnly'],
      }),
    );
  }

  group('OTP redemption response reconciliation', () {
    test('extracts the issued _t from the first-party 302', () {
      expect(
        LoginTokenRedeemer.issuedTokenFromOtpResponse(otpResponse()),
        'new-session-token',
      );
    });

    test('handles multiple and combined Set-Cookie headers', () {
      expect(
        LoginTokenRedeemer.issuedTokenFromOtpResponse(
          otpResponse(
            setCookies: [
              'theme=light; Path=/',
              '_forum_session=other; Path=/, _t=fresh; Path=/; HttpOnly',
            ],
          ),
        ),
        'fresh',
      );
    });

    test('never trusts challenge, unrelated origin, or ordinary API response', () {
      expect(
        LoginTokenRedeemer.issuedTokenFromOtpResponse(
          otpResponse(status: 403),
        ),
        isNull,
      );
      expect(
        LoginTokenRedeemer.issuedTokenFromOtpResponse(
          otpResponse(host: 'external.example'),
        ),
        isNull,
      );
      expect(
        LoginTokenRedeemer.issuedTokenFromOtpResponse(
          otpResponse(path: '/session/current.json'),
        ),
        isNull,
      );
      expect(
        LoginTokenRedeemer.issuedTokenFromOtpResponse(
          otpResponse(method: 'GET'),
        ),
        isNull,
      );
      expect(
        LoginTokenRedeemer.issuedTokenFromOtpResponse(
          otpResponse(setCookies: ['_t=del; Max-Age=0']),
        ),
        isNull,
      );
    });
  });
}
