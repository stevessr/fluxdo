import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/stevessr_render_params.dart';
import 'avatar_delta_codec.dart';
import 'assets/static_asset_packs.dart';

/// 预览和导出共享同一份还原结果，按角色目录区分主图和清单，缓存最近使用的表情。
abstract final class StevessrCharacterAssets {
  static const root = 'assets/images/avater/';
  static final _cache = <String, Future<Uint8List>>{};
  static final _manifests = <String, Future<Map<String, dynamic>>>{};
  static StreamSubscription<String>? _packChanges;
  static int _generation = 0;

  static void _watchPackChanges() {
    _packChanges ??= StaticAssetPacks.changes.listen((packId) {
      if (!packId.startsWith('avatar-')) return;
      _generation++;
      _cache.clear();
      _manifests.clear();
    });
  }

  static bool usesDelta(
    StevessrCharacter character,
    StevessrExpression emotion,
  ) =>
      character.usesExpressionDeltas &&
      character.resolveExpression(emotion) != StevessrExpression.neutral;

  static Future<Uint8List> load(
    StevessrCharacter character,
    StevessrExpression emotion,
  ) async {
    _watchPackChanges();
    final base = '$root${character.assetPath(emotion: emotion)}';
    if (!usesDelta(character, emotion)) return _loadAsset(base);
    final resolved = character.resolveExpression(emotion);
    final key = '${character.type.directory}/${character.name}/${resolved.key}';
    if (_cache.length >= 8 && !_cache.containsKey(key)) {
      _cache.remove(_cache.keys.first);
    }
    final pending = _cache.putIfAbsent(
      key,
      () => _restoreStable(character, resolved, base),
    );
    try {
      return await pending;
    } catch (_) {
      if (identical(_cache[key], pending)) _cache.remove(key);
      rethrow;
    }
  }

  static Future<Uint8List> _loadAsset(String path) =>
      StaticAssetPacks.loadBytes(path);

  /// 包升级时不返回跨版本主图/差分的组合。
  static Future<Uint8List> _restoreStable(
    StevessrCharacter character,
    StevessrExpression emotion,
    String base,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final observed = _generation;
      final restored = await _restore(character, emotion, base);
      if (observed == _generation) return restored;
    }
    throw StateError('角色素材连续更新，无法获得一致的资源版本');
  }

  static Future<Uint8List> _restore(
    StevessrCharacter character,
    StevessrExpression emotion,
    String base,
  ) async {
    final directory = character.type.directory;
    final manifestFuture = _manifests.putIfAbsent(
      directory,
      () => StaticAssetPacks
          .loadString('$root$directory/manifest.json')
          .then((value) => jsonDecode(value) as Map<String, dynamic>),
    );
    late final Map<String, dynamic> manifest;
    try {
      manifest = await manifestFuture;
    } catch (_) {
      _manifests.remove(directory);
      rethrow;
    }
    final name = character.name.isEmpty ? 'original' : character.name;
    final entry =
        manifest['characters'][name]['expressions'][emotion.key]
            as Map<String, dynamic>;
    return compute(restoreAvatarDelta, <String, Object>{
      'base': await _loadAsset(base),
      'patch': await _loadAsset('$root$directory/${entry['asset']}'),
      'x': entry['x'] as int,
      'y': entry['y'] as int,
    });
  }
}
