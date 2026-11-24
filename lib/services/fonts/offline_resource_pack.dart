import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Optional Android resource-only companion. Its assets are accessed through
/// the existing plugin channel; other platforms keep their original behavior.
class OfflineResourcePack {
  OfflineResourcePack._();
  static final instance = OfflineResourcePack._();
  static const _channel =
      MethodChannel('com.github.lingyan000.fluxdo/external_plugins');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static final _name = RegExp(r'^[a-z0-9_+-]+(?::t[1-6])?$');
  static const _sets = {
    'noto', 'twemoji', 'fluentui', 'openmoji', 'unicode',
    'noto_3d', 'noto_animated',
  };

  static String? emojiPath(String name, String set) {
    if (!_sets.contains(set) || !_name.hasMatch(name)) return null;
    final ext = set == 'noto_animated' ? 'webp' : 'png';
    return 'emoji/$set/${name.replaceFirst(':t', '/')}.$ext';
  }

  Future<File?> copyFont(String path) async {
    if (!supported) return null;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'copyPackFont', {'path': path},
      );
      final local = result?['path'];
      return local is String ? File(local) : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  // Coalesce duplicate glyph reads and cap retained encoded assets. Expiry
  // allows freshly installed/upgraded packs to become visible without a restart.
  final _images = <String, (DateTime, Future<PackEmojiAsset>)>{};

  Future<PackEmojiAsset> emoji(String path) {
    if (!supported) return Future.value(const PackEmojiAsset(false));
    final previous = _images.remove(path);
    if (previous != null &&
        DateTime.now().difference(previous.$1) < const Duration(seconds: 30)) {
      _images[path] = previous;
      return previous.$2;
    }
    final future = _readEmoji(path);
    _images[path] = (DateTime.now(), future);
    if (_images.length > 64) _images.remove(_images.keys.first);
    return future;
  }

  Future<PackEmojiAsset> _readEmoji(String path) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'readPackEmoji', {'path': path},
      );
      final bytes = result?['bytes'];
      return PackEmojiAsset(result?['installed'] == true,
          bytes is Uint8List && bytes.isNotEmpty ? bytes : null);
    } on PlatformException {
      return const PackEmojiAsset(false);
    } on MissingPluginException {
      return const PackEmojiAsset(false);
    }
  }
}

class PackEmojiAsset {
  const PackEmojiAsset(this.installed, [this.bytes]);
  final bool installed;
  final Uint8List? bytes;
}
