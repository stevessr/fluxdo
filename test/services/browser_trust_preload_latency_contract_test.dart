import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File(
      'lib/services/browser_trust_coordinator.dart',
    ).readAsStringSync();
  });

  test('startup WebView preload does not await session bootstrap', () {
    final start = source.indexOf(
      'Future<bool> _hydratePreloadThroughWebView',
    );
    final end = source.indexOf(
      'Future<void> _navigateToHome',
      start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final preloadBody = source.substring(start, end);
    expect(preloadBody, isNot(contains('.runOnController(')));
    expect(
      preloadBody,
      isNot(contains('getCookieDiagnosticsForRequest')),
    );
    expect(preloadBody, contains('await _preload.hydrateFromHtml(html)'));
  });

  test('hydrated WebView preload settles browser trust in background', () {
    expect(
      source,
      contains(
        "_startBrowserTrustAfterPreload(reason: reason, path: 'webview');",
      ),
    );
    expect(
      source,
      contains("reason: '\$reason:\${path}_preload_settle'"),
    );
    expect(
      source,
      contains('final synced = await ensureBrowserTrust('),
    );
  });
}
