/// Validates the evidence used to close an embedded OAuth/Passkey login.
///
/// A redirect to / or a hydrated Discourse page is not sufficient evidence:
/// only a first-party, authenticated session with a username and a _t cookie
/// may complete the login flow.
class WebViewLoginSessionProbe {
  const WebViewLoginSessionProbe._();

  static bool isSameSiteUrl(String? rawUrl, String baseUrl) {
    final current = Uri.tryParse(rawUrl ?? '');
    final base = Uri.tryParse(baseUrl);
    if (current == null || base == null) return false;
    return current.scheme == base.scheme &&
        current.host.toLowerCase() == base.host.toLowerCase() &&
        current.port == base.port;
  }

  /// 未登录/guest 本地会话应接管浏览器里已经存在的登录状态。
  /// 只有正在切换一个已登录账号时，才把 WebView 原有的 _t 作为基线，
  /// 避免把旧账号误识别成这次 OAuth 登录。
  static String? baselineToken({
    required String? webViewToken,
    required String? appToken,
    required bool guestSession,
  }) {
    if (guestSession) return null;
    if (appToken == null || appToken.isEmpty) return appToken;
    return webViewToken != null && webViewToken.isNotEmpty
        ? webViewToken
        : appToken;
  }

  static bool isNewSessionToken(String? token, String? baseline) =>
      token != null && token.isNotEmpty && token != baseline;

  static String? usernameFromSession(Object? data) {
    if (data is! Map || data['probeComplete'] != true) return null;
    final user = data['current_user'];
    if (user is! Map) return null;
    final username = user['username'];
    if (username is! String) return null;
    final trimmed = username.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool isCompletedProbe(Object? data) =>
      data is Map && data['probeComplete'] == true;
}
