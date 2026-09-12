import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/preload_cache_service.dart';

void main() {
  late Directory tempDirectory;
  late String? accountId;
  late bool enabled;
  late DateTime now;
  late PreloadCacheService cache;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'fluxdo-preload-cache-test-',
    );
    accountId = 'alice';
    enabled = true;
    now = DateTime.utc(2026, 9, 12, 12);
    cache = PreloadCacheService.testing(
      cacheBaseDirectory: () async => tempDirectory,
      accountId: () async => accountId,
      isEnabled: () async => enabled,
      now: () => now,
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('stores preload cache independently for each account', () async {
    await cache.writeCurrentAccount('<html>alice</html>');
    expect(await cache.readCurrentAccount(), '<html>alice</html>');

    accountId = 'bob';
    expect(await cache.readCurrentAccount(), isNull);
    await cache.writeCurrentAccount('<html>bob</html>');
    expect(await cache.readCurrentAccount(), '<html>bob</html>');

    accountId = 'alice';
    expect(await cache.readCurrentAccount(), '<html>alice</html>');
  });

  test('expires cache at seven days and prunes it', () async {
    await cache.writeCurrentAccount('<html>fresh</html>');

    now = now.add(const Duration(days: 6, hours: 23));
    expect(await cache.readCurrentAccount(), '<html>fresh</html>');

    now = now.add(const Duration(hours: 1));
    expect(await cache.readCurrentAccount(), isNull);
  });

  test('disabled experiment stops reads and writes without deleting cache', () async {
    await cache.writeCurrentAccount('<html>kept</html>');

    enabled = false;
    expect(await cache.readCurrentAccount(), isNull);
    await cache.writeCurrentAccount('<html>ignored</html>');

    enabled = true;
    expect(await cache.readCurrentAccount(), '<html>kept</html>');
  });

  test('clearAll removes caches for every account', () async {
    await cache.writeCurrentAccount('<html>alice</html>');
    accountId = 'bob';
    await cache.writeCurrentAccount('<html>bob</html>');

    expect(await cache.clearAll(), 2);
    expect(await cache.readCurrentAccount(), isNull);

    accountId = 'alice';
    expect(await cache.readCurrentAccount(), isNull);
  });

  test('guest and missing accounts never use persistent preload cache', () async {
    accountId = null;
    await cache.writeCurrentAccount('<html>anonymous</html>');
    expect(await cache.readCurrentAccount(), isNull);

    accountId = 'guest';
    await cache.writeCurrentAccount('<html>guest</html>');
    expect(await cache.readCurrentAccount(), isNull);

    expect(await cache.clearAll(), 0);
  });

  test('strips short-lived session metadata before persistence', () async {
    const html = '''
<html>
<head>
<meta name="csrf-token" content="stale-csrf">
<meta content="stale-messagebus" name="shared_session_key">
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
    expect(persisted, isNot(contains('stale-messagebus')));
    expect(persisted, isNot(contains('stale-turnstile')));
    expect(persisted, contains('id="data-preloaded"'));
    expect(persisted, contains('alice'));
  });
}
