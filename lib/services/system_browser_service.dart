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

  static const linuxBrowserCommands = <({String name, String command})>[
    (name: 'Firefox', command: 'firefox'),
    (name: 'Firefox ESR', command: 'firefox-esr'),
    (name: 'Firefox Beta', command: 'firefox-beta'),
    (name: 'Firefox Developer Edition', command: 'firefox-developer-edition'),
    (name: 'Firefox Nightly', command: 'firefox-nightly'),
    (name: 'Firefox Nightly', command: 'firefox-trunk'),
    (name: 'LibreWolf', command: 'librewolf'),
    (name: 'Zen Browser', command: 'zen-browser'),
    (name: 'Floorp', command: 'floorp'),
    (name: 'Waterfox', command: 'waterfox'),
    (name: 'Chromium', command: 'chromium'),
    (name: 'Chromium', command: 'chromium-browser'),
    (name: 'Google Chrome', command: 'google-chrome-stable'),
    (name: 'Google Chrome', command: 'google-chrome'),
    (name: 'Google Chrome Beta', command: 'google-chrome-beta'),
    (name: 'Google Chrome Dev', command: 'google-chrome-unstable'),
    (name: 'Google Chrome Canary', command: 'google-chrome-canary'),
    (name: 'Brave', command: 'brave-browser'),
    (name: 'Brave Beta', command: 'brave-browser-beta'),
    (name: 'Brave Nightly', command: 'brave-browser-nightly'),
    (name: 'Microsoft Edge', command: 'microsoft-edge-stable'),
    (name: 'Microsoft Edge', command: 'microsoft-edge'),
    (name: 'Microsoft Edge Beta', command: 'microsoft-edge-beta'),
    (name: 'Microsoft Edge Dev', command: 'microsoft-edge-dev'),
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

  /// 浏览器的不同预览通道具有独立启动入口及登录 Profile。
  static const macBrowserAppNames = <String>[
    'Safari', 'Safari Technology Preview',
    'Google Chrome', 'Google Chrome Beta', 'Google Chrome Dev',
    'Google Chrome Canary', 'Firefox', 'Firefox Beta',
    'Firefox Developer Edition', 'Firefox Nightly', 'Brave Browser',
    'Microsoft Edge', 'Microsoft Edge Beta', 'Microsoft Edge Dev',
    'Microsoft Edge Canary', 'Chromium', 'Vivaldi', 'Opera', 'Arc',
  ];

  /// Windows 中预览通道通常不在 PATH，必须查找专属安装路径。
  static const windowsBrowserInstallPaths = <({String name, String relative})>[
    (name: 'Google Chrome', relative: r'Google\Chrome\Application\chrome.exe'),
    (name: 'Google Chrome Beta', relative: r'Google\Chrome Beta\Application\chrome.exe'),
    (name: 'Google Chrome Dev', relative: r'Google\Chrome Dev\Application\chrome.exe'),
    (name: 'Google Chrome Canary', relative: r'Google\Chrome SxS\Application\chrome.exe'),
    (name: 'Firefox', relative: r'Mozilla Firefox\firefox.exe'),
    (name: 'Firefox Beta', relative: r'Mozilla Firefox Beta\firefox.exe'),
    (name: 'Firefox Beta', relative: r'Firefox Beta\firefox.exe'),
    (name: 'Firefox Developer Edition', relative: r'Firefox Developer Edition\firefox.exe'),
    (name: 'Firefox Nightly', relative: r'Nightly\firefox.exe'),
    (name: 'Firefox ESR', relative: r'Mozilla Firefox ESR\firefox.exe'),
    (name: 'Microsoft Edge', relative: r'Microsoft\Edge\Application\msedge.exe'),
    (name: 'Microsoft Edge Beta', relative: r'Microsoft\Edge Beta\Application\msedge.exe'),
    (name: 'Microsoft Edge Dev', relative: r'Microsoft\Edge Dev\Application\msedge.exe'),
    (name: 'Microsoft Edge Canary', relative: r'Microsoft\Edge SxS\Application\msedge.exe'),
    (name: 'Brave', relative: r'BraveSoftware\Brave-Browser\Application\brave.exe'),
    (name: 'Brave Beta', relative: r'BraveSoftware\Brave-Browser-Beta\Application\brave.exe'),
    (name: 'Brave Nightly', relative: r'BraveSoftware\Brave-Browser-Nightly\Application\brave.exe'),
    (name: 'Vivaldi', relative: r'Vivaldi\Application\vivaldi.exe'),
    (name: 'Opera', relative: r'Programs\Opera\opera.exe'),
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
      final seenExecutables = <String>{};
      for (final entry in linuxBrowserCommands) {
        final commandPath = await _findCommandPath(entry.command);
        if (commandPath != null) {
          String identity;
          try {
            identity = await File(commandPath).resolveSymbolicLinks();
          } on FileSystemException {
            identity = commandPath;
          }
          if (!seenExecutables.add(identity)) continue;
          browsers.add(LoginBrowser(
            id: 'linux:' + entry.command,
            name: entry.name,
            executable: entry.command,
          ));
        }
      }
      if (await _findCommandPath('flatpak') != null) {
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

      final home = Platform.environment['HOME'] ?? '';
      for (final name in macBrowserAppNames) {
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
        Platform.environment['PROGRAMW6432'],
        Platform.environment['LOCALAPPDATA'],
      ].whereType<String>().toSet();
      for (final entry in windowsBrowserInstallPaths) {
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

  Future<String?> _findCommandPath(String command) async {
    try {
      final result = await Process.run('which', [command]);
      if (result.exitCode != 0) return null;
      final path = (result.stdout as String).trim().split('\n').first;
      return path.isEmpty ? null : path;
    } on ProcessException {
      return null;
    }
  }
}
