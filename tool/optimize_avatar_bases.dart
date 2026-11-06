import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import '_workspace_cli.dart';

/// 制作源稿时无损优化主图；验证可见 RGBA 一致且更小后才替换。
Future<void> main(List<String> args) async {
  enterWorkspaceRoot();
  if (args.any((arg) => arg != '--all-avatars')) {
    throw ArgumentError(
      '用法：dart tool/optimize_avatar_bases.dart [--all-avatars]',
    );
  }
  final paths = <String>[
    'tool/avatar_sources/llm/claude/neutral.webp',
    'tool/avatar_sources/llm/deepseek/neutral.webp',
    'tool/avatar_sources/stevessr/neutral.webp',
  ];
  if (args.contains('--all-avatars')) {
    for (final group in ['touhou', 'blue_archive', 'witch_judgment']) {
      paths.addAll(
        Directory('assets/images/avater/$group')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.webp'))
            .map((file) => file.path),
      );
    }
  }
  paths.sort();
  var savedBytes = 0;
  var changed = 0;
  var next = 0;
  final temp = Directory('.dart_tool/avatar_base_optimizer');
  temp.createSync(recursive: true);

  // 两个原生编码进程并行；逐张验证后写入，限制内存与 CPU 占用。
  Future<void> worker(int workerId) async {
    while (next < paths.length) {
      final path = paths[next++];
      final source = File(path);
      final original = source.readAsBytesSync();
      final candidate = File('${temp.path}/candidate_$workerId.webp');
      try {
        await runOrExit(
          title: '无损优化 $path',
          executable: 'magick',
          arguments: [
            path,
            '-quality',
            '100',
            '-define',
            'webp:lossless=true',
            '-define',
            'webp:method=6',
            candidate.path,
          ],
        );
        final encoded = candidate.readAsBytesSync();
        final before = img.decodeWebP(original)!;
        final after = img.decodeWebP(encoded)!;
        if (before.width != after.width ||
            before.height != after.height ||
            _visibleHash(before) != _visibleHash(after)) {
          throw StateError('无损校验失败，保留原图：$path');
        }
        if (encoded.length < original.length) {
          source.writeAsBytesSync(encoded);
          savedBytes += original.length - encoded.length;
          changed++;
          stdout.writeln('$path: ${original.length} → ${encoded.length} 字节');
        } else {
          stdout.writeln('$path: 已是更小或相同的无损版本，保留原图');
        }
      } finally {
        if (candidate.existsSync()) candidate.deleteSync();
      }
    }
  }

  await Future.wait([worker(0), worker(1)]);
  stdout.writeln('验证 ${paths.length} 张主图，优化 $changed 张，节省 $savedBytes 字节');
}

Digest _visibleHash(img.Image image) {
  for (final pixel in image) {
    if (pixel.a == 0) pixel.setRgba(0, 0, 0, 0);
  }
  return sha256.convert(image.getBytes(order: img.ChannelOrder.rgba));
}
