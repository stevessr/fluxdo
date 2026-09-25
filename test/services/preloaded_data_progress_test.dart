import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String preloadSource;
  late String topicsSource;
  late String providerSource;

  setUpAll(() {
    preloadSource = File(
      'lib/services/preloaded_data_service.dart',
    ).readAsStringSync();
    topicsSource = File('lib/pages/topics_screen.dart').readAsStringSync();
    providerSource = File(
      'lib/providers/topic_list/topic_list_provider.dart',
    ).readAsStringSync();
  });

  test('preload uses upstream loading wait semantics', () {
    expect(preloadSource, contains('bool _loading = false;'));
    expect(preloadSource, isNot(contains('_loadingFuture')));

    final start = preloadSource.indexOf(
      'Future<void> _waitForActiveLoad() async',
    );
    final end = preloadSource.indexOf(
      'Future<void> _loadPreloadedDataInternal',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final body = preloadSource.substring(start, end);
    expect(body, contains('while (_loading)'));
    expect(body, contains('Duration(milliseconds: 50)'));
    expect(
      body,
      contains(
        'Future<void> _ensureLoaded({bool suppressCfChallenge = false}) async',
      ),
    );
    expect(body, contains('if (_loading)'));
    expect(body, contains('if (_loaded) return;'));
  });

  test('native preload probe is high priority and can suppress CF UI', () {
    expect(preloadSource, contains("import 'network/flux_request_spec.dart';"));

    final start = preloadSource.indexOf(
      'Future<void> _loadPreloadedDataInternal',
    );
    final end = preloadSource.indexOf('bool _isCurrent', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final body = preloadSource.substring(start, end);
    expect(
      body,
      contains('FluxRequestKeys.priority: FluxRequestPriority.high'),
    );
    expect(body, contains('if (suppressCfChallenge)'));
    expect(body, contains('FluxRequestKeys.skipCfChallenge: true'));
    expect(body, contains("FluxRequestKeys.requestTag: 'preload-home'"));
  });

  test('bootstrap validity matches Discourse anonymous preload contract', () {
    final start = preloadSource.indexOf('bool _hasReusableBootstrapData()');
    final end = preloadSource.indexOf(
      '/// 从 HTML 中提取 discourse-base-uri',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final body = preloadSource.substring(start, end);
    expect(body, contains('_hasDiscourseSetup'));
    expect(body, contains('_siteSettings != null'));
    expect(body, contains('_site != null'));
    expect(body, isNot(contains('_currentUser != null')));
  });

  test('persistent preload source is exposed for dynamic SWR', () {
    expect(
      preloadSource,
      contains('bool get loadedFromPersistentCache =>'),
    );
    expect(
      preloadSource,
      contains("response.extra['preloadCacheHit'] == true"),
    );
    expect(
      preloadSource,
      contains('_loadedFromPersistentCache = loadedFromPersistentCache;'),
    );
  });

  test('top preload progress and progressive feed plumbing stay removed', () {
    expect(preloadSource, isNot(contains('PreloadProgress')));
    expect(preloadSource, isNot(contains('preloadProgressListenable')));
    expect(topicsSource, isNot(contains('LinearProgressIndicator')));
    expect(topicsSource, isNot(contains('preloadProgressListenable')));
    expect(providerSource, isNot(contains('progressiveTopicListListenable')));
    expect(providerSource, isNot(contains('getInitialTopicListFirstBatch')));
  });

  test('metadata scans exclude the large preload payload', () {
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
    expect(body, contains('_extractPluginCandidatesInBackground('));
    expect(body, contains('metadataHtml,'));
  });

  test('cached bootstrap topic list is revalidated without loading state', () {
    expect(providerSource, contains('loadedFromPersistentCache'));

    final start = providerSource.indexOf(
      'void _revalidatePersistentPreload',
    );
    final end = providerSource.indexOf('TopicListUpdateQuery get updateQuery', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final body = providerSource.substring(start, end);
    expect(body, contains('if (!preloaded.loadedFromPersistentCache) return;'));
    expect(body, contains('await silentRefresh();'));

    expect(
      RegExp(
        r'_revalidatePersistentPreload\(preloadedService\);',
      ).allMatches(providerSource),
      hasLength(2),
    );
  });

  test('topic list decode starts before core hydration wait', () {
    final start = preloadSource.indexOf(
      'Future<bool> _parsePreloadedDataString',
    );
    final end = preloadSource.indexOf(
      'void _parseTopicListFromPreloaded',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final body = preloadSource.substring(start, end);
    final topicStart = body.indexOf('_parseTopicListFromPreloaded(');
    final coreWait = body.indexOf(
      'await Future.wait<Map<String, dynamic>>(coreDecodes)',
    );
    expect(topicStart, greaterThanOrEqualTo(0));
    expect(coreWait, greaterThan(topicStart));
    expect(body, contains('if (userSettingsRaw.isNotEmpty)'));
    expect(body, contains('if (siteRaw.isNotEmpty)'));
  });
}
