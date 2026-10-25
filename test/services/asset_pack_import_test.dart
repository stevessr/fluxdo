import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/assets/asset_pack_import.dart';

void main() {
  test('streamed ZIP respects announced length and max limit', () async {
    final bytes = await readBoundedPackStream(
      Stream<List<int>>.fromIterable([
        Uint8List.fromList([1, 2]),
        Uint8List.fromList([3, 4]),
      ]),
      expectedBytes: 4,
      maxBytes: 6,
    );
    expect(bytes, [1, 2, 3, 4]);
  });

  test('rejects truncated, oversized and empty ZIPs', () async {
    await expectLater(
      readBoundedPackStream(Stream.value([1]), expectedBytes: 2),
      throwsFormatException,
    );
    await expectLater(
      readBoundedPackStream(Stream.value([1, 2, 3]),
          expectedBytes: 2, maxBytes: 2),
      throwsFormatException,
    );
    await expectLater(
      readBoundedPackStream(Stream.value([1]), expectedBytes: 0),
      throwsFormatException,
    );
  });

  test('propagates I/O errors without installing partial resources', () async {
    await expectLater(
      readBoundedPackStream(Stream<List<int>>.error(StateError('read failed')),
          expectedBytes: 1),
      throwsStateError,
    );
  });
}
