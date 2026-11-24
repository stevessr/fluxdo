import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/fonts/emoji_font_service.dart';

void main() {
  test('format 4 cmap applies glyph delta and excludes the sentinel', () {
    final data = ByteData(72);
    data.setUint32(0, 0x00010000);
    data.setUint16(4, 1);
    data.setUint32(12, 0x636d6170);
    data.setUint32(20, 28);
    data.setUint32(24, 44);
    data.setUint16(30, 1);
    data.setUint16(32, 3);
    data.setUint16(34, 1);
    data.setUint32(36, 12);
    data.setUint16(40, 4);
    data.setUint16(42, 32);
    data.setUint16(46, 4);
    data.setUint16(54, 0x2764);
    data.setUint16(56, 0xffff);
    data.setUint16(60, 0x2764);
    data.setUint16(62, 0xffff);
    data.setUint16(64, (1 - 0x2764) & 0xffff);
    data.setUint16(66, 1);
    expect(emojiFontCoverage(data.buffer.asUint8List()), {0x2764});
  });

  test('format 12 cmap reads glyph coverage and skips glyph zero', () {
    final data = ByteData(72);
    data.setUint32(0, 0x00010000);
    data.setUint16(4, 1);
    data.setUint32(12, 0x636d6170);
    data.setUint32(20, 28);
    data.setUint32(24, 40);
    data.setUint16(30, 1);
    data.setUint16(32, 3);
    data.setUint16(34, 10);
    data.setUint32(36, 12);
    data.setUint16(40, 12);
    data.setUint32(44, 28);
    data.setUint32(52, 1);
    data.setUint32(56, 0x1f600);
    data.setUint32(60, 0x1f602);
    data.setUint32(64, 0);
    final coverage = emojiFontCoverage(data.buffer.asUint8List());
    expect(coverage, {0x1f601, 0x1f602});
    expect(emojiFontCoverage(Uint8List(4)), isEmpty);
  });
}
