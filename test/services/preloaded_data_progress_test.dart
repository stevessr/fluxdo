import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';

void main() {
  group('PreloadProgress', () {
    test('uses determinate overall progress before topic parsing starts', () {
      const requesting = PreloadProgress(phase: PreloadPhase.requesting);
      const halfDownloaded = PreloadProgress(
        phase: PreloadPhase.requesting,
        receivedBytes: 50,
        totalBytes: 100,
      );
      const scanning = PreloadProgress(phase: PreloadPhase.scanning);
      const halfWork = PreloadProgress(
        phase: PreloadPhase.hydratingCore,
        completedWorkUnits: 50,
        totalWorkUnits: 100,
      );

      expect(requesting.isActive, isTrue);
      expect(requesting.fraction, 0.02);
      expect(halfDownloaded.downloadPercent, 50);
      expect(halfDownloaded.fraction, closeTo(0.235, 0.000001));
      expect(scanning.isActive, isTrue);
      expect(scanning.fraction, 0.45);
      expect(halfWork.fraction, closeTo(0.725, 0.000001));
    });

    test('reports and clamps parsed topic progress', () {
      const half = PreloadProgress(
        phase: PreloadPhase.parsingTopics,
        parsedTopics: 12,
        totalTopics: 24,
        completedWorkUnits: 50,
        totalWorkUnits: 100,
      );
      const overflow = PreloadProgress(
        phase: PreloadPhase.parsingTopics,
        parsedTopics: 30,
        totalTopics: 24,
        completedWorkUnits: 100,
        totalWorkUnits: 100,
      );

      expect(half.fraction, closeTo(0.725, 0.000001));
      expect(half.semanticsLabel, contains('12 / 24'));
      expect(overflow.fraction, 1.0);
    });

    test('complete and failed phases stop the active indicator', () {
      const complete = PreloadProgress(phase: PreloadPhase.complete);
      const failed = PreloadProgress(phase: PreloadPhase.failed);

      expect(complete.isActive, isFalse);
      expect(complete.fraction, 1.0);
      expect(failed.isActive, isFalse);
      expect(failed.fraction, isNull);
    });
  });

  group('progressive preload source contracts', () {
    late String serviceSource;
    late String providerSource;
    late String screenSource;

    setUpAll(() {
      serviceSource = File(
        'lib/services/preloaded_data_service.dart',
      ).readAsStringSync();
      providerSource = File(
        'lib/providers/topic_list/topic_list_provider.dart',
      ).readAsStringSync();
      screenSource = File('lib/pages/topics_screen.dart').readAsStringSync();
    });

    test('topic list decoding stays incremental and generation guarded', () {
      expect(serviceSource, contains('_topicParseBatchSize = 24'));
      expect(serviceSource, contains('_topicParseConcurrency = 2'));
      expect(serviceSource, contains('Future.wait<List<Topic>>'));
      expect(serviceSource, contains('completedWorkUnits'));
      expect(serviceSource, contains('getInitialTopicListFirstBatch'));
      expect(serviceSource, contains('progressiveTopicListListenable'));
      expect(serviceSource, contains('rawTopics.sublist(start, end)'));
      expect(
        serviceSource,
        contains('_publishTopicListSnapshot(snapshot, finalSnapshot: isFinal)'),
      );
      expect(
        serviceSource,
        contains('if (!_isCurrent(revision, generation)) return;'),
      );
    });

    test('provider preserves live topics and closes progressive listeners', () {
      expect(
        providerSource,
        contains('_mergeProgressivePreloadedSnapshot(snapshot)'),
      );
      expect(providerSource, contains('scheduleMicrotask'));
      expect(providerSource, contains('detachProgressiveListener'));
      expect(providerSource, contains('Future<void>.delayed(Duration.zero'));
      expect(providerSource, contains('if (topicIds.add(topic.id)) topic'));
    });

    test('top progress overlay does not rebuild the workspace tree', () {
      expect(screenSource, contains('ValueListenableBuilder<PreloadProgress>'));
      expect(screenSource, contains('child: workspace'));
      expect(screenSource, contains('LinearProgressIndicator'));
      expect(screenSource, contains('progress.percent'));
      expect(screenSource, contains('minHeight: 4'));
      expect(serviceSource, contains('onReceiveProgress:'));
    });
  });
}
