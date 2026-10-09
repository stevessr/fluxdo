import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// A browser chosen explicitly by the user. Never reads or copies its cookies.
class LoginBrowser {
  const LoginBrowser({
    required this.id,
    required this.name,
    this.executable,
    this.arguments = const [],
  });

  final String id;
  final String name;
  final String? executable;
  final List<String> arguments;
}

/// Opens Discourse's User API Key authorization page in a particular installed
/// browser, so an existing Google/GitHub login in that browser can be reused.
///
/// The provider's OAuth callback still goes to linux.do. The separate
/// discourse://auth_redirect callback is handled by DeepLinkService.
class SystemBrowserService {
  SystemBrowserService._();
  static final instance = SystemBrowserService._();

  static const _channel = MethodChannel(
    'com.github.lingyan000.fluxdo/browser',
  );
  static const _default = LoginBrowser(
    id: 'default',
    name: '系统默认浏览器',
  );

  // Flatpak must not inspect or execute binaries on the host. The portal's
  // OpenURI ask option displays the host's browser/application chooser.
  static const _portalChooser = LoginBrowser(
    id: 'portal:chooser',
    name: '选择系统已安装的浏览器',
  );

  static bool get _inFlatpak =>
      Platform.environment.containsKey('FLATPAK_ID') ||
      File('/.flatpak-info').existsSync();

  static const _linuxBrowsers = <({String name, String command})>[
    (name: 'Firefox', command: 'firefox'),
    (name: 'Firefox Developer Edition', command: 'firefox-developer-edition'),
    (name: 'LibreWolf', command: 'librewolf'),
    (name: 'Zen Browser', command: 'zen-browser'),
    (name: 'Floorp', command: 'floorp'),
    (name: 'Waterfox', command: 'waterfox'),
    (name: 'Chromium', command: 'chromium'),
    (name: 'Chromium', command: 'chromium-browser'),
    (name: 'Google Chrome', command: 'google-chrome-stable'),
    (name: 'Google Chrome', command: 'google-chrome'),
    (name: 'Brave', command: 'brave-browser'),
    (name: 'Microsoft Edge', command: 'microsoft-edge-stable'),
    (name: 'Microsoft Edge', command: 'microsoft-edge'),
    (name: 'Vivaldi', command: 'vivaldi-stable'),
    (name: 'Vivaldi', command: 'vivaldi'),
    (name: 'Opera', command: 'opera'),
    (name: 'Cromite', command: 'cromite'),
    (name: 'Thorium', command: 'thorium-browser'),
    (name: 'Mullvad Browser', command: 'mullvad-browser'),
  ];

  static const _flatpakBrowsers = <({String name, String appId})>[
    (name: 'Firefox', appId: 'org.mozilla.firefox'),
    (name: 'LibreWolf', appId: 'io.gitlab.librewolf-community'),
    (name: 'Chromium', appId: 'org.chromium.Chromium'),
    (name: 'Google Chrome', appId: 'com.google.Chrome'),
    (name: 'Brave', appId: 'com.brave.Browser'),
    (name: 'Microsoft Edge', appId: 'com.microsoft.Edge'),
    (name: 'Vivaldi', appId: 'com.vivaldi.Vivaldi'),
    (name: 'Opera', appId: 'com.opera.Opera'),
    (name: 'Zen Browser', appId: 'app.zen_browser.zen'),
  ];

