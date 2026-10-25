import 'dart:io';

/// 保留 desktop 文件本身，由 GIO 处理 Exec 字段码、工作目录与 D-Bus 激活。
typedef XdgBrowserEntry = ({
  String id,
  String name,
  String path,
  String? command,
  String? icon,
  String? exec,
});

class XdgBrowserDiscovery {
  XdgBrowserDiscovery({required this.environment, required this.findCommand});

  final Map<String, String> environment;
  final Future<String?> Function(String) findCommand;

  Future<List<XdgBrowserEntry>> discover() async {
    final home = environment['HOME'] ?? '';
    final dataHome = environment['XDG_DATA_HOME'];
    final dataDirs = environment['XDG_DATA_DIRS'];
    final roots = <String>{
      if (dataHome != null && dataHome.startsWith('/'))
        dataHome
      else if (home.startsWith('/'))
        '$home/.local/share',
      ...(dataDirs == null || dataDirs.isEmpty
              ? '/usr/local/share:/usr/share'
              : dataDirs)
          .split(':')
          .where((path) => path.startsWith('/')),
    };
    final seen = <String>{};
    final result = <XdgBrowserEntry>[];
    for (final root in roots) {
      final directory = Directory('$root/applications');
      try {
        // 不跟随目录链接，避免循环或离开应用目录；文件链接仍可读取。
        final files = await directory
            .list(recursive: true, followLinks: false)
            .where((entry) => entry.path.endsWith('.desktop'))
            .toList();
        files.sort((a, b) => a.path.compareTo(b.path));
        for (final file in files) {
          final id = file.path
              .substring(directory.path.length + 1)
              .replaceAll('/', '-');
          // 用户覆盖及 Hidden 墓碑必须先占用 ID，不能回退到系统版本。
          if (!seen.add(id)) continue;
          try {
            final values = _parse(await File(file.path).readAsString());
            if (values['Type'] != 'Application' ||
                values['Hidden'] == 'true' ||
                values['Terminal'] == 'true' ||
                id == 'fluxdo.desktop' ||
                id == 'com.github.lingyan000.fluxdo.desktop') {
              continue;
            }
            final mimeTypes = (values['MimeType'] ?? '').split(';');
            if (!mimeTypes.contains('x-scheme-handler/http') ||
                !mimeTypes.contains('x-scheme-handler/https')) {
              continue;
            }
            if (!_visible(values) || !_isBrowser(values, id)) continue;
            final name = _name(values);
            if (name.isEmpty) continue;
            final tryExec = values['TryExec'];
            if (tryExec != null && await _executable(tryExec) == null) continue;
            final command = _firstCommand(values['Exec'] ?? '');
            if (values['DBusActivatable'] != 'true' &&
                (command == null || await _executable(command) == null)) {
              continue;
            }
            result.add((
              id: id,
              name: name,
              path: file.path,
              command: command,
              icon: values['Icon'],
              exec: values['Exec'],
            ));
          } on FileSystemException {
            // 不可读或损坏的单个入口不阻断其他浏览器。
          } on FormatException {
            // 忽略非 UTF-8 文件。
          }
        }
      } on FileSystemException {
        // 可选数据目录不存在或不可访问时继续下一项。
      }
    }
    return result;
  }

  // Handling HTTPS alone does not mean the application is a browser (chat
  // clients and other URL handlers often register both schemes).
  static bool _isBrowser(Map<String, String> values, String id) {
    if ((values['Categories'] ?? '').split(';').contains('WebBrowser')) {
      return true;
    }
    final label = '${values['Name'] ?? ''} ${values['GenericName'] ?? ''} $id'
        .toLowerCase();
    return RegExp(
      r'browser|firefox|chromium|chrome|librewolf|waterfox|floorp|brave|vivaldi|opera|falkon|epiphany|midori|qutebrowser|mullvad|cromite|thorium',
    ).hasMatch(label);
  }

  Future<String?> _executable(String command) async {
    if (!command.startsWith('/')) {
      if (command.contains('/')) return null;
      return findCommand(command);
    }
    final stat = await File(command).stat();
    return stat.type == FileSystemEntityType.file && stat.mode & 0x49 != 0
        ? command
        : null;
  }

  bool _visible(Map<String, String> values) {
    final desktops = (environment['XDG_CURRENT_DESKTOP'] ?? '').split(':');
    final only = values['OnlyShowIn']?.split(';');
    final not = (values['NotShowIn'] ?? '').split(';');
    for (final desktop in desktops.where((d) => d.isNotEmpty)) {
      if (only?.contains(desktop) ?? false) return true;
      if (not.contains(desktop)) return false;
    }
    return only == null;
  }

  String _name(Map<String, String> values) {
    final locale = ['LC_ALL', 'LC_MESSAGES', 'LANG']
        .map((key) => environment[key] ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => 'C')
        .replaceFirst(RegExp(r'\.[^@]*'), '');
    final parts = locale.split('@');
    final language = parts.first.split('_').first;
    for (final suffix in <String>{
      locale,
      parts.first,
      if (parts.length > 1) '$language@${parts[1]}',
      language,
    }) {
      if (values.containsKey('Name[$suffix]')) return values['Name[$suffix]']!;
    }
    return values['Name'] ?? '';
  }

  static Map<String, String> _parse(String source) {
    final values = <String, String>{};
    var inEntry = false;
    for (final raw in source.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('[')) {
        inEntry = line == '[Desktop Entry]';
      } else if (inEntry && !line.startsWith('#')) {
        final equals = line.indexOf('=');
        if (equals > 0) {
          values[line.substring(0, equals).trim()] = _unescape(
            line.substring(equals + 1).trim(),
          );
        }
      }
    }
    return values;
  }

  static String _unescape(String value) => value.replaceAllMapped(
    RegExp(r'\\([sntr\\])'),
    (m) => switch (m[1]) {
      's' => ' ',
      'n' => '\n',
      't' => '\t',
      'r' => '\r',
      _ => '\\',
    },
  );

  // 只取入口做安装检查及 PATH 回退去重，绝不自行执行或展开 Exec。
  static String? _firstCommand(String exec) {
    final match = RegExp(r'^(?:"((?:\\.|[^"\\])*)"|([^\s"]+))(?:\s|$)')
        .firstMatch(exec);
    if (match == null) return null;
    return (match[1] ?? match[2]!).replaceAllMapped(
      RegExp(r'\\(["`$\\])'),
      (m) => m[1]!,
    );
  }
}
