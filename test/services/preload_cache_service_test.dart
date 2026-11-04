import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/preload_cache_service.dart';

void main() {
  late Directory tempDirectory;
  late String? namespaceSeed;
  late bool enabled;
  late DateTime now;
  late PreloadCacheService cache;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'fluxdo-preload-cache-test-',
    );
    namespaceSeed = 'alice-session-token';
    enabled = true;
    now = DateTime.utc(2026, 9, 12, 12);
    cache = PreloadCacheService.testing(
      cacheBaseDirectory: () async => tempDirectory,
      namespaceSeed: () async => namespaceSeed,
      isEnabled: () async => enabled,
      now: () => now,
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('stores preload cache independently for each account session', () async {
    await cache.writeCurrentAccount('<html>alice</html>');
    expect(await cache.readCurrentAccount(), '<html>alice</html>');

    namespaceSeed = 'bob-session-token';
    expect(await cache.readCurrentAccount(), isNull);
    await cache.writeCurrentAccount('<html>bob</html>');
    expect(await cache.readCurrentAccount(), '<html>bob</html>');

    namespaceSeed = 'alice-session-token';
    expect(await cache.readCurrentAccount(), '<html>alice</html>');
  });

  test('token rotation never reuses the previous session cache', () async {
    await cache.writeCurrentAccount('<html>old-session</html>');

    namespaceSeed = 'alice-new-session-token';
    expect(await cache.readCurrentAccount(), isNull);
    await cache.writeCurrentAccount('<html>new-session</html>');
    expect(await cache.readCurrentAccount(), '<html>new-session</html>');

    namespaceSeed = 'alice-session-token';
    expect(await cache.readCurrentAccount(), '<html>old-session</html>');
  });

  test('expires cache at seven days and prunes it', () async {
    await cache.writeCurrentAccount('<html>fresh</html>');

    now = now.add(const Duration(days: 6, hours: 23));
    expect(await cache.readCurrentAccount(), '<html>fresh</html>');

    now = now.add(const Duration(hours: 1));
    expect(await cache.readCurrentAccount(), isNull);
  });

  test('maxAge rejects stale fast-path without deleting disk cache', () async {
    await cache.writeCurrentAccount('<html>snapshot</html>');

    now = now.add(PreloadCacheService.startupFastPathTtl);
    expect(
      await cache.readCurrentAccount(
        maxAge: PreloadCacheService.startupFastPathTtl,
      ),
      isNull,
    );

    // maxAge 只是本次新鲜度门槛；仍在 7 天硬 TTL 内的文件继续保留。
    expect(await cache.readCurrentAccount(), '<html>snapshot</html>');
  });

  test(
    'disabled experiment stops reads and writes without deleting cache',
    () async {
      await cache.writeCurrentAccount('<html>kept</html>');

      enabled = false;
      expect(await cache.readCurrentAccount(), isNull);
      await cache.writeCurrentAccount('<html>ignored</html>');

      enabled = true;
      expect(await cache.readCurrentAccount(), '<html>kept</html>');
    },
  );

  test('clearAll removes caches for every account session', () async {
    await cache.writeCurrentAccount('<html>alice</html>');
    namespaceSeed = 'bob-session-token';
    await cache.writeCurrentAccount('<html>bob</html>');

    expect(await cache.clearAll(), 2);
    expect(await cache.readCurrentAccount(), isNull);

    namespaceSeed = 'alice-session-token';
    expect(await cache.readCurrentAccount(), isNull);
  });

  test('missing auth session never uses persistent preload cache', () async {
    namespaceSeed = null;
    await cache.writeCurrentAccount('<html>anonymous</html>');
    expect(await cache.readCurrentAccount(), isNull);
    expect(await cache.clearAll(), 0);
  });

  test('sanitizes transient metadata but keeps shared session key', () async {
    const html = '''
<html>
<head>
<meta name="csrf-token" content="stale-csrf">
<meta content="seven-day-messagebus" name="shared_session_key">
</head>
<body data-sitekey="stale-turnstile">
<script type="application/json" id="data-preloaded">{"currentUser":"{\\"username\\":\\"alice\\"}"}</script>
</body>
</html>
''';

    await cache.writeCurrentAccount(html);
    final persisted = await cache.readCurrentAccount();

    expect(persisted, isNotNull);
    expect(persisted, isNot(contains('stale-csrf')));
    expect(persisted, contains('seven-day-messagebus'));
    expect(persisted, isNot(contains('stale-turnstile')));
    expect(persisted, contains('id="data-preloaded"'));
    expect(persisted, contains('alice'));
  });
}
