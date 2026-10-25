import 'dart:io';
import 'dart:typed_data';

/// Resolves the Icon= value of an XDG desktop entry using the installed icon
/// theme directories. It never executes a .desktop file or downloads artwork.
///
/// The caller caches the resulting bytes with the browser discovery results.
class XdgBrowserIconLoader {
  XdgBrowserIconLoader({required this.environment});

  final Map<String, String> environment;
  static const _maxBytes = 1024 * 1024;

  Future<({Uint8List bytes, bool isSvg})?> load(String? icon) async {
    if (icon == null || icon.trim().isEmpty) return null;
    final value = icon.trim();
    final paths = value.startsWith('/')
        ? <String>[value]
        : _iconCandidates(value);

    for (final path in paths) {
      if (!_supportedPath(path)) continue;
      try {
        final file = File(path);
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file ||
            stat.size == 0 ||
            stat.size > _maxBytes) {
          continue;
        }
        final data = await file.readAsBytes();
        if (data.isNotEmpty && data.length <= _maxBytes) {
          return (bytes: data, isSvg: path.toLowerCase().endsWith('.svg'));
        }
      } on FileSystemException {
        // A missing theme, icon or dangling symlink is expected.
      }
    }
    return null;
  }

  static bool _supportedPath(String path) {
    final value = path.toLowerCase();
    return value.endsWith('.png') ||
        value.endsWith('.svg') ||
        value.endsWith('.webp') ||
        value.endsWith('.jpg') ||
        value.endsWith('.jpeg');
  }

  List<String> _iconCandidates(String name) {
    // Freedesktop icon names are not file paths. Block relative traversals.
    if (name.contains('/') || name.contains('\\') || name == '..') {
      return const [];
    }
    final bareName = name.replaceFirst(
      RegExp(r'\.(png|svg|webp|jpe?g)$', caseSensitive: false),
      '',
    );
    final home = environment['HOME'] ?? '';
    final dataHome = environment['XDG_DATA_HOME'];
    final effectiveHome = dataHome != null && dataHome.startsWith('/')
        ? dataHome
        : home.startsWith('/')
        ? '$home/.local/share'
        : null;
    final dataDirs = (environment['XDG_DATA_DIRS']?.isNotEmpty ?? false)
        ? environment['XDG_DATA_DIRS']!
        : '/usr/local/share:/usr/share';
    final roots = <String>{
      if (effectiveHome != null) effectiveHome,
      ...dataDirs.split(':').where((p) => p.startsWith('/')),
    };
    final iconRoots = <String>{
      if (home.startsWith('/')) '$home/.icons',
      for (final root in roots) '$root/icons',
    };
    final themes = <String>{
      if ((environment['XDG_ICON_THEME'] ?? '').isNotEmpty)
        environment['XDG_ICON_THEME']!,
      if ((environment['GTK_ICON_THEME'] ?? '').isNotEmpty)
        environment['GTK_ICON_THEME']!,
      'hicolor',
      'Adwaita',
      'breeze',
      'Papirus',
    }.where((theme) => !theme.contains('/') && theme != '..').toList();

    // Prefer a comfortably sized raster icon. SVG is preserved when no PNG
    // exists; the picker uses its SVG renderer rather than Image.memory.
    final results = <String>[];
    for (final extension in const ['png', 'webp', 'jpg', 'jpeg', 'svg']) {
      for (final root in iconRoots) {
        for (final theme in themes) {
          for (final size in const [
            '64x64',
            '48x48',
            '128x128',
            '256x256',
            '32x32',
            'scalable',
            '512x512',
            '24x24',
          ]) {
            results.add('$root/$theme/$size/apps/$bareName.$extension');
          }
        }
      }
      for (final root in roots) {
        results.add('$root/pixmaps/$bareName.$extension');
        results.add('$root/icons/$bareName.$extension');
      }
      results.add('/usr/share/pixmaps/$bareName.$extension');
    }
    return results;
  }
}
