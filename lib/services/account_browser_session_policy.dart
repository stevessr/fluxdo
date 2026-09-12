import '../constants.dart';
import '../config/discourse_instance_runtime.dart';
import 'network/cookie/cookie_jar_service.dart';

/// Defines the WebView origins whose login state is part of an account
/// snapshot.
///
/// App-owned origins continue to use [CookieJarService.matchesAppHost].
/// Third-party origins must be explicitly allowlisted here so account switching
/// cannot accidentally persist or restore arbitrary browser cookies.
class AccountBrowserSessionPolicy {
  AccountBrowserSessionPolicy._();

  static const List<String> _linuxDoAppOrigins = [
    'https://linux.do/',
    'https://credit.linux.do/',
    'https://cdk.linux.do/',
    'https://connect.linux.do/',
  ];

  /// 非默认实例只把当前 Discourse origin 作为账号浏览器边界。
  static List<String> get appOrigins {
    if (DiscourseInstanceRuntime.isDefaultInstance) {
      return _linuxDoAppOrigins;
    }
    return ['${AppConstants.baseUrl}/'];
  }

  /// External sites whose WebView login is intentionally tied to the active
  /// linux.do account/profile. Generic Discourse instances must not inherit
  /// these linux.do-specific account bindings.
  static List<String> get externalAccountOrigins =>
      DiscourseInstanceRuntime.isDefaultInstance
      ? const ['https://anyrouter.top/']
      : const [];

  static List<String> get snapshotOrigins => [
    ...appOrigins,
    ...externalAccountOrigins,
  ];

  static bool isAllowedRestoreOrigin(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') return false;

    final host = uri.host.toLowerCase();
    if (CookieJarService.matchesAppHost(host)) {
      // app-owned origin may be HTTP for local/self-hosted experimental sites,
      // but must still match the active instance's scheme.
      return scheme == Uri.parse(AppConstants.baseUrl).scheme.toLowerCase();
    }

    // Third-party account bindings are intentionally HTTPS-only.
    if (scheme != 'https') return false;
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
