from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    source = path.read_text()
    if old not in source:
        raise SystemExit(f"missing block: {label}")
    path.write_text(source.replace(old, new, 1))


browser = Path('lib/services/browser_trust_coordinator.dart')
source = browser.read_text()

old = '''      _log(
        'startup WebView snapshot captured=${html != null && html.isNotEmpty}, '
        'syncing cookies reason=$reason',
      );
      await _syncCookiesFromController(c);
      if (cancellation.isCancelled) return false;

      final hydrated =
          html != null &&
          html.isNotEmpty &&
          await _preload.hydrateFromHtml(html);
      if (cancellation.isCancelled) return false;
'''
new = '''      final hasSnapshot = html != null && html.isNotEmpty;
      _log(
        'startup WebView snapshot captured=$hasSnapshot, '
        'syncing cookies + hydrating reason=$reason',
      );

      // Cookie boundary sync and preload JSON hydration are independent once the
      // document-start snapshot has been captured. Start both immediately and
      // wait for both before disposing the WebView; this turns two serial chunks
      // on the startup critical path into max(sync, hydrate) instead of their sum.
      final cookieSyncFuture = _syncCookiesFromController(c);
      final hydrateFuture = hasSnapshot
          ? _preload.hydrateFromHtml(html)
          : Future<bool>.value(false);
      final hydrated = await hydrateFuture;
      await cookieSyncFuture;
      if (cancellation.isCancelled) return false;
'''
if old not in source:
    raise SystemExit('missing browser hydrate block')
source = source.replace(old, new, 1)

old = '''  }) async {
    final deadline = DateTime.now().add(_domSnapshotTimeout);
    while (!cancellation.isCancelled && DateTime.now().isBefore(deadline)) {
'''
new = '''  }) async {
    final deadline = DateTime.now().add(_domSnapshotTimeout);
    // The preload element usually appears very early in HTML parsing. Poll
    // aggressively for the first few hundred milliseconds, then back off to the
    // old 250ms cadence so slow/CF pages do not spam the JS bridge.
    var pollDelay = const Duration(milliseconds: 25);
    while (!cancellation.isCancelled && DateTime.now().isBefore(deadline)) {
'''
if old not in source:
    raise SystemExit('missing snapshot loop header')
source = source.replace(old, new, 1)

old = '''      await Future.any<void>([
        Future<void>.delayed(const Duration(milliseconds: 250)),
        cancellation.whenCancelled,
      ]);
'''
new = '''      await Future.any<void>([
        Future<void>.delayed(pollDelay),
        cancellation.whenCancelled,
      ]);
      final currentDelayMs = pollDelay.inMilliseconds;
      pollDelay = Duration(
        milliseconds: currentDelayMs < 125 ? currentDelayMs * 2 : 250,
      );
'''
if old not in source:
    raise SystemExit('missing snapshot fixed delay')
source = source.replace(old, new, 1)
browser.write_text(source)


preload = Path('lib/services/preloaded_data_service.dart')
source = preload.read_text()

old = '''    String? dataString;
    var htmlEntityEncoded = false;
'''
new = '''    String? dataString;
    var htmlEntityEncoded = false;
    int? payloadStart;
    int? payloadEnd;
'''
if old not in source:
    raise SystemExit('missing preload payload vars')
source = source.replace(old, new, 1)

old = '''      if (end > start) {
        dataString = html.substring(start, end);
      }
'''
new = '''      if (end > start) {
        dataString = html.substring(start, end);
        payloadStart = start;
        payloadEnd = end;
      }
'''
if old not in source:
    raise SystemExit('missing script payload extraction')
source = source.replace(old, new, 1)

old = '''      dataString = match.group(1)!;
      htmlEntityEncoded = true;
    }

    final parseFuture = _parsePreloadedDataString(
'''
new = '''      dataString = match.group(1)!;
      htmlEntityEncoded = true;
      payloadStart = match.start;
      payloadEnd = match.end;
    }

    final parseFuture = _parsePreloadedDataString(
'''
if old not in source:
    raise SystemExit('missing legacy payload extraction')
source = source.replace(old, new, 1)

