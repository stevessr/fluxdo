import 'dart:async';
import 'dart:io';

import '../lib/services/browser_discovery_cache.dart';

Future<void> main() async {
  var checks = 0;
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
    checks++;
  }

  var reads = 0;
  final gate = Completer<List<int>>();
  final cache = BrowserDiscoveryCache<List<int>>(
    load: () {
      reads++;
      return gate.future;
    },
  );

  final first = cache.get();
  final simultaneous = cache.get();
  check(identical(first, simultaneous), 'Concurrent scans share one Future');
  check(reads == 1, 'Only one scan starts');
  gate.complete([1, 2, 3]);
  check(identical(await first, await simultaneous), 'Same discovery result');
  check(identical(await cache.get(), await first), 'Cached result reused');
  check(reads == 1, 'No scan on cache hit');

  cache.invalidate();
  check(reads == 1, 'Invalidation itself does not rescan');
  await cache.get();
  check(reads == 2, 'Invalidation forces next scan');

  var refreshes = 0;
  final shortCache = BrowserDiscoveryCache<int>(
    ttl: const Duration(milliseconds: 60),
    load: () async => ++refreshes,
  );
  check(await shortCache.get() == 1, 'First scan');
  check(await shortCache.get() == 1, 'TTL reuse');
  await Future<void>.delayed(const Duration(milliseconds: 100));
  check(await shortCache.get() == 2, 'Expired cache cleared automatically');

  var failures = 0;
  final failureCache = BrowserDiscoveryCache<int>(
    load: () async {
      if (failures++ == 0) throw StateError('test discovery failure');
      return 7;
    },
  );
  try {
    await failureCache.get();
    throw StateError('Expected failure');
  } on StateError catch (e) {
    check(e.message == 'test discovery failure', 'Failure passed to caller');
  }
  check(await failureCache.get() == 7, 'Failure is not cached');
  check(failures == 2, 'Retry starts a new discovery');

  final invalidated = Completer<int>();
  var started = 0;
  final raceCache = BrowserDiscoveryCache<int>(
    load: () => ++started == 1 ? invalidated.future : Future.value(10),
  );
  final old = raceCache.get();
  raceCache.invalidate();
  check(await raceCache.get() == 10, 'New generation bypasses stale scan');
  invalidated.complete(1);
  check(await old == 1, 'Original caller still receives completed scan');
  check(await raceCache.get() == 10, 'Stale scan never overwrites new cache');

  cache.invalidate();
  shortCache.invalidate();
  failureCache.invalidate();
  raceCache.invalidate();
  stdout.writeln('PASS: $checks browser cache checks');
}
