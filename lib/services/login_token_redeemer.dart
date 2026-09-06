import 'dart:convert';

import 'package:dio/dio.dart';

import 'auth_session.dart';
import 'cf_challenge_service.dart';
import 'log/log_writer.dart';
import 'network/cookie/cookie_jar_service.dart';
import 'network/exceptions/api_exception.dart';

/// 一次性登录令牌兑换的可靠性封装。
///
/// 与普通 API 重试不同，Discourse OTP 是一次性的：POST /session/otp/:token
/// 一旦在服务端成功就会被消费。因此这里绝不能在“不确定请求是否已经到达服务端”
/// 的情况下盲目重放，而是通过兑换前后的 `_t` 对账来判断真实结果。
///
/// 同时把 Cloudflare challenge 单独建模：盾产生的 403/429（或被
/// [CfChallengeInterceptor] 转换后的 [CfChallengeException]）不能被上层误报为
/// “令牌失效 / 无权限”。
class LoginTokenRedeemer {
  LoginTokenRedeemer._();

  static Future<LoginTokenRedeemResult> redeemUserApiKeyOtp(
    Dio dio,
    String otp, {
    int? requestGeneration,
  }) async {
    final generation = requestGeneration ?? AuthSession().generation;
    bool isCurrent() => AuthSession().isValid(generation);

    if (!RegExp(r'^[0-9a-f]+$').hasMatch(otp)) {
      _log(
        'warning',
        'login_otp_bad_format',
        '登录 OTP 格式异常，拒绝兑换',
      );
      return const LoginTokenRedeemResult.failed();
    }

    final cookieJar = CookieJarService();

    // 兑换前必须成功取得基线。若这里失败，直接停止且绝不发送 OTP：
    // 否则后续看到一个本来就存在的 `_t` 时无法安全判断它是否由本次兑换产生。
    final beforeSnapshot = await _readTToken(cookieJar, phase: 'before');
    if (!isCurrent()) return const LoginTokenRedeemResult.failed();
    if (!beforeSnapshot.succeeded) {
      _log(
        'warning',
        'login_otp_cookie_baseline_failed',
        '登录 OTP 兑换前无法读取 _t 基线，已停止兑换以避免误判',
        {'error': beforeSnapshot.error.toString()},
      );
      return const LoginTokenRedeemResult.failed();
    }
    final beforeToken = beforeSnapshot.token;

    try {
      final csrf = await _fetchCsrf(dio);
      if (!isCurrent()) return const LoginTokenRedeemResult.failed();
      if (csrf == null || csrf.isEmpty) {
        _log(
          'warning',
          'login_otp_missing_csrf',
          '登录 OTP 兑换前未取得 CSRF token',
        );
        return const LoginTokenRedeemResult.failed();
      }

      await dio.post<dynamic>(
        '/session/otp/$otp',
        options: Options(
          followRedirects: false,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
          headers: {
            'X-CSRF-Token': csrf,
            'X-Requested-With': 'XMLHttpRequest',
          },
          extra: const {
            'skipCsrf': true,
            'skipAuthCheck': true,
            'skipRedirect': true,
            'requestTag': 'login-otp-redeem',
          },
        ),
      );

      if (!isCurrent()) return const LoginTokenRedeemResult.failed();
      final afterSnapshot = await _readTToken(cookieJar, phase: 'after');
      if (!isCurrent()) return const LoginTokenRedeemResult.failed();
      if (!afterSnapshot.succeeded) {
        _log(
          'warning',
          'login_otp_cookie_verify_failed',
          '登录 OTP 请求完成，但读取兑换后的 _t 失败；不会重放一次性 OTP',
          {'error': afterSnapshot.error.toString()},
        );
        return const LoginTokenRedeemResult.failed();
      }

      final afterToken = afterSnapshot.token;
      if (_isFreshToken(beforeToken, afterToken)) {
        _log(
          'info',
          'login_otp_redeem_success',
          '登录 OTP 兑换成功，已获得新 _t',
        );
        return LoginTokenRedeemResult.success(afterToken!);
      }

      _log(
        'warning',
        'login_otp_no_session_cookie',
        '登录 OTP 请求完成，但未观察到新的 _t；不会重放一次性 OTP',
      );
      return const LoginTokenRedeemResult.failed();
    } on DioException catch (e) {
      if (!isCurrent()) return const LoginTokenRedeemResult.failed();

      // OTP 可能已经在服务端成功消费，只是后续响应/同步链路抛错。
      // 在分类原始网络错误之前先对账 cookie，避免把“已经登录成功”误报为失败，
      // 也避免再次发送一次性 OTP。
      //
      // 注意：对账读取本身也可能失败。它不能覆盖原始 DioException，更不能
      // 逃出本方法；读取失败时继续按原始异常分类即可。
      final afterSnapshot = await _readTToken(cookieJar, phase: 'reconcile');
      if (!isCurrent()) return const LoginTokenRedeemResult.failed();
      if (afterSnapshot.succeeded &&
          _isFreshToken(beforeToken, afterSnapshot.token)) {
        _log(
          'warning',
          'login_otp_recovered_from_cookie',
          '登录 OTP 响应链报错，但新 _t 已落盘，按兑换成功恢复',
          {
            'statusCode': e.response?.statusCode,
            'errorType': e.type.toString(),
          },
        );
        return LoginTokenRedeemResult.success(afterSnapshot.token!);
      }
      if (!afterSnapshot.succeeded) {
        _log(
          'warning',
          'login_otp_cookie_reconcile_failed',
          '登录 OTP 响应链报错，且 _t 对账读取失败；保留原始异常分类',
          {
            'statusCode': e.response?.statusCode,
            'errorType': e.type.toString(),
            'cookieError': afterSnapshot.error.toString(),
          },
        );
      }

      if (isChallengeError(e)) {
        _log(
          'warning',
          'login_otp_blocked_by_cf',
          '登录 OTP 兑换被 Cloudflare challenge 阻断，未按令牌失效处理',
          {
            'statusCode': e.response?.statusCode,
            'errorType': e.type.toString(),
          },
        );
        return const LoginTokenRedeemResult.blockedByChallenge();
      }

      _log(
        'warning',
        'login_otp_redeem_failed',
        '登录 OTP 兑换请求失败',
        {
          'statusCode': e.response?.statusCode,
          'errorType': e.type.toString(),
        },
      );
      return const LoginTokenRedeemResult.failed();
    } catch (e) {
      _log(
        'warning',
        'login_otp_redeem_failed',
        '登录 OTP 兑换发生非网络异常',
        {'error': e.toString()},
      );
      return const LoginTokenRedeemResult.failed();
    }
  }

