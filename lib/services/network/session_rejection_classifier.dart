import 'package:dio/dio.dart';

import '../cf_challenge_service.dart';
import 'exceptions/api_exception.dart';

/// /session/current.json 的拒绝不能只看 HTTP 状态码。
///
/// Cloudflare challenge/block 和 Discourse 自身的权限拒绝都可能返回 403。
/// 只有明确的登录失效证据才能清理账号；无法确认时应保留本地凭据。
enum SessionRejectionKind { confirmedInvalid, cloudflareBlocked, inconclusive }

class SessionRejectionClassifier {
  const SessionRejectionClassifier._();

  /// cf-mitigated 是 Cloudflare 给出的权威标志（也可能是非 challenge 的阻断）。
  /// 没有该头时，沿用现有的 CF challenge body 识别逻辑。
  static bool isCloudflareMitigationResponse(Response<dynamic>? response) {
    if (response == null) return false;
    final mitigated = response.headers.value('cf-mitigated');
    return (mitigated != null && mitigated.trim().isNotEmpty) ||
        CfChallengeService.isCfChallengeResponse(response);
  }

  static bool isCloudflareBlocked(DioException error) {
    return error.error is CfChallengeException ||
        isCloudflareMitigationResponse(error.response);
  }

  static SessionRejectionKind classify(DioException error) {
    if (isCloudflareBlocked(error)) {
      return SessionRejectionKind.cloudflareBlocked;
    }

    final response = error.response;
    if (response == null) return SessionRejectionKind.inconclusive;

    final status = response.statusCode;
    // Discourse 的 session/current 在用户已不存在时返回 404。
    if (status == 404) return SessionRejectionKind.confirmedInvalid;
    if (status != 401 && status != 403) {
      return SessionRejectionKind.inconclusive;
    }

    // Discourse 明确声明退出，或 JSON body 明确写 not_logged_in。
    final loggedOut = response.headers.value('discourse-logged-out');
    if (loggedOut != null && loggedOut.trim().isNotEmpty) {
      return SessionRejectionKind.confirmedInvalid;
    }
    final body = response.data;
    if (body is Map && body['error_type'] == 'not_logged_in') {
      return SessionRejectionKind.confirmedInvalid;
    }

    // 401 仍是源站明确拒绝；403 单独出现仅表示禁止访问，不能说明 _t 失效。
    // cf-ray/server: cloudflare 在正常代理响应里也存在，不能单凭它们判断撞盾。
    return status == 401
        ? SessionRejectionKind.confirmedInvalid
        : SessionRejectionKind.inconclusive;
  }
}
