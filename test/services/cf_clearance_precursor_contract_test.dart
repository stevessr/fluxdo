import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File(
      'lib/services/cf_clearance_refresh_service.dart',
    ).readAsStringSync();
  });

  test('Precursor keeps a real same-origin browser session before fallback', () {
    final originLoad = source.indexOf('WebUri(_browserSessionUrl)');
    final fallback = source.indexOf(
      '_writeTurnstileHtml(controller, _buildTurnstileHtml(sitekey))',
    );

    expect(originLoad, greaterThanOrEqualTo(0));
    expect(fallback, greaterThan(originLoad));
    expect(source, contains('/cdn-cgi/challenge-platform/'));
    expect(source, contains("performance.getEntriesByType('resource')"));
  });

  test('Precursor rotation only accepts a newly observed exact clearance', () {
    expect(source, contains('_knownBrowserClearanceValues'));
    expect(source, contains('_browserClearanceBaselineReady'));
    expect(
      source,
      contains(
        'final freshValues = observed.difference(_knownBrowserClearanceValues);',
      ),
    );
    expect(source, contains('if (freshValues.length == 1)'));
    expect(
      source,
      contains('acceptValues: freshBrowserClearance == null'),
    );
    expect(
      source,
      contains("await _syncAndCheckCookies('browser_session_ready', gen);"),
    );
    expect(source, contains('if (!isInitialOriginLoad)'));

    // Do not add a broad authority bypass: historical CHIPS/Turnstile
    // variants must still be rejected by the existing sticky-incumbent rule.
    expect(source, isNot(contains('allowCfClearanceRotation')));
  });
}
