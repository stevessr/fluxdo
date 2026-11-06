import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import '_workspace_cli.dart';

/// 编译前生成主图与无损差分；完整源稿不在 Flutter 的资产目录中。
void main(List<String> args) {
  enterWorkspaceRoot();
  final check = args.contains('--check');
  _generateLlm({
    'claude': ['happy', 'surprised', 'love'],
    'deepseek': ['happy', 'surprised', 'love'],
  }, check);
  _generateStevessr(check);
}

void _generateLlm(Map<String, List<String>> names, bool check) {
  const directory = 'llm';
  final outputRoot = 'assets/images/avater/$directory';
  final manifest = <String, Object>{
    'version': 1,
    'characters': <String, Object>{},
  };
  final characters = manifest['characters'] as Map<String, Object>;
  var sourceBytes = 0;
  var bundleBytes = 0;
  var outdated = false;
  final outputs = <String, List<int>>{};
  final fingerprint = StringBuffer();
  for (final name in names.keys) {
    final sourceRoot = 'tool/avatar_sources/llm/$name';
    for (final expression in ['neutral', ...names[name]!]) {
      final file = File('$sourceRoot/$expression.webp');
      fingerprint.write(
        '$name/$expression:${sha256.convert(file.readAsBytesSync())};',
      );
    }
  }
  final inputHash = sha256
      .convert(utf8.encode('avatar-delta-v3:$fingerprint'))
      .toString();
  final manifestFile = File('$outputRoot/manifest.json');
  // 日常构建跳过昂贵的重编码；输入/输出散列任何一处变化都会重新生成。
  if (!check && manifestFile.existsSync()) {
    final old =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    final hashes = old['outputs'] as Map<String, dynamic>?;
    if (old['inputHash'] == inputHash &&
        hashes != null &&
        hashes.entries.every((entry) {
          final file = File('$outputRoot/${entry.key}');
          return file.existsSync() &&
              sha256.convert(file.readAsBytesSync()).toString() == entry.value;
        })) {
      stdout.writeln('$directory 角色资产已是最新状态');
      return;
    }
  }
  for (final name in names.keys) {
    final sourceRoot = 'tool/avatar_sources/llm/$name';
    final baseBytes = File('$sourceRoot/neutral.webp').readAsBytesSync();
    final base = img.decodeWebP(baseBytes)!;
    outputs['$name.webp'] = baseBytes;
    sourceBytes += baseBytes.length;
    final variants = <String, Object>{};
    for (final expression in names[name]!) {
      final bytes = File('$sourceRoot/$expression.webp').readAsBytesSync();
      sourceBytes += bytes.length;
      final target = img.decodeWebP(bytes)!;
      if (target.width != base.width || target.height != base.height) {
        throw StateError('$name/$expression 的尺寸与主图不一致');
      }
      var left = base.width, top = base.height, right = -1, bottom = -1;
      for (final pixel in target) {
        final other = base.getPixel(pixel.x, pixel.y);
        // 完全透明的隐藏 RGB 不参与可见差分。
        if (pixel.a == 0 && other.a == 0) continue;
        if (pixel.r != other.r ||
            pixel.g != other.g ||
            pixel.b != other.b ||
            pixel.a != other.a) {
          if (pixel.x < left) left = pixel.x;
          if (pixel.y < top) top = pixel.y;
          if (pixel.x > right) right = pixel.x;
          if (pixel.y > bottom) bottom = pixel.y;
        }
      }
      if (right < left) throw StateError('$name/$expression 没有表情变化');
      final patch = img.copyCrop(
        target,
        x: left,
        y: top,
        width: right - left + 1,
        height: bottom - top + 1,
      );
      // 同时尝试两种无损编码，始终选择实际更小的一份。
      final png = img.encodePng(patch, level: 9);
      final webp = img.encodeWebP(patch, exact: false);
      final useWebp = webp.length < png.length;
      final extension = useWebp ? 'webp' : 'png';
      final path = '${name}_$expression.$extension';
      outputs[path] = useWebp ? webp : png;
      variants[expression] = {
        'asset': path,
        'x': left,
        'y': top,
        'width': patch.width,
        'height': patch.height,
      };
    }
    characters[name] = {
      'width': base.width,
      'height': base.height,
      'expressions': variants,
    };
  }
  manifest['inputHash'] = inputHash;
  manifest['outputs'] = {
    for (final entry in outputs.entries)
      entry.key: sha256.convert(entry.value).toString(),
  };
  outputs['manifest.json'] = utf8.encode(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
  Directory(outputRoot).createSync(recursive: true);
  for (final entry in outputs.entries) {
    bundleBytes += entry.value.length;
    final file = File('$outputRoot/${entry.key}');
    if (!file.existsSync() ||
        sha256.convert(file.readAsBytesSync()) != sha256.convert(entry.value)) {
      outdated = true;
      if (!check) file.writeAsBytesSync(entry.value);
    }
  }
  if (check && outdated) {
    stderr.writeln('角色资产过期，请执行 dart tool/gen_avatar_deltas.dart');
    exitCode = 1;
  }
  // 清理已移除的表情和旧格式，避免重新打包历史生成产物。
  if (!check) {
    for (final file in Directory(outputRoot).listSync().whereType<File>()) {
      if (['.webp', '.png', '.json'].any(file.path.endsWith) &&
          !outputs.containsKey(file.uri.pathSegments.last)) {
        file.deleteSync();
      }
    }
  }
  stdout.writeln(
    '$directory 角色资产：完整源稿 $sourceBytes 字节 → 主图＋差分 $bundleBytes 字节 '
    '（减少 ${(100 * (1 - bundleBytes / sourceBytes)).toStringAsFixed(1)}%）',
  );
}

/// StevesSR 使用规范无损差分源稿，避免构建时重新编码导致体积回退。
void _generateStevessr(bool check) {
  const sourceRoot = 'tool/avatar_sources/stevessr';
  const outputRoot = 'assets/images/avater/stevessr';
  final source = jsonDecode(
    File('$sourceRoot/source.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final entries = source['expressions'] as Map<String, dynamic>;
  final outputs = <String, List<int>>{
    'neutral.webp': File('$sourceRoot/neutral.webp').readAsBytesSync(),
  };
  final variants = <String, Object>{};
  for (final entry in entries.entries) {
    final patch = entry.value as Map<String, dynamic>;
    final path = 'original_${entry.key}.webp';
    outputs[path] = File('$sourceRoot/${patch['asset']}').readAsBytesSync();
    variants[entry.key] = {...patch, 'asset': path};
  }
  final manifest = {
    'version': 1,
    'characters': {
      'original': {
        'width': source['width'],
        'height': source['height'],
        'expressions': variants,
      },
    },
  };
  outputs['manifest.json'] = utf8.encode(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
  Directory(outputRoot).createSync(recursive: true);
  var size = 0;
  for (final entry in outputs.entries) {
    size += entry.value.length;
    final file = File('$outputRoot/${entry.key}');
    if (!file.existsSync() ||
        sha256.convert(file.readAsBytesSync()) != sha256.convert(entry.value)) {
      if (check) {
        stderr.writeln('StevesSR 资产过期：${entry.key}');
        exitCode = 1;
      } else {
        file.writeAsBytesSync(entry.value);
      }
    }
  }
  for (final file in Directory(outputRoot).listSync().whereType<File>()) {
    if (['.webp', '.png', '.json'].any(file.path.endsWith) &&
        !outputs.containsKey(file.uri.pathSegments.last)) {
      if (check) {
        stderr.writeln('陈旧 StevesSR 资产：${file.path}');
        exitCode = 1;
      } else {
        file.deleteSync();
      }
    }
  }
  final original = source['originalBytes'] as int;
  stdout.writeln(
    'stevessr 角色资产：完整原稿 $original 字节 → 主图＋差分 $size 字节 '
    '（减少 ${(100 * (1 - size / original)).toStringAsFixed(1)}%）',
  );
}
