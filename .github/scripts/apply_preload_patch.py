from pathlib import Path

SERVICE_PATH = Path("lib/services/preloaded_data_service.dart")
TEST_PATH = Path("test/services/preloaded_data_progress_test.dart")


def splice(text: str, start_marker: str, end_marker: str, replacement: str) -> str:
    start = text.index(start_marker)
    end = text.index(end_marker, start)
    return text[:start] + replacement + text[end:]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


service = SERVICE_PATH.read_text()

progress_replacement = '''enum PreloadPhase {
  idle,
  requesting,
  scanning,
  hydratingCore,
  decodingTopics,
  parsingTopics,
  complete,
  failed,
}

@immutable
class PreloadProgress {
  const PreloadProgress({
    required this.phase,
    this.parsedTopics = 0,
    this.totalTopics = 0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.completedWorkUnits = 0,
    this.totalWorkUnits = 0,
  });

  const PreloadProgress.idle()
    : phase = PreloadPhase.idle,
      parsedTopics = 0,
      totalTopics = 0,
      receivedBytes = 0,
      totalBytes = 0,
      completedWorkUnits = 0,
      totalWorkUnits = 0;

  final PreloadPhase phase;
  final int parsedTopics;
  final int totalTopics;
  final int receivedBytes;
  final int totalBytes;
  final int completedWorkUnits;
  final int totalWorkUnits;

  bool get isActive =>
      phase == PreloadPhase.requesting ||
      phase == PreloadPhase.scanning ||
      phase == PreloadPhase.hydratingCore ||
      phase == PreloadPhase.decodingTopics ||
      phase == PreloadPhase.parsingTopics;

  /// 整个 preload 流程的确定进度。
  ///
  /// 首页下载占 2%~45%。下载完成后的 45%~100% 不再按固定阶段硬切，
  /// 而是按实际 preload payload、核心 JSON、topic_list JSON 与 topic
  /// 模型批次的工作量累计。并行任务只增加自己对应的份额，避免固定卡在
  /// 某个百分比以及最后突然跳满。
  double? get fraction {
    switch (phase) {
      case PreloadPhase.idle:
        return 0.0;
      case PreloadPhase.requesting:
        final networkFraction = totalBytes > 0
            ? (receivedBytes / totalBytes).clamp(0.0, 1.0).toDouble()
            : 0.0;
        return 0.02 + networkFraction * 0.43;
      case PreloadPhase.scanning:
      case PreloadPhase.hydratingCore:
      case PreloadPhase.decodingTopics:
      case PreloadPhase.parsingTopics:
        if (totalWorkUnits <= 0) return 0.45;
        final workFraction = (completedWorkUnits / totalWorkUnits)
            .clamp(0.0, 1.0)
            .toDouble();
        return 0.45 + workFraction * 0.55;
      case PreloadPhase.complete:
        return 1.0;
      case PreloadPhase.failed:
        return null;
    }
  }

  int get percent => ((fraction ?? 0.0) * 100).round();

  int? get downloadPercent {
    if (phase != PreloadPhase.requesting || totalBytes <= 0) return null;
    return ((receivedBytes / totalBytes).clamp(0.0, 1.0) * 100).round();
  }

  String get semanticsLabel {
    switch (phase) {
      case PreloadPhase.idle:
        return '预加载未开始';
      case PreloadPhase.requesting:
        final networkPercent = downloadPercent;
        return networkPercent == null
            ? '正在获取预加载数据'
            : '正在获取预加载数据 · 下载 $networkPercent%';
      case PreloadPhase.scanning:
        return '正在扫描预加载数据';
      case PreloadPhase.hydratingCore:
        return '正在解析核心数据';
      case PreloadPhase.decodingTopics:
        return '正在解码话题数据';
      case PreloadPhase.parsingTopics:
        return totalTopics > 0
            ? '正在解析话题 $parsedTopics / $totalTopics'
            : '正在解析话题';
      case PreloadPhase.complete:
        return '预加载完成';
      case PreloadPhase.failed:
        return '预加载失败';
    }
  }
}

class _PreloadWorkTracker {
  _PreloadWorkTracker({
    required this.revision,
    required this.generation,
    required this.totalUnits,
    required this.completedUnits,
    required this.phase,
  });

  final int revision;
  final int generation;
  final int totalUnits;
  int completedUnits;
  PreloadPhase phase;
  int parsedTopics = 0;
  int totalTopics = 0;
}

int _rawPreloadWorkUnits(Object? value) {
  if (value == null) return 0;
  if (value is String) return value.isEmpty ? 1 : value.length;
  return 1;
}

int _preloadGroupWorkUnits(Map<String, dynamic> group) {
  var total = 0;
  for (final value in group.values) {
    total += _rawPreloadWorkUnits(value);
  }
  return total;
}

int _preloadTopicWorkUnits(Map<String, dynamic> preloaded) {
  for (final key in const ['topicList', 'topic_list', 'latest']) {
    if (preloaded.containsKey(key)) {
      return _rawPreloadWorkUnits(preloaded[key]);
    }
  }
  return 0;
}

'''
service = splice(
    service,
    "enum PreloadPhase {",
    "/// 预加载数据服务",
    progress_replacement,
)

