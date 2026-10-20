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

    test('Linux 可识别 Chrome / Edge / Firefox 的独立发布通道', () {
      final commands = {
        for (final entry in SystemBrowserService.linuxBrowserCommands)
          entry.command: entry.name,
      };
      expect(commands['google-chrome-beta'], 'Google Chrome Beta');
      expect(commands['google-chrome-unstable'], 'Google Chrome Dev');
      expect(commands['google-chrome-canary'], 'Google Chrome Canary');
      expect(commands['microsoft-edge-beta'], 'Microsoft Edge Beta');
      expect(commands['microsoft-edge-dev'], 'Microsoft Edge Dev');
      expect(commands['firefox-beta'], 'Firefox Beta');
      expect(commands['firefox-nightly'], 'Firefox Nightly');
      expect(commands['firefox-developer-edition'], 'Firefox Developer Edition');
      expect(commands['firefox'], 'Firefox');
    });

    test('macOS 可分别选择应用包与预览通道', () {
      final names = SystemBrowserService.macBrowserAppNames;
      for (final name in [
        'Google Chrome Beta',
        'Google Chrome Dev',
        'Google Chrome Canary',
        'Microsoft Edge Beta',
        'Microsoft Edge Dev',
        'Microsoft Edge Canary',
        'Firefox Beta',
        'Firefox Nightly',
        'Firefox Developer Edition',
      ]) {
        expect(names, contains(name));
      }
    });

    test('Windows Canary 的 SxS 与 Beta / Dev 各自采用独立安装目录', () {
      final paths = {
        for (final entry in SystemBrowserService.windowsBrowserInstallPaths)
          entry.name: entry.relative,
      };
      expect(paths['Google Chrome Canary'], contains('Chrome SxS'));
      expect(paths['Microsoft Edge Canary'], contains('Edge SxS'));
      expect(paths['Google Chrome Beta'], contains('Chrome Beta'));
      expect(paths['Google Chrome Dev'], contains('Chrome Dev'));
      expect(paths['Microsoft Edge Beta'], contains('Edge Beta'));
      expect(paths['Microsoft Edge Dev'], contains('Edge Dev'));
      expect(paths['Firefox Nightly'], contains('Nightly'));
      expect(paths['Firefox Developer Edition'],
          contains('Developer Edition'));
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
