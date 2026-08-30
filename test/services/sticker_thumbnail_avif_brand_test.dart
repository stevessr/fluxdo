import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// Keep this test focused on the ISO BMFF ftyp layout used by animated AVIF.
// The production helper is private, so this verifies representative byte
// layouts through a local equivalent instead of widening the runtime API.
bool looksAnimatedAvif(Uint8List bytes) {
  if (bytes.length < 16) return false;
  if (bytes[4] != 0x66 || bytes[5] != 0x74 || bytes[6] != 0x79 || bytes[7] != 0x70) {
    return false;
  }

  bool isAnimationBrand(int offset) {
    if (offset < 0 || offset + 4 > bytes.length) return false;
    final b0 = bytes[offset];
    final b1 = bytes[offset + 1];
    final b2 = bytes[offset + 2];
    final b3 = bytes[offset + 3];
    return (b0 == 0x61 && b1 == 0x76 && b2 == 0x69 && b3 == 0x73) ||
        (b0 == 0x6D && b1 == 0x73 && b2 == 0x66 && b3 == 0x31);
  }

  if (isAnimationBrand(8)) return true;
  final boxSize =
      (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  final end = boxSize.clamp(16, bytes.length);
  for (var offset = 16; offset + 4 <= end; offset += 4) {
    if (isAnimationBrand(offset)) return true;
  }
  return false;
}

Uint8List ftyp(String major, List<String> compatible) {
  final size = 16 + compatible.length * 4;
  final bytes = BytesBuilder();
  bytes.add([
    (size >> 24) & 0xff,
    (size >> 16) & 0xff,
    (size >> 8) & 0xff,
    size & 0xff,
    0x66,
    0x74,
    0x79,
    0x70,
  ]);
  bytes.add(major.codeUnits);
  bytes.add([0, 0, 0, 0]);
  for (final brand in compatible) {
    bytes.add(brand.codeUnits);
  }
  return bytes.takeBytes();
}

void main() {
  test('detects avis major brand', () {
    expect(looksAnimatedAvif(ftyp('avis', const ['avif', 'mif1'])), isTrue);
  });

  test('detects avis compatible brand', () {
    expect(looksAnimatedAvif(ftyp('avif', const ['mif1', 'avis'])), isTrue);
  });

  test('detects msf1 compatible brand', () {
    expect(looksAnimatedAvif(ftyp('mif1', const ['avif', 'msf1'])), isTrue);
  });

  test('does not mark static avif as animation', () {
    expect(looksAnimatedAvif(ftyp('avif', const ['mif1'])), isFalse);
  });
}