service = replace_once(
    service,
    "  static const int _topicParseBatchSize = 24;\n",
    "  static const int _topicParseBatchSize = 24;\n"
    "  static const int _topicParseConcurrency = 2;\n",
    "topic concurrency constant",
)

progress_marker = '''  void _setPreloadProgress(PreloadProgress progress) {
    _preloadProgress.value = progress;
  }
'''
progress_helpers = progress_marker + '''
  void _publishPreloadWork(
    _PreloadWorkTracker tracker, {
    required PreloadPhase phase,
    int? parsedTopics,
    int? totalTopics,
  }) {
    if (!_isCurrent(tracker.revision, tracker.generation)) return;
    if (phase.index > tracker.phase.index &&
        phase != PreloadPhase.complete &&
        phase != PreloadPhase.failed) {
      tracker.phase = phase;
    }
    if (parsedTopics != null) tracker.parsedTopics = parsedTopics;
    if (totalTopics != null) tracker.totalTopics = totalTopics;

    final completed = tracker.completedUnits >= tracker.totalUnits;
    _setPreloadProgress(
      PreloadProgress(
        phase: completed ? PreloadPhase.complete : tracker.phase,
        parsedTopics: tracker.parsedTopics,
        totalTopics: tracker.totalTopics,
        completedWorkUnits: tracker.completedUnits,
        totalWorkUnits: tracker.totalUnits,
      ),
    );
  }

  void _advancePreloadWork(
    _PreloadWorkTracker tracker, {
    required int units,
    required PreloadPhase phase,
    int? parsedTopics,
    int? totalTopics,
  }) {
    if (!_isCurrent(tracker.revision, tracker.generation)) return;
    final next = tracker.completedUnits + (units < 0 ? 0 : units);
    tracker.completedUnits = next > tracker.totalUnits
        ? tracker.totalUnits
        : next;
    _publishPreloadWork(
      tracker,
      phase: phase,
      parsedTopics: parsedTopics,
      totalTopics: totalTopics,
    );
  }
'''
service = replace_once(
    service,
    progress_marker,
    progress_helpers,
    "progress helper insertion",
)

service = replace_once(
    service,
    "    _setPreloadProgress(const PreloadProgress(phase: PreloadPhase.decoding));\n",
    "    _setPreloadProgress(const PreloadProgress(phase: PreloadPhase.scanning));\n",
    "scanning phase",
)

