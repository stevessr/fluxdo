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
