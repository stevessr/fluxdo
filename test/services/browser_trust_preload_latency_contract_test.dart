import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File(
      'lib/services/browser_trust_coordinator.dart',
    ).readAsStringSync();
  });

  test('startup WebView preload avoids full-load and bootstrap waits', () {
    final start = source.indexOf('Future<bool> _hydratePreloadThroughWebView');
    final end = source.indexOf('Future<void> _navigateToHome', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final preloadBody = source.substring(start, end);
    expect(preloadBody, isNot(contains('.runOnController(')));
    expect(preloadBody, isNot(contains('getCookieDiagnosticsForRequest')));
    expect(preloadBody, isNot(contains('_waitForLoad(')));
    expect(preloadBody, contains('await _readPreloadedSnapshot('));
    final syncStart = preloadBody.indexOf(
      'final cookieSyncFuture = _syncCookiesFromController(c);',
    );
    final hydrateStart = preloadBody.indexOf(
      'final hydrateFuture = hasSnapshot',
    );
    final hydrateWait = preloadBody.indexOf(
      'final hydrated = await hydrateFuture;',
    );
    final syncWait = preloadBody.indexOf('await cookieSyncFuture;');
    expect(syncStart, greaterThanOrEqualTo(0));
    expect(hydrateStart, greaterThan(syncStart));
    expect(hydrateWait, greaterThan(hydrateStart));
    expect(syncWait, greaterThan(hydrateWait));
    expect(
      preloadBody,
      contains('if (platformViewStarted && io.Platform.isWindows)'),
    );
  });

  test('preload snapshot polling is eager first and bounded later', () {
    final start = source.indexOf('Future<String?> _readPreloadedSnapshot');
    final end = source.indexOf(
      'Future<void> _syncCookiesFromController',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final body = source.substring(start, end);
    expect(body, contains('Duration(milliseconds: 25)'));
    expect(body, contains('Future<void>.delayed(pollDelay)'));
    expect(body, contains('currentDelayMs < 125 ? currentDelayMs * 2 : 250'));
    expect(
      body,
      isNot(
        contains('Future<void>.delayed(const Duration(milliseconds: 250))'),
      ),
    );
  });

  test('hydrated WebView preload settles browser trust in background', () {
    expect(
      source,
      contains(
        "_startBrowserTrustAfterPreload(reason: reason, path: 'webview');",
      ),
    );
    expect(source, contains("reason: '\$reason:\${path}_preload_settle'"));
    expect(source, contains('final synced = await ensureBrowserTrust('));
  });
}
