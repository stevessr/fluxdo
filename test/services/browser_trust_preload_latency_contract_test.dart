import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/services/browser_trust_coordinator.dart')
        .readAsStringSync();
  });

  test('native preload probe runs before startup WebView fallback', () {
    final start = source.indexOf('Future<void> _ensurePreloadedInternal');
    final end = source.indexOf('void _startBrowserTrustAfterPreload', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final body = source.substring(start, end);
    final nativeProbe = body.indexOf(
      '_preload.ensureLoaded(suppressCfChallenge: true)',
    );
    final webViewFallback = body.indexOf('_hydratePreloadThroughWebView(');
    expect(nativeProbe, greaterThanOrEqualTo(0));
    expect(webViewFallback, greaterThan(nativeProbe));
    expect(
      body,
      contains('if (!_clearanceRecentlyRejected || proactiveVerified)'),
    );
    expect(body, isNot(contains('_isNativePreloadTrusted')));
  });

  test('startup WebView preload reads snapshot before conditional bootstrap', () {
    final start = source.indexOf('Future<bool> _hydratePreloadThroughWebView');
    final end = source.indexOf('Future<void> _navigateToHome', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final body = source.substring(start, end);
    // 仍不等待整页 onLoadStop；HTML 快照优先完成首屏 hydration。
    expect(body, isNot(contains('_waitForLoad(')));
    final snapshot = body.indexOf('final html = await _readPreloadedSnapshot(');
    final hydrate = body.indexOf('await _preload.hydrateFromHtml(html)');
    final token = body.indexOf('final tToken = await _jar.getTToken();');
    final bootstrap = body.indexOf('.runOnController(');
    expect(snapshot, greaterThanOrEqualTo(0));
    expect(hydrate, greaterThan(snapshot));
    expect(token, greaterThan(hydrate));
    expect(bootstrap, greaterThan(token));

    // 当账号带 _t 时才维护 WebView 的会话；bootstrap 必须可取消。
    expect(body, contains('if (tToken != null && tToken.isNotEmpty)'));
    expect(body, contains('cancellationSignal: cancelled'));
    expect(body, contains('if (cancellation.isCancelled || !lease.isCurrent)'));
    expect(body, contains('await _syncCookiesFromController(c, generation)'));
    expect(body, contains("names: const {'_rt'}"));
    expect(body, contains('if (bootstrapped && hasRuntimeCookie)'));
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

  test('persistent CF keeper stays off preload critical path', () {
    final start = source.indexOf('void _startClearanceRefreshNow');
    final end = source.indexOf('Future<void> _ensurePreloadedInternal', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final body = source.substring(start, end);
    expect(source, contains('_clearanceRefreshStartupDelay'));
    expect(
      source,
      contains(
        'static const Duration _clearanceRefreshStartupDelay = '
        'Duration(seconds: 5);',
      ),
    );
    expect(body, contains('Timer(_clearanceRefreshStartupDelay'));
    expect(
      body,
      contains('_activePreload != null || _activeBrowserTrust != null'),
    );
    expect(body, contains('_preload.currentUserSync == null'));

    final scheduled = body.indexOf('Timer(_clearanceRefreshStartupDelay');
    final keeperStart = body.indexOf('CfClearanceRefreshService().start()');
    expect(scheduled, greaterThanOrEqualTo(0));
    expect(keeperStart, greaterThan(scheduled));
  });
}