  /// 统一判断“这不是鉴权失败，而是 Cloudflare 盾”。
  ///
  /// 第一种是 CF 拦截器已经把响应类型化；第二种用于兜底识别尚未经过
  /// terminal normalizer 的原始 challenge response。
  static bool isChallengeError(DioException error) {
    return error.error is CfChallengeException ||
        CfChallengeService.isCfChallengeResponse(error.response);
  }

  static Future<String?> _fetchCsrf(Dio dio) async {
    final response = await dio.get<dynamic>(
      '/session/csrf',
      options: Options(
        headers: const {
          'X-Requested-With': 'XMLHttpRequest',
          'Accept': 'application/json, text/javascript, */*; q=0.01',
        },
        extra: const {
          'skipCsrf': true,
          'skipAuthCheck': true,
          'requestTag': 'login-otp-csrf',
        },
      ),
    );

    final data = response.data;
    if (data is Map) return data['csrf']?.toString();
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return decoded['csrf']?.toString();
      } catch (_) {}
    }
    return null;
  }

  static Future<_TTokenSnapshot> _readTToken(
    CookieJarService cookieJar, {
    required String phase,
  }) async {
    try {
      return _TTokenSnapshot.success(await cookieJar.getTToken());
    } catch (e) {
      return _TTokenSnapshot.failed(e, phase);
    }
  }

  static bool _isFreshToken(String? beforeToken, String? afterToken) {
    return afterToken != null &&
        afterToken.isNotEmpty &&
        afterToken != beforeToken;
  }

  static void _log(
    String level,
    String event,
    String message, [
    Map<String, dynamic>? fields,
  ]) {
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': level,
      'type': 'auth',
      'event': event,
      'message': message,
      ...?fields,
    });
  }
}

class LoginTokenRedeemResult {
  const LoginTokenRedeemResult._({this.token, this.challengeBlocked = false});

  const LoginTokenRedeemResult.success(String token)
      : this._(token: token);

  const LoginTokenRedeemResult.failed() : this._();

  const LoginTokenRedeemResult.blockedByChallenge()
      : this._(challengeBlocked: true);

  final String? token;
  final bool challengeBlocked;

  bool get succeeded => token != null && token!.isNotEmpty;
}

class _TTokenSnapshot {
  const _TTokenSnapshot._({this.token, this.error, required this.phase});

  const _TTokenSnapshot.success(String? token)
      : this._(token: token, phase: '');

  const _TTokenSnapshot.failed(Object error, String phase)
      : this._(error: error, phase: phase);

  final String? token;
  final Object? error;
  final String phase;

  bool get succeeded => error == null;
}