parse_function = '''  Future<bool> _parsePreloadedDataString(
    String dataString, {
    required bool htmlEntityEncoded,
    required int revision,
    required int generation,
  }) async {
    try {
      // Phase 1: scan the outer preload object once. Nested JSON strings stay
      // raw so large independent payloads can be decoded in parallel.
      final preloaded = await compute(_scanPreloadedJsonInIsolate, [
        dataString,
        if (htmlEntityEncoded) 'entity',
      ]);
      if (preloaded == null) {
        debugPrint('[PreloadedData] 预加载 JSON 解析为空');
        return false;
      }
      if (!_isCurrent(revision, generation)) return false;

      final userSettingsRaw = <String, dynamic>{
        if (preloaded.containsKey('currentUser'))
          'currentUser': preloaded['currentUser'],
        if (preloaded.containsKey('siteSettings'))
          'siteSettings': preloaded['siteSettings'],
        if (preloaded.containsKey('topicTrackingStateMeta'))
          'topicTrackingStateMeta': preloaded['topicTrackingStateMeta'],
      };
      final siteRaw = <String, dynamic>{
        if (preloaded.containsKey('site')) 'site': preloaded['site'],
        if (preloaded.containsKey('customEmoji'))
          'customEmoji': preloaded['customEmoji'],
      };

      final scanUnits = dataString.isEmpty ? 1 : dataString.length;
      final userSettingsUnits = _preloadGroupWorkUnits(userSettingsRaw);
      final siteUnits = _preloadGroupWorkUnits(siteRaw);
      final topicUnits = _preloadTopicWorkUnits(preloaded);
      // topic_list 的 raw JSON 解码和模型构建都需要完整遍历一次，分别
      // 计入同等工作量；核心组则按各自 raw payload 大小计权。
      final totalWorkUnits =
          scanUnits +
          userSettingsUnits +
          siteUnits +
          (topicUnits * 2) +
          1;
      final tracker = _PreloadWorkTracker(
        revision: revision,
        generation: generation,
        totalUnits: totalWorkUnits,
        completedUnits: scanUnits,
        phase: PreloadPhase.hydratingCore,
      );
      _publishPreloadWork(tracker, phase: PreloadPhase.hydratingCore);

      // Start topic_list immediately after the outer scan. Previously this waited
      // for both core decode workers, leaving a serial bubble on startup.
      final hasTopicList = _parseTopicListFromPreloaded(
        preloaded,
        revision: revision,
        generation: generation,
        tracker: tracker,
        topicDecodeWorkUnits: topicUnits,
        topicModelWorkUnits: topicUnits,
      );

      Future<Map<String, dynamic>> decodeCoreGroup(
        Map<String, dynamic> rawGroup,
        int workUnits,
      ) async {
        if (rawGroup.isEmpty) return const <String, dynamic>{};
        final decoded = await compute(_decodePreloadedGroupInIsolate, rawGroup);
        _advancePreloadWork(
          tracker,
          units: workUnits,
          phase: PreloadPhase.hydratingCore,
        );
        return decoded;
      }

      // Two coarse-grained workers keep site/settings parallel, while empty groups
      // avoid paying an isolate startup at all.
      final groups = await Future.wait<Map<String, dynamic>>([
        if (userSettingsRaw.isNotEmpty)
          decodeCoreGroup(userSettingsRaw, userSettingsUnits),
        if (siteRaw.isNotEmpty) decodeCoreGroup(siteRaw, siteUnits),
      ]);
      if (!_isCurrent(revision, generation)) return false;

      final hydrated = <String, dynamic>{};
      for (final group in groups) {
        hydrated.addAll(group);
      }

      if (hydrated.containsKey('currentUser')) {
        _currentUser = hydrated['currentUser'] as Map<String, dynamic>;
        debugPrint(
          '[PreloadedData] currentUser 解析成功: id=${_currentUser?['id']}, '
          'unread_notifications=${_currentUser?['unread_notifications']}, '
          'all_unread=${_currentUser?['all_unread_notifications_count']}',
        );
      }

      if (hydrated.containsKey('siteSettings')) {
        _siteSettings = hydrated['siteSettings'] as Map<String, dynamic>;

        final reactionsStr =
            _siteSettings?['discourse_reactions_enabled_reactions'] as String?;
        if (reactionsStr != null && reactionsStr.isNotEmpty) {
          _enabledReactions = reactionsStr.split('|');
          debugPrint('[PreloadedData] reactions: $_enabledReactions');
        }

        final pollingUrl = _siteSettings?['long_polling_base_url'] as String?;
        if (pollingUrl != null && pollingUrl.isNotEmpty && pollingUrl != '/') {
          _longPollingBaseUrl = pollingUrl.endsWith('/')
              ? pollingUrl.substring(0, pollingUrl.length - 1)
              : pollingUrl;
          debugPrint(
            '[PreloadedData] longPollingBaseUrl: $_longPollingBaseUrl',
          );
        }
      }

      if (hydrated.containsKey('site')) {
        _site = hydrated['site'] as Map<String, dynamic>;
        debugPrint(
          '[PreloadedData] site 解析成功, categories=${(_site?['categories'] as List?)?.length ?? 0}',
        );
      }

      if (hydrated.containsKey('topicTrackingStateMeta')) {
        _topicTrackingStateMeta =
            hydrated['topicTrackingStateMeta'] as Map<String, dynamic>;
        debugPrint(
          '[PreloadedData] topicTrackingStateMeta: $_topicTrackingStateMeta',
        );
      }

      if (preloaded.containsKey('topicTrackingStates')) {
        final value = preloaded['topicTrackingStates'];
        if (value is List) {
          _topicTrackingStates = value.cast<Map<String, dynamic>>();
          _topicTrackingStatesRawJson = null;
          debugPrint(
            '[PreloadedData] topicTrackingStates: ${_topicTrackingStates?.length ?? 0} items',
          );
        } else if (value is String && value.isNotEmpty) {
          _topicTrackingStatesRawJson = value;
          _topicTrackingStates = null;
          debugPrint('[PreloadedData] topicTrackingStates 后台预热');
        }
      }

      if (hydrated.containsKey('customEmoji')) {
        _customEmoji = (hydrated['customEmoji'] as List)
            .cast<Map<String, dynamic>>();
        debugPrint(
          '[PreloadedData] customEmoji: ${_customEmoji?.length ?? 0} items',
        );
      }

      // Keep one tiny final unit so progress cannot report 100% before decoded
      // core maps have actually been published to the service.
      _advancePreloadWork(
        tracker,
        units: 1,
        phase: hasTopicList
            ? PreloadPhase.parsingTopics
            : PreloadPhase.hydratingCore,
      );

      // Non-critical tracking state continues after core hydration. Existing
      // completers let an early caller reuse the same background work.
      if (_topicTrackingStatesRawJson != null) {
        unawaited(_decodeTopicTrackingStatesAsync());
      }
      return true;
    } catch (e) {
      debugPrint('[PreloadedData] JSON 解析失败: $e');
      if (_isCurrent(revision, generation)) {
        _setPreloadProgress(const PreloadProgress(phase: PreloadPhase.failed));
      }
      return false;
    }
  }

'''
service = splice(
    service,
    "  Future<bool> _parsePreloadedDataString(",
    "  /// 从预加载数据中解析话题列表",
    parse_function,
)

