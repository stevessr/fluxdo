import 'dart:collection';
import 'dart:typed_data';

/// Small in-memory LRU for authenticated Matrix media previews.
///
/// It is intentionally scoped to a [MatrixMediaService] instance rather than
/// being global so signing out or leaving the room can drop authenticated
/// content immediately. Both entry count and retained byte size are bounded.
class MatrixMediaMemoryCache {
  MatrixMediaMemoryCache({
    this.maxEntries = 32,
    this.maxBytes = 24 * 1024 * 1024,
  }) {
    if (maxEntries <= 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be positive');
    }
    if (maxBytes <= 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'must be positive');
    }
  }

  final int maxEntries;
  final int maxBytes;
  final LinkedHashMap<String, Uint8List> _entries =
      LinkedHashMap<String, Uint8List>();

  int _totalBytes = 0;

  int get entryCount => _entries.length;
  int get totalBytes => _totalBytes;

  Uint8List? get(String key) {
    final value = _entries.remove(key);
    if (value == null) return null;
    // Reinsert to make this entry most recently used.
    _entries[key] = value;
    return value;
  }

  void put(String key, Uint8List bytes) {
    if (key.isEmpty) return;

    final previous = _entries.remove(key);
    if (previous != null) {
      _totalBytes -= previous.lengthInBytes;
    }

    final size = bytes.lengthInBytes;
    if (size > maxBytes) {
      return;
    }

    _entries[key] = bytes;
    _totalBytes += size;
    _evictIfNeeded();
  }

  void remove(String key) {
    final value = _entries.remove(key);
    if (value != null) {
      _totalBytes -= value.lengthInBytes;
    }
  }

  void clear() {
    _entries.clear();
    _totalBytes = 0;
  }

  void _evictIfNeeded() {
    while (_entries.length > maxEntries || _totalBytes > maxBytes) {
      final oldestKey = _entries.keys.first;
      final oldest = _entries.remove(oldestKey);
      if (oldest != null) {
        _totalBytes -= oldest.lengthInBytes;
      }
    }
  }
}
