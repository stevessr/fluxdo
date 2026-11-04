import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 一张长图切片的本地文件。
class LongImageSlice {
  const LongImageSlice({required this.path, required this.name});

  final String path;
  final String name;
}

/// 长图尺寸信息。
class LongImageInfo {
  const LongImageInfo({required this.width, required this.height});

  final int width;
  final int height;

  double get aspectRatio => width <= 0 ? 0 : height / width;

  bool get isEligible =>
      width > 0 &&
      height > 0 &&
      aspectRatio >= LongImageSplitter.triggerAspectRatio;
}

/// 指定切片数量后的几何计划。
class LongImageSplitPlan {
  const LongImageSplitPlan({
    required this.partHeight,
    required this.starts,
    required this.overlapFraction,
  });

  final int partHeight;
  final List<int> starts;
  final double overlapFraction;

  int get partCount => starts.length;
}

/// 独立“长图上传”入口使用的切割器。
///
/// 普通图片上传链路不得调用此类。只有用户主动进入长图上传、选中一张
/// 图片并通过宽高比检查后，才读取/切割图片。
class LongImageSplitter {
  LongImageSplitter._();

  /// 高度达到宽度的 3 倍时允许进入长图切割。
  static const double triggerAspectRatio = 3.0;

  /// 推荐切片数以单片高度约不超过宽度 2 倍为目标。
  static const double targetPartAspectRatio = 2.0;

  /// 相邻切片重叠 10%。
  static const double overlapFraction = 0.10;

  static const Set<String> _supportedExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
  };

  static bool supportsPath(String sourcePath) =>
      _supportedExtensions.contains(p.extension(sourcePath).toLowerCase());

  /// 读取图片方向修正后的实际尺寸。
  ///
  /// 这个方法只由独立长图上传入口调用，因此普通图片上传不会产生额外解码。
  static Future<LongImageInfo?> inspect(String sourcePath) async {
    if (!supportsPath(sourcePath)) return null;
    try {
      final sourceBytes = await File(sourcePath).readAsBytes();
      return Isolate.run<LongImageInfo?>(() {
        final decoded = img.decodeImage(sourceBytes);
        if (decoded == null) return null;
        final oriented = img.bakeOrientation(decoded);
        return LongImageInfo(width: oriented.width, height: oriented.height);
      });
    } catch (_) {
      return null;
    }
  }

  /// 根据尺寸给出一个建议值；最终切片数必须由用户明确选择。
  static int recommendedPartCount({
    required int width,
    required int height,
    double targetPartRatio = targetPartAspectRatio,
    double overlap = overlapFraction,
  }) {
    if (width <= 0 || height <= 0) return 2;
    final targetHeight = (width * targetPartRatio).clamp(1, height);
    final raw =
        ((height / targetHeight - overlap) / (1 - overlap)).ceil();
    return raw.clamp(2, height).toInt();
  }

  /// 按用户指定的数量生成切片计划。
  static LongImageSplitPlan planForCount({
    required int width,
    required int height,
    required int partCount,
    double overlap = overlapFraction,
  }) {
    if (width <= 0 || height <= 0 || partCount < 2) {
      throw ArgumentError('长图切片需要有效尺寸且切片数量至少为 2');
    }
    final count = partCount.clamp(2, height).toInt();

    // 总高度 = 单片高度 * [n - (n - 1) * overlap]。
    final coveredUnits = count - (count - 1) * overlap;
    final partHeight = (height / coveredUnits)
        .ceil()
        .clamp(1, height)
        .toInt();
    final travel = height - partHeight;
    final starts = <int>[
      for (var i = 0; i < count; i++)
        (travel * i / (count - 1)).round(),
    ];

    return LongImageSplitPlan(
      partHeight: partHeight,
      starts: starts,
      overlapFraction: overlap,
    );
  }

  /// 按用户明确选择的 [partCount] 切割。
  static Future<List<LongImageSlice>> split(
    String sourcePath, {
    required String originalName,
    required int partCount,
  }) async {
    if (!supportsPath(sourcePath)) {
      throw UnsupportedError('不支持该图片格式的长图切割');
    }

    final sourceBytes = await File(sourcePath).readAsBytes();
    final extension = p.extension(sourcePath).toLowerCase();
    final payload = await Isolate.run<_SplitPayload?>(() {
      final decoded = img.decodeImage(sourceBytes);
      if (decoded == null) return null;

      final oriented = img.bakeOrientation(decoded);
      final info = LongImageInfo(width: oriented.width, height: oriented.height);
      if (!info.isEligible) return null;

      final splitPlan = planForCount(
        width: oriented.width,
        height: oriented.height,
        partCount: partCount,
      );
      final jpeg = extension == '.jpg' || extension == '.jpeg';
      final outputExtension = jpeg ? 'jpg' : 'png';
      final parts = <Uint8List>[];

      for (final start in splitPlan.starts) {
        final remaining = oriented.height - start;
        final cropHeight = remaining < splitPlan.partHeight
            ? remaining
            : splitPlan.partHeight;
        final cropped = img.copyCrop(
          oriented,
          x: 0,
          y: start,
          width: oriented.width,
          height: cropHeight,
        );
        final encoded = jpeg
            ? img.encodeJpg(cropped, quality: 100)
            : img.encodePng(cropped);
        parts.add(Uint8List.fromList(encoded));
      }

      return _SplitPayload(extension: outputExtension, parts: parts);
    });

    if (payload == null || payload.parts.length != partCount) {
      throw StateError('图片尺寸不符合长图切割要求');
    }

    final tempDir = await getTemporaryDirectory();
    final stem = p.basenameWithoutExtension(originalName);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final digits = payload.parts.length.toString().length;
    final slices = <LongImageSlice>[];

    for (var i = 0; i < payload.parts.length; i++) {
      final partNo = (i + 1).toString().padLeft(digits, '0');
      final name =
          '${stem}_part_${partNo}_of_${payload.parts.length}.${payload.extension}';
      final path = p.join(tempDir.path, 'long_image_${stamp}_$name');
      await File(path).writeAsBytes(payload.parts[i], flush: true);
      slices.add(LongImageSlice(path: path, name: name));
    }

    return slices;
  }
}

class _SplitPayload {
  const _SplitPayload({required this.extension, required this.parts});

  final String extension;
  final List<Uint8List> parts;
}
