import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 差分是最小变化矩形的完整 RGBA 替换块，不能用 alpha 混合代替。
Uint8List restoreAvatarDelta(Map<String, Object> input) {
  final base = img.decodeWebP(input['base'] as Uint8List)!;
  final patch = img.decodeImage(input['patch'] as Uint8List)!;
  final x = input['x'] as int;
  final y = input['y'] as int;
  if (x < 0 ||
      y < 0 ||
      x + patch.width > base.width ||
      y + patch.height > base.height) {
    throw StateError('角色差分超出主图边界');
  }
  for (final pixel in patch) {
    base.setPixelRgba(
      x + pixel.x,
      y + pixel.y,
      pixel.r,
      pixel.g,
      pixel.b,
      pixel.a,
    );
  }
  return Uint8List.fromList(img.encodePng(base));
}
