import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import '_workspace_cli.dart';

/// 制作规范差分源稿；日常构建直接打包这些无损源稿，不需要系统编码器。
Future<void> main(List<String> args) async {
  enterWorkspaceRoot();
  if (args.length != 1) {
    throw ArgumentError(
      '用法：dart tool/pack_stevessr_sources.dart <完整表情 WebP 目录>',
    );
  }
  final source = args.single;
  const output = 'tool/avatar_sources/stevessr';
  final baseBytes = File('$source/neutral.webp').readAsBytesSync();
  final base = img.decodeWebP(baseBytes)!;
  final entries = <String, Object>{};
  var originalBytes = baseBytes.length;
  final files =
      Directory(source)
          .listSync()
          .whereType<File>()
          .where(
            (file) =>
                file.path.endsWith('.webp') &&
                file.uri.pathSegments.last != 'neutral.webp',
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  Directory(output).createSync(recursive: true);
  File('$output/neutral.webp').writeAsBytesSync(baseBytes);
  for (final file in files) {
    final name = file.uri.pathSegments.last.replaceAll('.webp', '');
    final bytes = file.readAsBytesSync();
    originalBytes += bytes.length;
    final target = img.decodeWebP(bytes)!;
    if (target.width != base.width || target.height != base.height) {
      throw StateError('表情尺寸不一致：$name');
    }
    var left = base.width, top = base.height, right = -1, bottom = -1;
    for (final pixel in target) {
      final old = base.getPixel(pixel.x, pixel.y);
      if (pixel.a == 0 && old.a == 0) continue;
      if (pixel.r != old.r ||
          pixel.g != old.g ||
          pixel.b != old.b ||
          pixel.a != old.a) {
        if (pixel.x < left) left = pixel.x;
        if (pixel.y < top) top = pixel.y;
        if (pixel.x > right) right = pixel.x;
        if (pixel.y > bottom) bottom = pixel.y;
      }
    }
    if (right < left) throw StateError('没有表情变化：$name');
    final patch = img.copyCrop(
      target,
      x: left,
      y: top,
      width: right - left + 1,
      height: bottom - top + 1,
    );
    final temp = File('.dart_tool/stevessr-source-patch.png');
    temp.parent.createSync(recursive: true);
    temp.writeAsBytesSync(img.encodePng(patch));
    try {
      await runOrExit(
        title: '无损编码 StevesSR $name 差分源稿',
        executable: 'magick',
        arguments: [
          temp.path,
          '-quality',
          '100',
          '-define',
          'webp:lossless=true',
          '-define',
          'webp:method=6',
          '$output/$name.webp',
        ],
      );
    } finally {
      temp.deleteSync();
    }
    for (final pixel in target) {
      if (pixel.a == 0) pixel.setRgba(0, 0, 0, 0);
    }
    entries[name] = {
      'asset': '$name.webp',
      'x': left,
      'y': top,
      'width': patch.width,
      'height': patch.height,
      'pixelHash': sha256
          .convert(target.getBytes(order: img.ChannelOrder.rgba))
          .toString(),
    };
  }
  final metadata = {
    'version': 1,
    'width': base.width,
    'height': base.height,
    'originalBytes': originalBytes,
    'expressions': entries,
  };
  File('$output/source.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(metadata)}\n',
  );
}
