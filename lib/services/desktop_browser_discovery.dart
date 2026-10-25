import 'dart:io';
import 'dart:typed_data';

import 'xdg_browser_discovery.dart';

/// A browser chosen explicitly by the user. Never reads or copies its cookies.
class LoginBrowser {
  const LoginBrowser({
    required this.id,
    required this.name,
    this.executable,
    this.arguments = const [],
    this.iconBytes,
  });

  final String id;
  final String name;
  final String? executable;
  final List<String> arguments;

  /// Android 系统安装的真实应用图标（PNG）；桌面/iOS 可为空。
  final Uint8List? iconBytes;
}

/// 桌面发现逻辑独立于 Flutter，可在三个系统运行文件与进程行为测试。
class DesktopBrowserDiscovery {
  DesktopBrowserDiscovery({
    required this.platform,
    required this.environment,
    required this.inFlatpak,
    Future<String?> Function(String)? findCommand,
    Future<String> Function(String)? resolveExecutable,
    Future<bool> Function(String)? fileExists,
    Future<bool> Function(String)? directoryExists,
    Future<ProcessResult> Function(String, List<String>)? runProcess,
  }) : resolveExecutable =
           resolveExecutable ?? ((p) => File(p).resolveSymbolicLinks()),
       fileExists = fileExists ?? ((p) => File(p).exists()),
       directoryExists = directoryExists ?? ((p) => Directory(p).exists()),
       runProcess = runProcess ?? ((exe, args) => Process.run(exe, args)) {
    this.findCommand = findCommand ?? _findCommandPath;
  }

  final String platform;
  final Map<String, String> environment;
  final bool inFlatpak;
  late final Future<String?> Function(String) findCommand;
  final Future<String> Function(String) resolveExecutable;
  final Future<bool> Function(String) fileExists;
  final Future<bool> Function(String) directoryExists;
  final Future<ProcessResult> Function(String, List<String>) runProcess;
  static const _default = LoginBrowser(id: 'default', name: '系统默认浏览器');
  static const _portalChooser = LoginBrowser(
    id: 'portal:chooser',
    name: '选择系统已安装的浏览器',
  );

  static const linuxBrowserCommands = <({String name, String command})>[
    (name: 'Firefox', command: 'firefox'),
    (name: 'Firefox ESR', command: 'firefox-esr'),
    (name: 'Firefox Beta', command: 'firefox-beta'),
    (name: 'Firefox Developer Edition', command: 'firefox-aurora'),
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
    (name: 'Google Chrome Dev', command: 'google-chrome-dev'),
    (name: 'Google Chrome Canary', command: 'google-chrome-canary'),
    (name: 'Brave', command: 'brave-browser'),
    (name: 'Brave Beta', command: 'brave-browser-beta'),
    (name: 'Brave Nightly', command: 'brave-browser-nightly'),
    (name: 'Microsoft Edge', command: 'microsoft-edge-stable'),
    (name: 'Microsoft Edge', command: 'microsoft-edge'),
    (name: 'Microsoft Edge Beta', command: 'microsoft-edge-beta'),
    (name: 'Microsoft Edge Dev', command: 'microsoft-edge-dev'),
    (name: 'Microsoft Edge Canary', command: 'microsoft-edge-canary'),
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
    'Safari',
    'Safari Technology Preview',
    'Google Chrome',
    'Google Chrome Beta',
    'Google Chrome Dev',
    'Google Chrome Canary',
    'Firefox',
    'Firefox Beta',
    'Firefox Developer Edition',
    'Firefox Nightly',
    'Brave Browser',
    'Microsoft Edge',
    'Microsoft Edge Beta',
    'Microsoft Edge Dev',
    'Microsoft Edge Canary',
    'Chromium',
    'Vivaldi',
    'Opera',
    'Arc',
  ];

  /// Windows 中预览通道通常不在 PATH，必须查找专属安装路径。
  static const windowsBrowserInstallPaths = <({String name, String relative})>[
    (name: 'Google Chrome', relative: r'Google\Chrome\Application\chrome.exe'),
    (
      name: 'Google Chrome Beta',
      relative: r'Google\Chrome Beta\Application\chrome.exe',
    ),
    (
      name: 'Google Chrome Dev',
      relative: r'Google\Chrome Dev\Application\chrome.exe',
    ),
    (
      name: 'Google Chrome Canary',
      relative: r'Google\Chrome SxS\Application\chrome.exe',
    ),
    (name: 'Firefox', relative: r'Mozilla Firefox\firefox.exe'),
    (name: 'Firefox Beta', relative: r'Mozilla Firefox Beta\firefox.exe'),
    (name: 'Firefox Beta', relative: r'Firefox Beta\firefox.exe'),
    (
      name: 'Firefox Developer Edition',
      relative: r'Firefox Developer Edition\firefox.exe',
    ),
    (name: 'Firefox Nightly', relative: r'Nightly\firefox.exe'),
    (name: 'Firefox Nightly', relative: r'Firefox Nightly\firefox.exe'),
    (name: 'Firefox ESR', relative: r'Mozilla Firefox ESR\firefox.exe'),
    (
      name: 'Microsoft Edge',
      relative: r'Microsoft\Edge\Application\msedge.exe',
    ),
    (
      name: 'Microsoft Edge Beta',
      relative: r'Microsoft\Edge Beta\Application\msedge.exe',
    ),
    (
      name: 'Microsoft Edge Dev',
      relative: r'Microsoft\Edge Dev\Application\msedge.exe',
    ),
    (
      name: 'Microsoft Edge Canary',
      relative: r'Microsoft\Edge SxS\Application\msedge.exe',
    ),
    (
      name: 'Brave',
      relative: r'BraveSoftware\Brave-Browser\Application\brave.exe',
    ),
    (
      name: 'Brave Beta',
      relative: r'BraveSoftware\Brave-Browser-Beta\Application\brave.exe',
    ),
    (
      name: 'Brave Nightly',
      relative: r'BraveSoftware\Brave-Browser-Nightly\Application\brave.exe',
    ),
    (name: 'Vivaldi', relative: r'Vivaldi\Application\vivaldi.exe'),
    (name: 'Opera', relative: r'Programs\Opera\opera.exe'),
  ];