old = '''    // These small HTML metadata scans run while the preload isolate is decoding.
    _extractCsrfTokenFromHtml(html);
    _extractSharedSessionKeyFromHtml(html);
    _extractTurnstileSitekeyFromHtml(html);
    _extractBaseUriFromHtml(html);
    _extractCdnUrlFromHtml(html);

    final parsed = await parseFuture;
'''
new = '''    // Do not rescan the usually huge preload JSON for every tiny metadata
    // regexp. Remove only the payload bytes once, preserving the surrounding
    // document so meta/setup/plugin tags are still discoverable. This cuts UI
    // isolate string scanning substantially on large home payloads.
    final metadataHtml = payloadStart != null && payloadEnd != null
        ? '${html.substring(0, payloadStart)}${html.substring(payloadEnd)}'
        : html;

    // These small HTML metadata scans run while the preload isolate is decoding.
    _extractCsrfTokenFromHtml(metadataHtml);
    _extractSharedSessionKeyFromHtml(metadataHtml);
    _extractTurnstileSitekeyFromHtml(metadataHtml);
    _extractBaseUriFromHtml(metadataHtml);
    _extractCdnUrlFromHtml(metadataHtml);

    final parsed = await parseFuture;
'''
if old not in source:
    raise SystemExit('missing metadata scan block')
source = source.replace(old, new, 1)

old = '''    if (parsed) {
      _extractPluginCandidatesInBackground(
        html,
        revision: revision,
        generation: generation,
      );
    }
'''
new = '''    if (parsed && metadataHtml.contains('/plugins/')) {
      // WebView preload snapshots intentionally contain only data-preloaded,
      // metas and discourse setup, so they should not pay for a pointless
      // plugin-discovery isolate. Native full HTML still discovers plugins, but
      // scans the compact payload-free view instead of duplicating the JSON.
      _extractPluginCandidatesInBackground(
        metadataHtml,
        revision: revision,
        generation: generation,
      );
    }
'''
if old not in source:
    raise SystemExit('missing plugin background block')
source = source.replace(old, new, 1)
preload.write_text(source)


browser_test = Path('test/services/browser_trust_preload_latency_contract_test.dart')
source = browser_test.read_text()
old = '''    expect(preloadBody, contains('await _readPreloadedSnapshot('));
    expect(preloadBody, contains('await _syncCookiesFromController(c)'));
    expect(preloadBody, contains('await _preload.hydrateFromHtml(html)'));
    expect(
'''
new = '''    expect(preloadBody, contains('await _readPreloadedSnapshot('));
    final syncStart = preloadBody.indexOf(
      'final cookieSyncFuture = _syncCookiesFromController(c);',
    );
    final hydrateStart = preloadBody.indexOf('final hydrateFuture = hasSnapshot');
    final hydrateWait = preloadBody.indexOf(
      'final hydrated = await hydrateFuture;',
    );
    final syncWait = preloadBody.indexOf('await cookieSyncFuture;');
    expect(syncStart, greaterThanOrEqualTo(0));
    expect(hydrateStart, greaterThan(syncStart));
    expect(hydrateWait, greaterThan(hydrateStart));
    expect(syncWait, greaterThan(hydrateWait));
    expect(
'''
if old not in source:
    raise SystemExit('missing browser test expectations')
source = source.replace(old, new, 1)

insert_before = '''  test('hydrated WebView preload settles browser trust in background', () {
'''
addition = '''  test('preload snapshot polling is eager first and bounded later', () {
    final start = source.indexOf('Future<String?> _readPreloadedSnapshot');
    final end = source.indexOf('Future<void> _syncCookiesFromController', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final body = source.substring(start, end);
    expect(body, contains('Duration(milliseconds: 25)'));
    expect(body, contains('Future<void>.delayed(pollDelay)'));
    expect(body, contains('currentDelayMs < 125 ? currentDelayMs * 2 : 250'));
    expect(
      body,
      isNot(contains('Future<void>.delayed(const Duration(milliseconds: 250))')),
    );
  });

'''
if insert_before not in source:
    raise SystemExit('missing browser test insertion point')
source = source.replace(insert_before, addition + insert_before, 1)
browser_test.write_text(source)


preload_test = Path('test/services/preloaded_data_progress_test.dart')
source = preload_test.read_text()
insert_before = '''  test('topic list decode starts before core hydration wait', () {
'''
addition = '''  test('metadata scans exclude the large preload payload', () {
    final start = preloadSource.indexOf(
      'Future<bool> _parsePreloadedDataFromHtml',
    );
    final end = preloadSource.indexOf('void _extractCsrfTokenFromHtml', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final body = preloadSource.substring(start, end);
    expect(body, contains('int? payloadStart;'));
    expect(body, contains('int? payloadEnd;'));
    expect(body, contains('final metadataHtml ='));
    expect(body, contains('_extractCsrfTokenFromHtml(metadataHtml)'));
    expect(body, contains('_extractCdnUrlFromHtml(metadataHtml)'));
    expect(body, contains("parsed && metadataHtml.contains('/plugins/')"));
    expect(body, contains('_extractPluginCandidatesInBackground(\n        metadataHtml,'));
  });

'''
if insert_before not in source:
    raise SystemExit('missing preload test insertion point')
source = source.replace(insert_before, addition + insert_before, 1)
preload_test.write_text(source)
