import 'dart:typed_data';

import 'package:fluxdo/services/messaging/matrix_media_memory_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Uint8List bytes(int length, int marker) =>
      Uint8List.fromList(List<int>.filled(length, marker));

  test('evicts least recently used entries by count', () {
    final cache = MatrixMediaMemoryCache(maxEntries: 2, maxBytes: 1024);
    cache.put('a', bytes(10, 1));
    cache.put('b', bytes(10, 2));

    // Touch A so B becomes the least-recently-used entry.
    expect(cache.get('a'), isNotNull);
    cache.put('c', bytes(10, 3));

    expect(cache.get('a'), isNotNull);
    expect(cache.get('b'), isNull);
    expect(cache.get('c'), isNotNull);
    expect(cache.entryCount, 2);
  });

  test('enforces total byte limit and accounts replacements', () {
    final cache = MatrixMediaMemoryCache(maxEntries: 4, maxBytes: 20);
    cache.put('a', bytes(12, 1));
    cache.put('b', bytes(8, 2));
    expect(cache.totalBytes, 20);

    cache.put('a', bytes(5, 3));
    expect(cache.totalBytes, 13);

    cache.put('c', bytes(10, 4));
    expect(cache.totalBytes, lessThanOrEqualTo(20));
    expect(cache.get('b'), isNull);
  });

  test('does not retain a single item larger than the byte budget', () {
    final cache = MatrixMediaMemoryCache(maxEntries: 4, maxBytes: 8);
    cache.put('huge', bytes(9, 1));

    expect(cache.get('huge'), isNull);
    expect(cache.entryCount, 0);
    expect(cache.totalBytes, 0);
  });

  test('clear releases all retained bytes', () {
    final cache = MatrixMediaMemoryCache(maxEntries: 4, maxBytes: 100);
    cache.put('a', bytes(20, 1));
    cache.put('b', bytes(30, 2));

    cache.clear();

    expect(cache.entryCount, 0);
    expect(cache.totalBytes, 0);
  });
}
