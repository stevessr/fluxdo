import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 一张长图切片的本地文件。
class LongImageSlice {
  const LongImageSlice({required this.path, required this.name});

  final String path;
  final String name;
}

/// 长图切割计划。
///
/// 相邻切片使用固定比例重叠：后一张顶部的重叠区，正好对应前一张底部
/// 的同一块内容。这样阅读时既不会丢行，也不会因为上下各补一份而把重叠
/// 误放大成 20%。
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
  bool get shouldSplit => partCount > 1;
}

/// 长图上传前切割器。
///
/// 只处理静态 PNG/JPEG/WebP。GIF 保持原文件，避免切割后丢失动画。
class LongImageSplitter {
  LongImageSplitter._();

  /// 高度达到宽度的 3 倍时视为长图。
  static const double triggerAspectRatio = 3.0;

  /// 每个切片目标高度不超过宽度的 2 倍。
  static const double targetPartAspectRatio = 2.0;

  /// 相邻切片重叠 10%。
  static const double overlapFraction = 0.10;

  static const Set<String> _supportedExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
  };

  /// 纯几何计算，独立于图片编解码，便于测试边界条件。
  static LongImageSplitPlan plan({
    required int width,
    required int height,
    double triggerRatio = triggerAspectRatio,
    double targetPartRatio = targetPartAspectRatio,
    double overlap = overlapFraction,
  }) {
    if (width <= 0 || height <= 0) {
      return const LongImageSplitPlan(
        partHeight: 0,
        starts: [0],
        overlapFraction: overlapFraction,
      );
    }

    final ratio = height / width;
    if (ratio < triggerRatio) {
      return LongImageSplitPlan(
        partHeight: height,
        starts: const [0],
        overlapFraction: overlap,
      );
    }

    final maxPartHeight = (width * targetPartRatio)
        .round()
        .clamp(1, height)
        .toInt();

    // 总高度 = 单片高度 * [n - (n - 1) * overlap]。
    // 先求满足目标单片高度上限的最少片数，再反推等高切片高度。
    final rawCount =
        ((height / maxPartHeight - overlap) / (1 - overlap)).ceil();
    final count = rawCount.clamp(2, height).toInt();
    final coveredUnits = count - (count - 1) * overlap;
    final partHeight = (height / coveredUnits)
        .ceil()
        .clamp(1, height)
        .toInt();

    // 均匀分布起点并让最后一片严格贴住图底。由上面的 coveredUnits
    // 可知相邻步长约为 partHeight * (1 - overlap)，即约 10% 重叠。
    final travel = height - partHeight;
    final starts = <int>[
      for (var i = 0; i < count; i++)
        count == 1 ? 0 : (travel * i / (count - 1)).round(),
    ];

    return LongImageSplitPlan(
      partHeight: partHeight,
      starts: starts,
      overlapFraction: overlap,
    );
  }

  /// 需要时切成长图分片，否则返回原文件本身。
  ///
  /// 解码/切割失败时退回原文件，不能因为增强功能阻断原本可用的上传链路。
  static Future<List<LongImageSlice>> splitIfNeeded(
    String sourcePath, {
    required String originalName,
  }) async {
    final extension = p.extension(sourcePath).toLowerCase();
    if (!_supportedExtensions.contains(extension)) {
      return [LongImageSlice(path: sourcePath, name: originalName)];
    }

    try {
      final sourceBytes = await File(sourcePath).readAsBytes();
      final payload = await Isolate.run<_SplitPayload?>(() {
        final decoded = img.decodeImage(sourceBytes);
        if (decoded == null) return null;

        final oriented = img.bakeOrientation(decoded);
        final splitPlan = plan(width: oriented.width, height: oriented.height);
        if (!splitPlan.shouldSplit) return null;

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

        return _SplitPayload(
          extension: outputExtension,
          parts: parts,
        );
      });

      if (payload == null || payload.parts.length <= 1) {
        return [LongImageSlice(path: sourcePath, name: originalName)];
      }

      final tempDir = await getTemporaryDirectory();
      final stem = p.basenameWithoutExtension(originalName);
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final width = payload.parts.length.toString().length;
      final slices = <LongImageSlice>[];

      for (var i = 0; i < payload.parts.length; i++) {
        final partNo = (i + 1).toString().padLeft(width, '0');
        final name =
            '${stem}_part_${partNo}_of_${payload.parts.length}.${payload.extension}';
        final path = p.join(tempDir.path, 'long_image_${stamp}_$name');
        await File(path).writeAsBytes(payload.parts[i], flush: true);
        slices.add(LongImageSlice(path: path, name: name));
      }

      return slices;
    } catch (error, stackTrace) {
      debugPrint('[LongImageSplitter] 长图切割失败，回退原图: $error');
      debugPrintStack(stackTrace: stackTrace);
      return [LongImageSlice(path: sourcePath, name: originalName)];
    }
  }
}

class _SplitPayload {
  const _SplitPayload({required this.extension, required this.parts});

  final String extension;
  final List<Uint8List> parts;
}
