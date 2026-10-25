import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'static_asset_packs.dart';

/// 未来瘦身 Core 的外置字体载入器。
/// 只在 FLUXDO_EXTERNAL_MISANS=true 的构建配置下由启动及设置入口使用。
/// 不重复注册同一字体；更新字体文件后应重新启动进程。
abstract final class OptionalFontLoader {
  static bool _isLoaded = false;
  static Future<bool>? _loading;

  static bool get isLoaded => _isLoaded;

  static Future<bool> ensureMiSansFromPack() {
    if (_isLoaded) return Future<bool>.value(true);
    return _loading ??= _tryLoad().then((ok) {
      if (ok) _isLoaded = true;
      _loading = null;
      return ok;
    }, onError: (Object error, StackTrace trace) {
      _loading = null;
      return false;
    });
  }

  static Future<bool> _tryLoad() async {
    final bytes = await StaticAssetPacks.loadInstalledBytes(
      'assets/fonts/MiSansVF.ttf',
    );
    if (bytes == null || bytes.isEmpty) return false;
    final loader = FontLoader('MiSans');
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    return true;
  }
}
