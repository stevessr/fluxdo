import 'dart:io';

import '../lib/services/desktop_browser_discovery.dart';
import '../lib/services/xdg_browser_discovery.dart';
import '../lib/services/xdg_browser_icon_loader.dart';

Future<void> main() async {
  if (!Platform.isLinux) return;
  var checks = 0;
  void check(bool value, String message) {
    if (!value) throw StateError(message);
    checks++;
  }

  final temp = await Directory.systemTemp.createTemp('fluxdo-xdg-');
  try {
    final user = '${temp.path}/user';
    final system = '${temp.path}/system';
    final executable = File('${temp.path}/browser with spaces');
    await executable.writeAsString(r'''#!/bin/sh
printf '%s\n' "$@" > "$FLUXDO_TEST_ARGUMENTS"
''');
    await Process.run('chmod', ['+x', executable.path]);
    final env = <String, String>{
      'HOME': temp.path,
      'XDG_DATA_HOME': user,
      'XDG_DATA_DIRS': '$system:relative:',
      'XDG_CURRENT_DESKTOP': 'niri:GNOME',
      'LANG': 'en_US.UTF-8',
      'LC_MESSAGES': 'zh_CN.UTF-8',
    };
    Future<String?> find(String command) async => switch (command) {
      'gio' => '/usr/bin/gio',
      'custom-browser' || 'google-chrome-stable' => executable.path,
      _ => null,
    };
    Future<void> entry(String root, String id, String content) async {
      final file = File('$root/applications/$id');
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    }

    const common = '''[Desktop Entry]
Type=Application
Name=Custom Browser
Name[zh_CN]=自定义浏览器
Name[zh]=浏览器
Exec=custom-browser %U
MimeType=x-scheme-handler/http;x-scheme-handler/https;
Categories=Network;WebBrowser;
Icon=custom-icon
''';
    final iconFile = File('$user/icons/hicolor/64x64/apps/custom-icon.png');
    await iconFile.parent.create(recursive: true);
    await iconFile.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10]);
    await entry(system, 'browser.desktop', common);
    await entry(
      user,
      'browser.desktop',
      common.replaceFirst('自定义浏览器', '用户浏览器'),
    );
    await entry(system, 'hidden.desktop', common);
    await entry(system, 'chatgpt.desktop', '''[Desktop Entry]
Type=Application
Name=ChatGPT
Exec=custom-browser %U
MimeType=x-scheme-handler/http;x-scheme-handler/https;
Categories=Network;
''');
    await entry(user, 'hidden.desktop', '[Desktop Entry]\nHidden=true\n');
    await entry(system, 'override.desktop', common);
    await entry(
      user,
      'override.desktop',
      common.replaceFirst('Type=Application', 'Type=Link'),
    );
    await entry(
      system,
      'https-only.desktop',
      common.replaceFirst('x-scheme-handler/http;', ''),
    );
    await entry(system, 'allowed.desktop', '${common}OnlyShowIn=niri;\n');
    await entry(system, 'terminal.desktop', '${common}Terminal=true\n');
    await entry(system, 'wrong-desktop.desktop', '${common}OnlyShowIn=KDE;\n');
    await entry(system, 'not-show.desktop', '${common}NotShowIn=niri;\n');
    await entry(system, 'missing.desktop', '${common}TryExec=not-installed\n');
    await entry(
      system,
      'no-exec.desktop',
      common.replaceFirst('Exec=custom-browser %U', 'Exec=not-installed %U'),
    );
    await entry(
      system,
      'org.example.DBus.desktop',
      '${common}DBusActivatable=true\nExec=not-installed\n',
    );
    await entry(system, 'nodisplay.desktop', '${common}NoDisplay=true\n');
    await entry(
      system,
      'nested/profile.desktop',
      common.replaceFirst(
        'Exec=custom-browser %U',
        'Exec=custom-browser --profile another %U',
      ),
    );
    await entry(system, 'fluxdo.desktop', common);
    await entry(system, 'com.github.lingyan000.fluxdo.desktop', common);
    await entry(
      system,
      'quoted.desktop',
      common.replaceFirst(
        'Exec=custom-browser %U',
        'Exec="${executable.path}" --label "hello world" %U',
      ),
    );
    await entry(
      system,
      'actions.desktop',
      '$common\n[Desktop Action Private]\nName=不能覆盖主入口\nExec=not-installed\n',
    );
    await File('$system/applications/bad-utf8.desktop')
        .writeAsBytes([255, 254, 253]);

    final entries = await XdgBrowserDiscovery(
      environment: env,
      findCommand: find,
    ).discover();
    final ids = entries.map((e) => e.id).toSet();
    check(entries.length == 7, '只发现符合条件的七个 XDG 入口：$ids');
    final browser = entries.singleWhere((e) => e.id == 'browser.desktop');
    check(browser.path == '$user/applications/browser.desktop', '用户覆盖系统同 ID');
    check(browser.name == '用户浏览器', '优先 LC_MESSAGES 本地化名称');
    check(browser.icon == 'custom-icon', '从 XDG 入口读取 Icon 字段');
    check(!ids.contains('chatgpt.desktop'), 'URL 处理器不等同于浏览器');
    check(!ids.contains('hidden.desktop'), '用户 Hidden 墓碑屏蔽系统入口');
    check(!ids.contains('override.desktop'), '无效用户覆盖不回退系统');
    check(!ids.contains('https-only.desktop'), '要求 HTTP 与 HTTPS');
    check(!ids.contains('terminal.desktop'), '排除终端应用');
    check(
      !ids.contains('wrong-desktop.desktop') &&
          !ids.contains('not-show.desktop'),
      '桌面环境限制',
    );
    check(
      !ids.contains('missing.desktop') && !ids.contains('no-exec.desktop'),
      '排除未安装入口',
    );
    check(ids.contains('org.example.DBus.desktop'), '保留可 D-Bus 激活入口');
    check(ids.contains('nodisplay.desktop'), 'NoDisplay 仅隐藏菜单，不隐藏合法 MIME 处理器');
    check(ids.contains('nested-profile.desktop'), '子目录转换为 desktop ID');
    check(
      entries.singleWhere((e) => e.id == 'quoted.desktop').command ==
          executable.path,
      '带空格的双引号入口',
    );
    check(
      entries.singleWhere((e) => e.id == 'actions.desktop').name == '自定义浏览器',
      '动作组不污染主入口',
    );
    check(
      !ids.contains('fluxdo.desktop') &&
          !ids.contains('com.github.lingyan000.fluxdo.desktop'),
      '排除客户端自身',
    );

    final browsers = await DesktopBrowserDiscovery(
      platform: 'linux',
      environment: env,
      inFlatpak: false,
      findCommand: find,
    ).availableBrowsers();
    check(
      browsers.where((b) => b.id.startsWith('xdg:')).length == 5,
      'XDG 完全相同的启动指令去重，不合并不同 Profile',
    );
    check(
      browsers.firstWhere((b) => b.id == 'xdg:browser.desktop').iconBytes?.length == 8,
      '获取 XDG 图标 PNG 并随浏览器结果返回',
    );
    check(
      !browsers.any((b) => b.id == 'linux:google-chrome-stable'),
      'XDG 与 PATH 相同入口不重复',
    );
    final selected = browsers.singleWhere((b) => b.id == 'xdg:quoted.desktop');
    check(
      selected.arguments.join('|') ==
          'launch|$system/applications/quoted.desktop',
      'GIO 接收所选文件，不使用默认处理器',
    );
    check(selected.executable == '/usr/bin/gio', '使用发现时的 GIO 绝对入口');
    check(
      browsers.any((b) => b.id == 'xdg:nested-profile.desktop'),
      '不同 Profile desktop ID 保留',
    );

    final noGio = await DesktopBrowserDiscovery(
      platform: 'linux',
      environment: env,
      inFlatpak: false,
      findCommand: (command) async => command == 'gio' ? null : find(command),
    ).availableBrowsers();
    check(
      noGio.any((b) => b.id == 'linux:google-chrome-stable'),
      '没有 GIO 时 PATH 回退仍可用',
    );
    check(!noGio.any((b) => b.id.startsWith('xdg:')), '没有 GIO 不展示不可启动 XDG 项');

    final svgFile = File('$user/browser.svg');
    await svgFile.writeAsString('<svg xmlns="http://www.w3.org/2000/svg"></svg>');
    final icons = XdgBrowserIconLoader(environment: env);
    final svgIcon = await icons.load(svgFile.path);
    check(svgIcon?.isSvg == true, '支持 Icon 绝对 SVG 路径');
    check((await icons.load('../private')) == null, '拒绝相对路径穿越');

    final localized = await XdgBrowserDiscovery(
      environment: {...env, 'LC_ALL': 'zh_TW.UTF-8'},
      findCommand: find,
    ).discover();
    check(localized.first.name == '浏览器', 'LC_ALL 优先并回退语言名称');
    final fallbackRoot = '${temp.path}/.local/share';
    await entry(fallbackRoot, 'fallback.desktop', common);
    final fallback = await XdgBrowserDiscovery(
      environment: {
        ...env,
        'XDG_DATA_HOME': 'relative',
        'XDG_DATA_DIRS': '/nonexistent',
      },
      findCommand: find,
    ).discover();
    check(
      fallback.single.id == 'fallback.desktop',
      '忽略相对 XDG_DATA_HOME 并回退 HOME',
    );

    // CI 的 Linux 镜像提供 GIO；实际启动临时脚本，检查字段码和 URL 不被 shell 展开。
    final gio = await DesktopBrowserDiscovery(
      platform: 'linux',
      environment: Platform.environment,
      inFlatpak: false,
    ).findCommand('gio');
    if (gio != null) {
      final output = File('${temp.path}/arguments');
      const url =
          'https://linux.do/user-api-key/new?nonce=a%20b&scopes=read,write';
      final result = await Process.run(
        gio,
        ['launch', '$system/applications/quoted.desktop', url],
        environment: {'FLUXDO_TEST_ARGUMENTS': output.path},
      );
      check(result.exitCode == 0, '真实 GIO 启动：${result.stderr}');
      for (var attempt = 0; attempt < 50 && !await output.exists(); attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      check(
        await output.readAsString() == '--label\nhello world\n$url\n',
        '真实 GIO 展开 %U，保留空格与 URL 原文',
      );
    }
    stdout.writeln(
      'PASS: $checks XDG browser checks (GIO integration: ${gio != null})',
    );
  } finally {
    await temp.delete(recursive: true);
  }
}
