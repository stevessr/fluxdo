import 'package:dio/dio.dart';

import 'auth_session.dart';
import 'log/log_writer.dart';
import 'network/cookie/cookie_jar_service.dart';
import 'user_api_key_service.dart';

/// 一次性登录令牌兑换的可靠性封装。
///
/// OTP 在服务端是一次性的：POST /session/otp/:token 一旦成功就会被消费，
/// 因此请求返回异常后不能安全地直接重放。与此同时，Dio 的响应拦截器会先把
/// Set-Cookie 写入 jar，再继续做 WebView cookie 同步；后半段同步如果失败，
/// 上层可能收到 DioException/空结果，但新的 `_t` 实际已经成功落盘。
///
/// 本封装在兑换前后对账 `_t`：正常返回优先采用服务结果；服务返回失败时，
/// 若发现 jar 中已经出现新的 `_t`，则把它视为“兑换成功、后处理失败”，继续
/// 登录收口。这样既避免误报失败，也不会冒险二次消费 OTP。
class LoginTokenRedeemer {
  LoginTokenRedeemer._();

  static Future<String?> redeemUserApiKeyOtp(
    Dio dio,
    String otp, {
    int? requestGeneration,
  }) async {
    final generation = requestGeneration ?? AuthSession().generation;
    bool isCurrent() => AuthSession().isValid(generation);

    final cookieJar = CookieJarService();
    final beforeToken = await cookieJar.getTToken();
    if (!isCurrent()) return null;

    final token = await UserApiKeyService().redeemOtp(
      dio,
      otp,
      requestGeneration: generation,
    );
    if (!isCurrent()) return null;
    if (token != null && token.isNotEmpty) return token;

    // 不重放一次性 OTP。先检查响应链是否其实已经把新 _t 落到了 jar。
    final afterToken = await cookieJar.getTToken();
    if (!isCurrent()) return null;
    if (!_isFreshToken(beforeToken, afterToken)) return null;

    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'warning',
      'type': 'auth',
      'event': 'otp_redeem_recovered_from_cookie',
      'message': 'OTP 兑换响应被判失败，但新 _t 已落盘，已按成功恢复',
      'hadTokenBefore': beforeToken != null && beforeToken.isNotEmpty,
      'hasTokenAfter': afterToken != null && afterToken.isNotEmpty,
      'tokenChanged': afterToken != beforeToken,
    });
    return afterToken;
  }

  static bool _isFreshToken(String? beforeToken, String? afterToken) {
    return afterToken != null &&
        afterToken.isNotEmpty &&
        afterToken != beforeToken;
  }
}
