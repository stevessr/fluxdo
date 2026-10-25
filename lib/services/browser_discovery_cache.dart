import 'dart:async';

/// In-memory, process-scoped discovery cache. Concurrent callers share a scan.
///
/// Results are never written to disk. The expiry timer releases the entries
/// after [ttl], even when the picker is not opened again.
class BrowserDiscoveryCache<T> {
  BrowserDiscoveryCache({
    required this.load,
    this.ttl = const Duration(hours: 1),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final Future<T> Function() load;
  final Duration ttl;
  final DateTime Function() clock;

  T? _value;
  DateTime? _expiresAt;
  Future<T>? _inFlight;
  Timer? _expiryTimer;
  int _generation = 0;

  Future<T> get({bool forceRefresh = false}) {
    if (forceRefresh) invalidate();

    final expiry = _expiresAt;
    if (expiry != null && clock().isBefore(expiry)) {
      return Future<T>.value(_value as T);
    }

    // At expiry, discard the old icons/list before starting another scan.
    if (expiry != null) {
      _value = null;
      _expiresAt = null;
      _expiryTimer?.cancel();
      _expiryTimer = null;
    }

    final running = _inFlight;
    if (running != null) return running;

    final generation = _generation;
    final future = _load(generation);
    _inFlight = future;
    // A completion handler with an error callback avoids an unhandled
    // secondary Future if discovery fails. Failures are not cached.
    future.then(
      (_) {
        if (identical(_inFlight, future)) _inFlight = null;
      },
      onError: (Object _, StackTrace __) {
        if (identical(_inFlight, future)) _inFlight = null;
      },
    );
    return future;
  }

  Future<T> _load(int generation) async {
    final result = await load();
    if (generation == _generation) {
      _value = result;
      _expiresAt = clock().add(ttl);
      _expiryTimer?.cancel();
      _expiryTimer = Timer(ttl, () {
        if (generation == _generation) invalidate();
      });
    }
    return result;
  }

  /// Also available when a browser install/uninstall needs an immediate rescan.
  void invalidate() {
    _generation++;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _expiresAt = null;
    _value = null;
    _inFlight = null;
  }
}
