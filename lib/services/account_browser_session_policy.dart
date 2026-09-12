import 'network/cookie/cookie_jar_service.dart';

/// Defines the WebView origins whose login state is part of an account
/// snapshot.
///
/// App-owned origins continue to use [CookieJarService.matchesAppHost].
/// Third-party origins must be explicitly allowlisted here so account switching
/// cannot accidentally persist or restore arbitrary browser cookies.
class AccountBrowserSessionPolicy {
  AccountBrowserSessionPolicy._();

  static const List<String> appOrigins = [
    'https://linux.do/',
    'https://credit.linux.do/',
    'https://cdk.linux.do/',
    'https://connect.linux.do/',
  ];

  /// External sites whose WebView login is intentionally tied to the active
  /// linux.do account/profile.
  static const List<String> externalAccountOrigins = [
    'https://anyrouter.top/',
  ];

  static const List<String> snapshotOrigins = [
    ...appOrigins,
    ...externalAccountOrigins,
  ];

  static bool isAllowedRestoreOrigin(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.toLowerCase() != 'https') return false;

    final host = uri.host.toLowerCase();
    if (CookieJarService.matchesAppHost(host)) return true;

    return externalAccountOrigins.any(
      (origin) => Uri.parse(origin).host.toLowerCase() == host,
    );
  }

  static bool isExternalAccountOrigin(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.toLowerCase() != 'https') return false;
    final host = uri.host.toLowerCase();
    return externalAccountOrigins.any(
      (origin) => Uri.parse(origin).host.toLowerCase() == host,
    );
  }
}