topic_entry = '''  bool _parseTopicListFromPreloaded(
    Map<String, dynamic> preloaded, {
    required int revision,
    required int generation,
    required _PreloadWorkTracker tracker,
    required int topicDecodeWorkUnits,
    required int topicModelWorkUnits,
  }) {
    final possibleKeys = ['topicList', 'topic_list', 'latest'];

    for (final key in possibleKeys) {
      if (!preloaded.containsKey(key)) continue;
      try {
        final value = preloaded[key];
        if (value is String) {
          _decodeTopicListAsync(
            value,
            revision: revision,
            generation: generation,
            tracker: tracker,
            topicDecodeWorkUnits: topicDecodeWorkUnits,
            topicModelWorkUnits: topicModelWorkUnits,
          );
          return true;
        } else if (value is Map) {
          _topicListData = Map<String, dynamic>.from(value);
          _advancePreloadWork(
            tracker,
            units: topicDecodeWorkUnits,
            phase: PreloadPhase.decodingTopics,
          );
        }

        if (_topicListData != null) {
          final topicsCount =
              (_topicListData?['topic_list']?['topics'] as List?)?.length ??
              (_topicListData?['topics'] as List?)?.length ??
              0;
          debugPrint(
            '[PreloadedData] topic_list 解析成功 (key=$key), topics=$topicsCount',
          );
          _parseTopicListResponseAsync(
            _topicListData!,
            revision: revision,
            generation: generation,
            tracker: tracker,
            topicModelWorkUnits: topicModelWorkUnits,
          );
          return true;
        }
      } catch (e) {
        debugPrint('[PreloadedData] 解析 $key 失败: $e');
      }
    }
    return false;
  }

'''
service = splice(
    service,
    "  bool _parseTopicListFromPreloaded(",
    "  void _prepareTopicListCompleters() {",
    topic_entry,
)

