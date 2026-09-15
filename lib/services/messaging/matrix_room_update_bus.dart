import 'dart:async';

/// Lightweight broadcast signal for Matrix rooms whose `/sync` timeline has
/// changed.
///
/// The bus deliberately carries only room IDs. Raw `/sync` timeline events stay
/// out of the paged history LRU, while active room UIs can request a fresh
/// `/messages` page only when their room actually received a timeline delta.
class MatrixRoomUpdateBus {
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  bool _disposed = false;

  Stream<String> watch(String roomId) {
    if (roomId.isEmpty) return const Stream<String>.empty();
    return _controller.stream.where((changedRoomId) => changedRoomId == roomId);
  }

  void publish(String roomId) {
    if (_disposed || roomId.isEmpty) return;
    _controller.add(roomId);
  }

  void publishAll(Iterable<String> roomIds) {
    if (_disposed) return;
    for (final roomId in roomIds) {
      publish(roomId);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_controller.close());
  }
}