  Future<List<LoginBrowser>> availableBrowsers() async {
    if (platform == 'linux' && inFlatpak) {
      // Browser discovery via PATH/flatpak inside the sandbox only sees
      // sandboxed tools. The host application chooser knows the actual
      // installed browsers and retains their existing OAuth sessions.
      return [_portalChooser];
    }

    final browsers = <LoginBrowser>[_default];
    if (platform == 'linux') {
      final seenExecutables = <String>{};
      final gio = await findCommand('gio');
      if (gio != null) {
        final entries = await XdgBrowserDiscovery(
          environment: environment,
          findCommand: findCommand,
        ).discover();
        for (final entry in entries) {
          browsers.add(
            LoginBrowser(
              id: 'xdg:${entry.id}',
              name: entry.name,
              executable: gio,
              arguments: ['launch', entry.path],
            ),
          );
          // 不合并不同 desktop ID 的 Profile；只抑制同入口的 PATH 回退项。
          final command = entry.command;
          if (command != null) {
            final path = command.startsWith('/')
                ? command
                : await findCommand(command);
            if (path != null) {
              try {
                seenExecutables.add(await resolveExecutable(path));
              } on FileSystemException {
                seenExecutables.add(path);
              }
            }
          }
        }
      }
      for (final entry in linuxBrowserCommands) {
        final commandPath = await findCommand(entry.command);
        if (commandPath != null) {
          String identity;
          try {
            identity = await resolveExecutable(commandPath);
          } on FileSystemException {
            identity = commandPath;
          }
          if (!seenExecutables.add(identity)) continue;
          browsers.add(
            LoginBrowser(
              id: 'linux:${entry.command}',
              name: entry.name,
              executable: commandPath,
            ),
          );
        }
      }
      final flatpakPath = await findCommand('flatpak');
      if (flatpakPath != null) {
        try {
          final result = await runProcess(flatpakPath, [
            'list',
            '--app',
            '--columns=application',
          ]);
          if (result.exitCode == 0) {
            final installed = (result.stdout as String)
                .split('\n')
                .map((s) => s.trim())
                .toSet();
            for (final entry in _flatpakBrowsers) {
              if (!installed.contains(entry.appId) ||
                  browsers.any(
                    (browser) => browser.id == 'xdg:${entry.appId}.desktop',
                  )) {
                continue;
              }
              browsers.add(
                LoginBrowser(
                  id: 'flatpak:${entry.appId}',
                  name: '${entry.name} (Flatpak)',
                  executable: flatpakPath,
                  arguments: ['run', entry.appId],
                ),
              );
            }
          }
        } on ProcessException {
          // The system default browser remains available.
        }
      }
    } else if (platform == 'macos') {
      final home = environment['HOME'] ?? '';
      for (final name in macBrowserAppNames) {
        for (final root in [
          '/Applications',
          if (home.isNotEmpty) '$home/Applications',
        ]) {
          final app = '$root/$name.app';
          if (!await directoryExists(app)) continue;
          browsers.add(
            LoginBrowser(
              id: 'mac:$app',
              name: name,
              executable: '/usr/bin/open',
              arguments: ['-a', app],
            ),
          );
          break;
        }
      }
    } else if (platform == 'windows') {
      // Browser binaries are normally not in PATH on Windows.
      final programFiles = [
        environment['PROGRAMFILES'],
        environment['PROGRAMFILES(X86)'],
        environment['PROGRAMW6432'],
        environment['LOCALAPPDATA'],
      ].whereType<String>().toSet();
      final seenPaths = <String>{};
      for (final entry in windowsBrowserInstallPaths) {
        for (final root in programFiles) {
          final file = '$root\\${entry.relative}';
          if (!await fileExists(file)) continue;
          // PROGRAMFILES 与 PROGRAMW6432 经常指向同一目录。
          if (!seenPaths.add(file.toLowerCase())) continue;
          browsers.add(
            LoginBrowser(id: 'win:$file', name: entry.name, executable: file),
          );
          break;
        }
      }
    }
    return browsers;
  }

  Future<String?> _findCommandPath(String command) async {
    for (final root in (environment['PATH'] ?? '').split(':')) {
      // 空段代表当前工作目录，保持 PATH 的正常语义。
      final file = File('${root.isEmpty ? '.' : root}/$command');
      try {
        final stat = await file.stat();
        if (stat.type == FileSystemEntityType.file && stat.mode & 0x49 != 0) {
          return file.absolute.path;
        }
      } on FileSystemException {
        // 损坏的链接或不可访问的目录不应阻断其他浏览器发现。
      }
    }
    return null;
  }
}