topic_pipeline = '''  void _decodeTopicListAsync(
    String rawJson, {
    required int revision,
    required int generation,
    required _PreloadWorkTracker tracker,
    required int topicDecodeWorkUnits,
    required int topicModelWorkUnits,
  }) {
    _prepareTopicListCompleters();
    _publishPreloadWork(tracker, phase: PreloadPhase.decodingTopics);
    unawaited(() async {
      try {
        final data = await compute(_decodeTopicListJsonInIsolate, rawJson);
        if (!_isCurrent(revision, generation)) return;
        if (data == null) {
          _setPreloadProgress(
            const PreloadProgress(phase: PreloadPhase.failed),
          );
          _completeTopicListWithNull();
          return;
        }
        _advancePreloadWork(
          tracker,
          units: topicDecodeWorkUnits,
          phase: PreloadPhase.decodingTopics,
        );
        _topicListData = data;
        await _parseTopicListResponseInBatches(
          data,
          revision: revision,
          generation: generation,
          tracker: tracker,
          topicModelWorkUnits: topicModelWorkUnits,
        );
      } catch (e) {
        debugPrint('[PreloadedData] 异步解析 topic_list 失败: $e');
        if (_isCurrent(revision, generation)) {
          _setPreloadProgress(
            const PreloadProgress(phase: PreloadPhase.failed),
          );
          _completeTopicListWithNull();
        }
      }
    }());
  }

  void _parseTopicListResponseAsync(
    Map<String, dynamic> data, {
    required int revision,
    required int generation,
    required _PreloadWorkTracker tracker,
    required int topicModelWorkUnits,
  }) {
    _prepareTopicListCompleters();
    unawaited(
      _parseTopicListResponseInBatches(
        data,
        revision: revision,
        generation: generation,
        tracker: tracker,
        topicModelWorkUnits: topicModelWorkUnits,
      ),
    );
  }

  Future<void> _parseTopicListResponseInBatches(
    Map<String, dynamic> data, {
    required int revision,
    required int generation,
    required _PreloadWorkTracker tracker,
    required int topicModelWorkUnits,
  }) async {
    try {
      final rawTopicList = data['topic_list'];
      if (rawTopicList is! Map) {
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

      final topicList = Map<String, dynamic>.from(rawTopicList);
      final rawUsers = data['users'] as List<dynamic>? ?? const <dynamic>[];
      final rawTopics =
          topicList['topics'] as List<dynamic>? ?? const <dynamic>[];
      final moreTopicsUrl = topicList['more_topics_url'] as String?;
      final total = rawTopics.length;
      final accumulated = <Topic>[];
      final seenTopicIds = <int>{};

      _publishPreloadWork(
        tracker,
        phase: PreloadPhase.parsingTopics,
        parsedTopics: 0,
        totalTopics: total,
      );

      if (total == 0) {
        _publishTopicListSnapshot(
          TopicListResponse(
            topics: const <Topic>[],
            moreTopicsUrl: moreTopicsUrl,
          ),
          finalSnapshot: true,
        );
        _advancePreloadWork(
          tracker,
          units: topicModelWorkUnits,
          phase: PreloadPhase.parsingTopics,
          parsedTopics: 0,
          totalTopics: 0,
        );
        return;
      }

      final windowSize = _topicParseBatchSize * _topicParseConcurrency;
      for (
        var windowStart = 0;
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
          for (final start in starts)
            compute(
              _parseTopicBatchInIsolate,
              <String, dynamic>{
                'users': rawUsers,
                'topics': rawTopics.sublist(
                  start,
                  (start + _topicParseBatchSize) < total
                      ? start + _topicParseBatchSize
                      : total,
                ),
              },
            ),
        ]);
        if (!_isCurrent(revision, generation)) return;

        for (var index = 0; index < starts.length; index++) {
          final start = starts[index];
          final requestedEnd = start + _topicParseBatchSize;
          final end = requestedEnd < total ? requestedEnd : total;
          final batch = batches[index];

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

        if (windowStart + windowSize < total) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    } catch (e) {
      debugPrint('[PreloadedData] 分批解析 TopicListResponse 失败: $e');
      if (_isCurrent(revision, generation)) {
        _setPreloadProgress(const PreloadProgress(phase: PreloadPhase.failed));
        _completeTopicListWithNull();
      }
    }
  }

'''
service = splice(
    service,
    "  void _decodeTopicListAsync(",
    "  void _publishTopicListSnapshot(",
    topic_pipeline,
)

