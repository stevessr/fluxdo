import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 基准来自压缩前的提交 0e95dfa5，不随优化后的资产自动更新。
  final originals = jsonDecode(
    File('test/fixtures/avatar_rgba_hashes.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  for (final entry in originals.entries) {
    test('${entry.key} 保持原尺寸、可见 RGB 和完整透明度', () async {
      final data = await rootBundle.load(entry.key);
      final image = img.decodeWebP(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      )!;
      final expected = entry.value as Map<String, dynamic>;
      expect(image.width, expected['width']);
      expect(image.height, expected['height']);
      // 只忽略 alpha 为零时不影响显示的隐藏 RGB，仍保留所有 alpha 值。
      for (final pixel in image) {
        if (pixel.a == 0) pixel.setRgba(0, 0, 0, 0);
      }
      expect(
        sha256.convert(image.getBytes(order: img.ChannelOrder.rgba)).toString(),
        expected['rgbaHash'],
      );
    });
  }
}
