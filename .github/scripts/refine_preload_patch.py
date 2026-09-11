from pathlib import Path

service_path = Path('lib/services/preloaded_data_service.dart')
test_path = Path('test/services/preloaded_data_progress_test.dart')
service = service_path.read_text()

old_fallback = '''      if (rawTopicList is! Map) {
        final result = await compute(_parseTopicListInIsolate, data);
        if (!_isCurrent(revision, generation)) return;
        final total = result?.topics.length ?? 0;
        if (result != null) {
          _publishTopicListSnapshot(result, finalSnapshot: true);
        } else {
          _completeTopicListWithNull();
        }
        _advancePreloadWork(
          tracker,
          units: topicModelWorkUnits,
          phase: PreloadPhase.parsingTopics,
          parsedTopics: total,
          totalTopics: total,
        );
        return;
      }
'''
new_fallback = '''      if (rawTopicList is! Map) {
        final result = await compute(_parseTopicListInIsolate, data);
        if (!_isCurrent(revision, generation)) return;
        final total = result.topics.length;
        _publishTopicListSnapshot(result, finalSnapshot: true);
        _advancePreloadWork(
          tracker,
          units: topicModelWorkUnits,
          phase: PreloadPhase.parsingTopics,
          parsedTopics: total,
          totalTopics: total,
        );
        return;
      }
'''
if service.count(old_fallback) != 1:
    raise SystemExit('fallback block mismatch')
service = service.replace(old_fallback, new_fallback, 1)

start = service.index('      final windowSize = _topicParseBatchSize * _topicParseConcurrency;')
end = service.index('    } catch (e) {', start)
old_pipeline = service[start:end]
new_pipeline = '''      Future<List<Topic>> parseBatch(int start) {
        final requestedEnd = start + _topicParseBatchSize;
        final end = requestedEnd < total ? requestedEnd : total;
        return compute(
          _parseTopicBatchInIsolate,
          <String, dynamic>{
            'users': rawUsers,
            'topics': rawTopics.sublist(start, end),
          },
        );
      }

      void publishBatch(int start, int end, List<Topic> batch) {
        for (final topic in batch) {
          if (seenTopicIds.add(topic.id)) accumulated.add(topic);
        }

        final snapshot = TopicListResponse(
          topics: List<Topic>.unmodifiable(accumulated),
          moreTopicsUrl: moreTopicsUrl,
        );
        final isFinal = end >= total;
        _publishTopicListSnapshot(snapshot, finalSnapshot: isFinal);

        final previousWork = topicModelWorkUnits * start ~/ total;
        final currentWork = topicModelWorkUnits * end ~/ total;
        _advancePreloadWork(
          tracker,
          units: currentWork - previousWork,
          phase: PreloadPhase.parsingTopics,
          parsedTopics: end,
          totalTopics: total,
        );
      }

      // Keep time-to-first-content optimal: the first 24 topics are parsed alone
      // and published immediately. Only the remaining batches fan out two-wide.
      final firstEnd = _topicParseBatchSize < total
          ? _topicParseBatchSize
          : total;
      final firstBatch = await parseBatch(0);
      if (!_isCurrent(revision, generation)) return;
      publishBatch(0, firstEnd, firstBatch);
      if (firstEnd >= total) return;

      await Future<void>.delayed(Duration.zero);
      final windowSize = _topicParseBatchSize * _topicParseConcurrency;
      for (
        var windowStart = firstEnd;
        windowStart < total;
        windowStart += windowSize
      ) {
        final starts = <int>[];
        for (
          var start = windowStart;
          start < total && starts.length < _topicParseConcurrency;
          start += _topicParseBatchSize
        ) {
          starts.add(start);
        }

        final batches = await Future.wait<List<Topic>>([
          for (final start in starts) parseBatch(start),
        ]);
        if (!_isCurrent(revision, generation)) return;

        for (var index = 0; index < starts.length; index++) {
          final batchStart = starts[index];
          final requestedEnd = batchStart + _topicParseBatchSize;
          final batchEnd = requestedEnd < total ? requestedEnd : total;
          publishBatch(batchStart, batchEnd, batches[index]);
        }

        if (windowStart + windowSize < total) {
          await Future<void>.delayed(Duration.zero);
        }
      }
'''
service = service[:start] + new_pipeline + service[end:]
service_path.write_text(service)

test = test_path.read_text()
test = test.replace(
    "      expect(serviceSource, contains('rawTopics.sublist(start, end)'));\n",
    "      expect(serviceSource, contains('rawTopics.sublist(start, end)'));\n"
    "      expect(serviceSource, contains('final firstBatch = await parseBatch(0)'));\n"
    "      expect(serviceSource, contains('for (final start in starts) parseBatch(start)'));\n",
    1,
)
test_path.write_text(test)