SERVICE_PATH.write_text(service)

test = TEST_PATH.read_text()
test = replace_once(
    test,
    "      const decoding = PreloadProgress(phase: PreloadPhase.decoding);\n",
    "      const scanning = PreloadProgress(phase: PreloadPhase.scanning);\n"
    "      const halfWork = PreloadProgress(\n"
    "        phase: PreloadPhase.hydratingCore,\n"
    "        completedWorkUnits: 50,\n"
    "        totalWorkUnits: 100,\n"
    "      );\n",
    "test scanning fixture",
)
test = replace_once(
    test,
    "      expect(decoding.isActive, isTrue);\n"
    "      expect(decoding.fraction, 0.55);\n",
    "      expect(scanning.isActive, isTrue);\n"
    "      expect(scanning.fraction, 0.45);\n"
    "      expect(halfWork.fraction, closeTo(0.725, 0.000001));\n",
    "test scanning expectations",
)
test = replace_once(
    test,
    "        totalTopics: 24,\n"
    "      );\n"
    "      const overflow = PreloadProgress(\n"
    "        phase: PreloadPhase.parsingTopics,\n"
    "        parsedTopics: 30,\n"
    "        totalTopics: 24,\n"
    "      );\n\n"
    "      expect(half.fraction, 0.8);",
    "        totalTopics: 24,\n"
    "        completedWorkUnits: 50,\n"
    "        totalWorkUnits: 100,\n"
    "      );\n"
    "      const overflow = PreloadProgress(\n"
    "        phase: PreloadPhase.parsingTopics,\n"
    "        parsedTopics: 30,\n"
    "        totalTopics: 24,\n"
    "        completedWorkUnits: 100,\n"
    "        totalWorkUnits: 100,\n"
    "      );\n\n"
    "      expect(half.fraction, closeTo(0.725, 0.000001));",
    "test work weighted progress",
)
test = replace_once(
    test,
    "      expect(serviceSource, contains('_topicParseBatchSize = 24'));\n",
    "      expect(serviceSource, contains('_topicParseBatchSize = 24'));\n"
    "      expect(serviceSource, contains('_topicParseConcurrency = 2'));\n"
    "      expect(serviceSource, contains('Future.wait<List<Topic>>'));\n"
    "      expect(serviceSource, contains('completedWorkUnits'));\n",
    "source contracts",
)
TEST_PATH.write_text(test)