  /// Only use this launcher for our own HTTPS authorization endpoint.
  static bool isAuthorizationUrl(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == 'linux.do' &&
      uri.path == '/user-api-key/new';

  Future<List<LoginBrowser>> availableBrowsers() async {
    if (Platform.isAndroid) {
      final raw = await _channel.invokeListMethod<dynamic>(
        'listLoginBrowsers',
      );
      return (raw ?? const [])
          .whereType<Map>()
          .map((entry) {
            final id = entry['id'];
            final name = entry['name'];
            if (id is! String || name is! String || id.isEmpty) {
              return null;
            }
            return LoginBrowser(id: id, name: name);
          })
          .whereType<LoginBrowser>()
          .toList();
    }

    if (Platform.isIOS) {
      final browsers = <LoginBrowser>[_default];
      for (final entry in const [
        (id: 'ios:chrome', name: 'Google Chrome', scheme: 'googlechromes'),
        (id: 'ios:firefox', name: 'Firefox', scheme: 'firefox'),
        (id: 'ios:edge', name: 'Microsoft Edge', scheme: 'microsoft-edge-https'),
      ]) {
        if (await canLaunchUrl(Uri.parse(entry.scheme + '://open-url'))) {
          browsers.add(LoginBrowser(id: entry.id, name: entry.name));
        }
      }
      return browsers;
    }

    if (Platform.isLinux && _inFlatpak) {
      // Browser discovery via PATH/flatpak inside the sandbox only sees
      // sandboxed tools. The host application chooser knows the actual
      // installed browsers and retains their existing OAuth sessions.
      return [_portalChooser];
    }

    final browsers = <LoginBrowser>[_default];
    if (Platform.isLinux) {
      for (final entry in _linuxBrowsers) {
        if (await _hasCommand(entry.command)) {
          browsers.add(LoginBrowser(
            id: 'linux:' + entry.command,
            name: entry.name,
            executable: entry.command,
          ));
        }
      }
      if (await _hasCommand('flatpak')) {
        try {
          final result = await Process.run(
            'flatpak',
            ['list', '--app', '--columns=application'],
          );
          if (result.exitCode == 0) {
            final installed = (result.stdout as String)
                .split('\n')
                .map((s) => s.trim())
                .toSet();
            for (final entry in _flatpakBrowsers) {
              if (!installed.contains(entry.appId)) continue;
              browsers.add(LoginBrowser(
                id: 'flatpak:' + entry.appId,
                name: entry.name + ' (Flatpak)',
                executable: 'flatpak',
                arguments: ['run', entry.appId],
              ));
            }
          }
        } on ProcessException {
          // The system default browser remains available.
        }
      }
    } else if (Platform.isMacOS) {
      const names = [
        'Safari',
        'Google Chrome',
        'Firefox',
        'Firefox Developer Edition',
        'Brave Browser',
        'Microsoft Edge',
        'Chromium',
        'Vivaldi',
        'Opera',
        'Arc',
      ];
      final home = Platform.environment['HOME'] ?? '';
      for (final name in names) {
        for (final root in [
          '/Applications',
          if (home.isNotEmpty) home + '/Applications',
        ]) {
          final app = root + '/' + name + '.app';
          if (!await Directory(app).exists()) continue;
          browsers.add(LoginBrowser(
            id: 'mac:' + app,
            name: name,
            executable: '/usr/bin/open',
            arguments: ['-a', app],
          ));
          break;
        }
      }
    } else if (Platform.isWindows) {
      // Browser binaries are normally not in PATH on Windows.
      final programFiles = [
        Platform.environment['PROGRAMFILES'],
        Platform.environment['PROGRAMFILES(X86)'],
        Platform.environment['LOCALAPPDATA'],
      ].whereType<String>().toSet();
      const paths = [
        (name: 'Google Chrome', relative: r'Google\Chrome\Application\chrome.exe'),
        (name: 'Firefox', relative: r'Mozilla Firefox\firefox.exe'),
        (name: 'Microsoft Edge', relative: r'Microsoft\Edge\Application\msedge.exe'),
        (name: 'Brave', relative: r'BraveSoftware\Brave-Browser\Application\brave.exe'),
        (name: 'Vivaldi', relative: r'Vivaldi\Application\vivaldi.exe'),
        (name: 'Opera', relative: r'Programs\Opera\opera.exe'),
      ];
      for (final entry in paths) {
        for (final root in programFiles) {
          final file = root + '\\' + entry.relative;
          if (!await File(file).exists()) continue;
          browsers.add(LoginBrowser(
            id: 'win:' + file,
            name: entry.name,
            executable: file,
          ));
          break;
        }
      }
    }
    return browsers;
  }

  Future<bool> open(LoginBrowser browser, Uri authorizationUrl) async {
    if (!isAuthorizationUrl(authorizationUrl)) return false;
    try {
      if (browser.id == _portalChooser.id && Platform.isLinux && _inFlatpak) {
        return _openWithPortalChooser(authorizationUrl);
      }
      if (browser.id == 'default') {
        return launchUrl(
          authorizationUrl,
          mode: LaunchMode.externalApplication,
        );
      }
      if (Platform.isAndroid) {
        return await _channel.invokeMethod<bool>(
              'launchLoginBrowser',
              {'id': browser.id, 'url': authorizationUrl.toString()},
            ) ??
            false;
      }
      if (Platform.isIOS) {
        late final Uri target;
        switch (browser.id) {
          case 'ios:chrome':
            target = authorizationUrl.replace(scheme: 'googlechromes');
            break;
          case 'ios:firefox':
            target = Uri.parse('firefox://open-url').replace(
              queryParameters: {'url': authorizationUrl.toString()},
            );
            break;
          case 'ios:edge':
            target = authorizationUrl.replace(scheme: 'microsoft-edge-https');
            break;
          default:
            return false;
        }
        return launchUrl(target, mode: LaunchMode.externalApplication);
      }
      if (browser.executable == null) return false;
      await Process.start(
        browser.executable!,
        [...browser.arguments, authorizationUrl.toString()],
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// XDG Desktop Portal OpenURI v3+ with ask=true. This delegates selection
  /// to the host's trusted app chooser without sandbox escape permissions.
  /// GDBus returns a Request handle immediately; the eventual user choice,
  /// including cancellation, is handled asynchronously by the portal.
  Future<bool> _openWithPortalChooser(Uri uri) async {
    try {
      final result = await Process.run(
        'gdbus',
        [
          'call',
          '--session',
          '--dest',
          'org.freedesktop.portal.Desktop',
          '--object-path',
          '/org/freedesktop/portal/desktop',
          '--method',
          'org.freedesktop.portal.OpenURI.OpenURI',
          '',
          uri.toString(),
          "{'ask': <true>}",
        ],
      );
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  Future<bool> _hasCommand(String command) async {
    try {
      final result = await Process.run('which', [command]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}
