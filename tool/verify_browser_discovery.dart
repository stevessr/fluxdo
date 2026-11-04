import 'dart:io';

import 'verify_xdg_browser_discovery.dart' as xdg;

import '../lib/services/desktop_browser_discovery.dart';

int checks = 0;
void check(bool condition, String message) {
  if (!condition) throw StateError(message);
  checks++;
}

Future<void> main() async {
  await xdg.main();
  // 这些是实际发现函数的行为测试，不要求宿主系统安装浏览器。
  final calls = <String>[];
  DesktopBrowserDiscovery fixture(
    String platform, {
    Map<String, String> environment = const {},
    Map<String, String> commands = const {},
    Map<String, String> identities = const {},
    Set<String> files = const {},
    Set<String> directories = const {},
    String flatpaks = '',
    bool flatpak = false,
    bool failFlatpak = false,
  }) => DesktopBrowserDiscovery(
    platform: platform,
    environment: environment,
    inFlatpak: flatpak,
    findCommand: (command) async {
      calls.add('find:$command');
      return commands[command];
    },
    resolveExecutable: (path) async {
      if (identities[path] == 'broken') throw FileSystemException('损坏链接');
      return identities[path] ?? path;
    },
    fileExists: (path) async => files.contains(path),
    directoryExists: (path) async => directories.contains(path),
    runProcess: (exe, args) async {
      calls.add('$exe ${args.join(' ')}');
      if (failFlatpak) throw ProcessException(exe, args);
      return ProcessResult(0, 0, flatpaks, '');
    },
  );

  var browsers = await fixture(
    'linux',
    commands: {
      'google-chrome-stable': '/opt/chrome stable',
      'google-chrome': '/usr/bin/google-chrome',
      'google-chrome-beta': '/opt/chrome beta',
      'firefox-nightly': '/opt/firefox-nightly',
    },
    identities: {
      '/opt/chrome stable': '/opt/chrome/chrome',
      '/usr/bin/google-chrome': '/opt/chrome/chrome',
    },
  ).availableBrowsers();
  check(browsers.length == 4, 'Linux 稳定版别名去重，预览版仍独立');
  check(browsers[1].id == 'linux:firefox-nightly', 'Linux 通道 ID 保持稳定');
  check(browsers.last.executable == '/opt/chrome beta', '保留发现时的绝对入口，支持空格');
  check(browsers.map((b) => b.id).toSet().length == browsers.length, 'ID 唯一');

  browsers = await fixture(
    'linux',
    commands: {'firefox': '/broken'},
    identities: {'/broken': 'broken'},
  ).availableBrowsers();
  check(browsers.last.executable == '/broken', '符号链接解析失败时保留候选入口');

  calls.clear();
  browsers = await fixture('linux', flatpak: true).availableBrowsers();
  check(browsers.single.id == 'portal:chooser', 'Flatpak 沙箱只展示宿主选择器');
  check(calls.isEmpty, 'Flatpak 沙箱不探测或执行宿主命令');

  browsers = await fixture(
    'linux',
    commands: {'flatpak': '/usr/bin/flatpak'},
    flatpaks: 'org.mozilla.firefox\ncom.google.Chrome\nunknown.app\n',
  ).availableBrowsers();
  check(browsers.length == 3, 'Flatpak 列表仅包含已知且已安装的浏览器');
  final firefox = browsers.firstWhere(
    (b) => b.id == 'flatpak:org.mozilla.firefox',
  );
  check(
    firefox.arguments.join('|') == 'run|org.mozilla.firefox',
    'Flatpak 启动参数',
  );
  browsers = await fixture(
    'linux',
    commands: {'flatpak': '/usr/bin/flatpak'},
    failFlatpak: true,
  ).availableBrowsers();
  check(browsers.single.id == 'default', 'Flatpak 命令失败仍保留默认浏览器');

  browsers = await fixture(
    'macos',
    environment: {'HOME': '/Users/Test User'},
    directories: {
      '/Applications/Google Chrome Beta.app',
      '/Users/Test User/Applications/Google Chrome Beta.app',
      '/Users/Test User/Applications/Firefox Nightly.app',
    },
  ).availableBrowsers();
  check(browsers.length == 3, 'macOS 系统应用优先并回退用户应用目录');
  check(
    browsers[1].arguments.join('|') ==
        '-a|/Applications/Google Chrome Beta.app',
    'macOS 空格路径保持单个参数',
  );
  check(
    browsers[2].id == 'mac:/Users/Test User/Applications/Firefox Nightly.app',
    'macOS 用户目录通道',
  );

  browsers = await fixture(
    'windows',
    environment: {
      'PROGRAMFILES': r'C:\Program Files',
      'PROGRAMFILES(X86)': r'C:\Program Files (x86)',
      'PROGRAMW6432': r'C:\PROGRAM FILES',
      'LOCALAPPDATA': r'C:\Users\Test User\AppData\Local',
    },
    files: {
      r'C:\Program Files\Google\Chrome Beta\Application\chrome.exe',
      r'C:\PROGRAM FILES\Google\Chrome Beta\Application\chrome.exe',
      r'C:\Users\Test User\AppData\Local\Google\Chrome SxS\Application\chrome.exe',
      r'C:\Program Files (x86)\Microsoft\Edge Dev\Application\msedge.exe',
      r'C:\Program Files\Firefox Nightly\firefox.exe',
    },
  ).availableBrowsers();
  check(browsers.length == 5, 'Windows 系统、x86、用户目录与重复根目录');
  check(
    browsers.any(
      (b) =>
          b.name == 'Google Chrome Canary' &&
          b.executable!.contains('Chrome SxS'),
    ),
    'Windows 用户安装的 Canary',
  );
  check(
    browsers.any((b) => b.name == 'Firefox Nightly'),
    'Windows Nightly 备用目录',
  );

  for (final platform in ['linux', 'macos', 'windows']) {
    browsers = await fixture(platform).availableBrowsers();
    check(browsers.single.id == 'default', '$platform 无浏览器时保留默认入口');
  }

  // 使用宿主真实文件系统，验证 PATH 查找不依赖 which，且忽略非可执行文件。
  if (Platform.isLinux) {
    final temp = await Directory.systemTemp.createTemp('fluxdo-browser-');
    try {
      final stable = File('${temp.path}/google-chrome-stable');
      await stable.writeAsString('#!/bin/sh\nexit 0\n');
      final beta = File('${temp.path}/google-chrome-beta');
      await beta.writeAsString(r'''#!/bin/sh
printf '%s\n' "$@"
''');
      await Process.run('chmod', ['+x', stable.path, beta.path]);
      await Link('${temp.path}/google-chrome').create(stable.path);
      await File('${temp.path}/firefox').writeAsString('不可执行');
      browsers = await DesktopBrowserDiscovery(
        platform: 'linux',
        environment: {'PATH': temp.path},
        inFlatpak: false,
      ).availableBrowsers();
      check(browsers.length == 3, '真实 Linux PATH：忽略非可执行文件并去重链接');
      check(browsers.last.executable == beta.path, '真实 Linux PATH：绝对路径');
      const url =
          'https://linux.do/user-api-key/new?nonce=a%20b&scopes=read,write';
      final result = await Process.run(browsers.last.executable!, [url]);
      check(result.stdout == '$url\n', '真实 Linux URL 查询参数作为单个参数原样传递');
      check(result.exitCode == 0, '真实 Linux 进程入口可启动');
    } finally {
      await temp.delete(recursive: true);
    }
  }
  if (Platform.isMacOS || Platform.isWindows) {
    final temp = await Directory.systemTemp.createTemp('fluxdo-browser-');
    try {
      if (Platform.isMacOS) {
        final app = Directory('${temp.path}/Applications/Firefox Nightly.app');
        await app.create(recursive: true);
        browsers = await DesktopBrowserDiscovery(
          platform: 'macos',
          environment: {'HOME': temp.path},
          inFlatpak: false,
          directoryExists: (path) async =>
              path.startsWith(temp.path) && await Directory(path).exists(),
        ).availableBrowsers();
        check(browsers.length == 2, '真实 macOS 用户应用包发现');
        check(browsers.last.arguments.last == app.path, '真实 macOS 应用包参数');
      } else {
        final exe = File(
          '${temp.path}\\Google\\Chrome SxS\\Application\\chrome.exe',
        );
        await exe.parent.create(recursive: true);
        await exe.writeAsString('仅供发现测试');
        browsers = await DesktopBrowserDiscovery(
          platform: 'windows',
          environment: {'LOCALAPPDATA': temp.path},
          inFlatpak: false,
        ).availableBrowsers();
        check(browsers.length == 2, '真实 Windows 用户安装文件发现');
        check(browsers.last.executable == exe.path, '真实 Windows Canary 入口');
      }
    } finally {
      await temp.delete(recursive: true);
    }
  }
  stdout.writeln(
    'PASS: $checks browser discovery behavioral checks (${Platform.operatingSystem})',
  );
}
