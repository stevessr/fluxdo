import 'dart:async';

import 'package:dio/dio.dart';

import '../matrix_client_service.dart';

typedef MatrixRoomSyncPull = Future<List<MatrixRoomSummary>> Function({
  required Duration timeout,
  CancelToken? cancelToken,
});
typedef MatrixRoomsListener = void Function(List<MatrixRoomSummary> rooms);
typedef MatrixRoomSyncErrorListener = void Function(Object error);

/// Drives cancellable Matrix `/sync` long polling without coupling the loop to
/// Flutter widgets. A single controller owns at most one in-flight request.
///
/// The first non-blocking sync stays in [MatrixClientService.loadRooms]; once a
/// `next_batch` token exists this controller can keep asking for deltas with a
/// server-side timeout. [stop] invalidates the generation and cancels the
/// current request, so late responses cannot mutate UI state after logout,
/// backgrounding, or a manual full-sync reset.
class MatrixRoomSyncController {
  MatrixRoomSyncController({
    required MatrixRoomSyncPull pull,
    required MatrixRoomsListener onRooms,
    MatrixRoomSyncErrorListener? onError,
    this.longPollTimeout = const Duration(seconds: 30),
    this.retryDelay = const Duration(seconds: 3),
  }) : _pull = pull,
       _onRooms = onRooms,
       _onError = onError;

  final MatrixRoomSyncPull _pull;
  final MatrixRoomsListener _onRooms;
  final MatrixRoomSyncErrorListener? _onError;
  final Duration longPollTimeout;
  final Duration retryDelay;

  bool _running = false;
  bool _disposed = false;
  int _generation = 0;
  CancelToken? _activeCancelToken;

  bool get isRunning => _running && !_disposed;

  void start() {
    if (_disposed || _running) return;
    _running = true;
    final generation = ++_generation;
    unawaited(_run(generation));
  }

  void stop() {
    if (_disposed && !_running && _activeCancelToken == null) return;
    _running = false;
    _generation++;
    _activeCancelToken?.cancel('Matrix live sync stopped');
    _activeCancelToken = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
  }

  Future<void> _run(int generation) async {
    while (!_disposed && _running && generation == _generation) {
      final cancelToken = CancelToken();
      _activeCancelToken = cancelToken;
      try {
        final rooms = await _pull(
          timeout: longPollTimeout,
          cancelToken: cancelToken,
        );
        if (_disposed || !_running || generation != _generation) return;
        _onRooms(List<MatrixRoomSummary>.unmodifiable(rooms));
      } catch (error) {
        if (cancelToken.isCancelled ||
            _disposed ||
            !_running ||
            generation != _generation) {
          return;
        }
        _onError?.call(error);
        if (retryDelay > Duration.zero) {
          await Future<void>.delayed(retryDelay);
          if (_disposed || !_running || generation != _generation) return;
        }
      } finally {
        if (identical(_activeCancelToken, cancelToken)) {
          _activeCancelToken = null;
        }
      }
    }
  }
}
