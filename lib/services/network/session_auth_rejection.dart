import 'package:dio/dio.dart';

import '../cf_challenge_service.dart';

/// A bare HTTP 403 does not prove that a Discourse session has expired.
///
/// Cloudflare WAF/challenge responses and ordinary permission-denied responses
/// can both return 403. Only a response carrying an explicit Discourse logout
/// signal is sufficient to treat *this status* as an authentication rejection.
/// 401/404 and successful session probes are handled by their own callers.
class SessionAuthRejection {
  static bool isExplicitLogout403(Response<dynamic>? response) {
    if (response?.statusCode != 403 ||
        CfChallengeService.isCfChallengeResponse(response)) {
      return false;
    }

    final loggedOut = response!.headers.value('discourse-logged-out');
    if (loggedOut != null && loggedOut.trim().isNotEmpty) {
      return true;
    }

    final data = response.data;
    return data is Map && data['error_type'] == 'not_logged_in';
  }
}
