import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/webview_login_session_probe.dart';

void main() {
  group('WebView OAuth/Passkey session probe', () {
    test('only first-party login pages may query the authenticated session', () {
      expect(
        WebViewLoginSessionProbe.isSameSiteUrl(
          'https://linux.do/login?redirect=%2F',
          'https://linux.do',
        ),
        isTrue,
      );
      expect(
        WebViewLoginSessionProbe.isSameSiteUrl(
          'https://linux.do/session/sso_login?code=test',
          'https://linux.do',
        ),
        isTrue,
      );
      expect(
        WebViewLoginSessionProbe.isSameSiteUrl(
          'https://evil.example/login',
          'https://linux.do',
        ),
        isFalse,
      );
      expect(
        WebViewLoginSessionProbe.isSameSiteUrl(
          'http://linux.do/login',
          'https://linux.do',
        ),
        isFalse,
      );
      expect(
        WebViewLoginSessionProbe.isSameSiteUrl(null, 'https://linux.do'),
        isFalse,
      );
    });

    test('guest can adopt a pre-existing authenticated WebView session', () {
      final baseline = WebViewLoginSessionProbe.baselineToken(
        webViewToken: 'browser-session',
        appToken: null,
        guestSession: true,
      );
      expect(baseline, isNull);
      expect(
        WebViewLoginSessionProbe.isNewSessionToken(
          'browser-session',
          baseline,
        ),
        isTrue,
      );
    });

    test('account switch cannot adopt an unchanged old WebView session', () {
      final baseline = WebViewLoginSessionProbe.baselineToken(
        webViewToken: 'previous-browser-session',
        appToken: 'current-app-session',
        guestSession: false,
      );
      expect(baseline, 'previous-browser-session');
      expect(
        WebViewLoginSessionProbe.isNewSessionToken(
          'previous-browser-session',
          baseline,
        ),
        isFalse,
      );
      expect(
        WebViewLoginSessionProbe.isNewSessionToken('new-session', baseline),
        isTrue,
      );
    });

    test('valid current_user response establishes a verified username', () {
      final evidence = {
        'probeComplete': true,
        'current_user': {'username': 'new-user', 'id': 123},
      };
      expect(WebViewLoginSessionProbe.isCompletedProbe(evidence), isTrue);
      expect(
        WebViewLoginSessionProbe.usernameFromSession(evidence),
        'new-user',
      );
    });

    test('anonymous, blocked, or malformed response never logs in', () {
      for (final evidence in [
        null,
        {'probeComplete': false, 'current_user': {'username': 'old-user'}},
        {'probeComplete': true, 'current_user': null},
        {'probeComplete': true, 'current_user': {'username': '  '}},
        {'probeComplete': true, 'current_user': {'username': 123}},
      ]) {
        expect(WebViewLoginSessionProbe.usernameFromSession(evidence), isNull);
      }
    });
  });
}
