import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '_workspace_cli.dart';

/// 将 AI 编辑稿的局部脸部变化固定到原图；避免无关的头发/衣服像素漂移。
/// 此工具只在制作源稿时运行，日常构建不依赖 ImageMagick 或图片生成服务。
Future<void> main(List<String> args) async {
  enterWorkspaceRoot();
  if (args.length != 3 ||
      !['claude', 'deepseek'].contains(args[0]) ||
      !['happy', 'surprised', 'love'].contains(args[1])) {
    throw ArgumentError(
      '用法：dart run tool/import_avatar_expression.dart <claude|deepseek> <happy|surprised|love> <AI 编辑稿.png>',
    );
  }
  final name = args[0];
  final base = img.decodeWebP(
    File('tool/avatar_sources/llm/$name/neutral.webp').readAsBytesSync(),
  )!;
  var edited = img.decodeImage(File(args[2]).readAsBytesSync())!;
  if (edited.width != base.width || edited.height != base.height) {
    edited = img.copyResize(
      edited,
      width: base.width,
      height: base.height,
      interpolation: img.Interpolation.cubic,
    );
  }
  // 保留眼睛和发丝，只有两眼下方的空白脸颊和嘴部参与差分。
  final bounds = name == 'claude' ? [450, 775, 795, 880] : [390, 862, 720, 967];
  for (var y = bounds[1]; y < bounds[3]; y++) {
    for (var x = bounds[0]; x < bounds[2]; x++) {
      if ((name == 'claude' && x > 700 && y < 815) ||
          (name == 'deepseek' && x > 640 && y < 892)) {
        continue;
      }
      final edge = math.min(
        math.min(x - bounds[0], bounds[2] - 1 - x),
        math.min(y - bounds[1], bounds[3] - 1 - y),
      );
      final weight = (edge / 10).clamp(0.0, 1.0);
      final old = base.getPixel(x, y);
      final next = edited.getPixel(x, y);
      base.setPixelRgba(
        x,
        y,
        (old.r * (1 - weight) + next.r * weight).round(),
        (old.g * (1 - weight) + next.g * weight).round(),
        (old.b * (1 - weight) + next.b * weight).round(),
        old.a,
      );
    }
  }
  final temp = File('.dart_tool/${name}_${args[1]}.png');
  temp.parent.createSync(recursive: true);
  temp.writeAsBytesSync(img.encodePng(base));
  try {
    await runOrExit(
      title: '无损保存表情源稿',
      executable: 'magick',
      arguments: [
        temp.path,
        '-define',
        'webp:lossless=true',
        'tool/avatar_sources/llm/$name/${args[1]}.webp',
      ],
    );
  } finally {
    if (temp.existsSync()) temp.deleteSync();
  }
}
