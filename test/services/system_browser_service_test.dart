import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/system_browser_service.dart';

void main() {
  group('SystemBrowserService', () {
    test('opens only the LINUX DO User API Key authorization entrypoint', () {
      expect(
        SystemBrowserService.isAuthorizationUrl(
          Uri.parse('https://linux.do/user-api-key/new?nonce=test'),
        ),
        isTrue,
      );

      for (final url in [
        'http://linux.do/user-api-key/new',
        'https://fake-linux.do/user-api-key/new',
        'https://linux.do.evil.example/user-api-key/new',
        'https://linux.do/auth/github/callback',
        'https://linux.do/user-api-key/activate',
        'https://linux.do/user-api-key/new/extra',
        'fluxdo://auth_redirect?payload=test',
      ]) {
        expect(
          SystemBrowserService.isAuthorizationUrl(Uri.parse(url)),
          isFalse,
          reason: 'Unexpected authorization URL: ' + url,
        );
      }
    });

    test('browser choices preserve explicit identifiers', () {
      const firefox = LoginBrowser(
        id: 'linux:firefox',
        name: 'Firefox',
        executable: 'firefox',
      );
      const flatpak = LoginBrowser(
        id: 'flatpak:org.mozilla.firefox',
        name: 'Firefox (Flatpak)',
        executable: 'flatpak',
        arguments: ['run', 'org.mozilla.firefox'],
      );

      expect(firefox.id, isNot(flatpak.id));
      expect(flatpak.arguments, ['run', 'org.mozilla.firefox']);
      expect(firefox.executable, 'firefox');
    });
  });
}
