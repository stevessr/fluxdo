from pathlib import Path


def replace_between(source: str, start: str, end: str, replacement: str) -> str:
    start_i = source.find(start)
    if start_i < 0:
        raise SystemExit(f"start marker missing: {start!r}")
    end_i = source.find(end, start_i)
    if end_i < 0:
        raise SystemExit(f"end marker missing: {end!r}")
    return source[:start_i] + replacement + source[end_i:]


decoder_path = Path("lib/services/preloaded_data_decoder.dart")
decoder = decoder_path.read_text()

old_decode = """  static Map<String, dynamic>? decode(
    String rawJson, {
    required bool htmlEntityEncoded,
  }) {
    final source = htmlEntityEncoded ? _decodeHtmlEntities(rawJson) : rawJson;

    try {
      return _decodeProjectedObject(source);
    } on FormatException {
      // Keep a compatibility fallback for unusual but valid JSON formatting.
      // The fast path is intentionally conservative: correctness wins over the
      // projection optimization if the lightweight scanner rejects a payload.
      return _decodeWithJsonDecoder(source);
    }
  }
"""
new_decode = """  static Map<String, dynamic>? decode(
    String rawJson, {
    required bool htmlEntityEncoded,
  }) {
    final projected = scan(
      rawJson,
      htmlEntityEncoded: htmlEntityEncoded,
    );
    if (projected == null) return null;
    return _decodeEagerEntries(projected);
  }

  /// Scans only retained top-level preload entries while deliberately keeping
  /// nested JSON strings raw. The service can then distribute the independent
  /// large inner payloads across a small number of worker isolates.
  static Map<String, dynamic>? scan(
    String rawJson, {
    required bool htmlEntityEncoded,
  }) {
    final source = htmlEntityEncoded ? _decodeHtmlEntities(rawJson) : rawJson;

    try {
      return _decodeProjectedObject(source);
    } on FormatException {
      // Preserve the compatibility fallback for unusual but valid JSON.
      return _decodeWithJsonDecoder(source);
    }
  }

  static Map<String, dynamic> _decodeEagerEntries(
    Map<String, dynamic> projected,
  ) {
    final result = Map<String, dynamic>.from(projected);
    for (final key in _eagerKeys) {
      if (!result.containsKey(key)) continue;
      final value = result[key];
      if (value is! String) continue;
      try {
        result[key] = jsonDecode(value);
      } catch (_) {
        // Preserve a non-JSON string exactly as the previous decoder did.
      }
    }
    return result;
  }
"""
if old_decode not in decoder:
    raise SystemExit("decoder decode block marker missing")
decoder = decoder.replace(old_decode, new_decode, 1)

old_projected = """      if (_retainedKeys.contains(key)) {
        dynamic value = jsonDecode(source.substring(valueStart, valueEnd));
        if (_eagerKeys.contains(key) && value is String) {
          try {
            value = jsonDecode(value);
          } catch (_) {
            // Match the previous implementation: an inner value that happens
            // to be a non-JSON string is preserved unchanged.
          }
        }
        result[key] = value;
      }
"""
new_projected = """      if (_retainedKeys.contains(key)) {
        // Decode only the outer value here. Nested preload JSON strings stay
        // raw so independent groups can be hydrated concurrently afterwards.
        result[key] = jsonDecode(source.substring(valueStart, valueEnd));
      }
"""
if old_projected not in decoder:
    raise SystemExit("decoder projected block marker missing")
decoder = decoder.replace(old_projected, new_projected, 1)

old_fallback = """    final result = <String, dynamic>{};
    for (final key in _retainedKeys) {
      if (!outer.containsKey(key)) continue;
      dynamic value = outer[key];
      if (_eagerKeys.contains(key) && value is String) {
        try {
          value = jsonDecode(value);
        } catch (_) {
          // Preserve the raw value for compatibility.
        }
      }
      result[key] = value;
    }
    return result;
"""
new_fallback = """    final result = <String, dynamic>{};
    for (final key in _retainedKeys) {
      if (!outer.containsKey(key)) continue;
      result[key] = outer[key];
    }
    return result;
"""
if old_fallback not in decoder:
    raise SystemExit("decoder fallback block marker missing")
decoder = decoder.replace(old_fallback, new_fallback, 1)
decoder_path.write_text(decoder)

service_path = Path("lib/services/preloaded_data_service.dart")
service = service_path.read_text()

parse_method = r'''  Future<bool> _parsePreloadedDataString(
    String dataString, {
    required bool htmlEntityEncoded,
    required int revision,
    required int generation,
  }) async {
    try {
      // Phase 1: scan the outer preload object once. Nested JSON strings stay
      // raw so the large independent inner payloads can use multiple CPU cores.
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

      // Phase 2: use two coarse-grained workers instead of one long decoder.
      // This exposes real multicore parallelism without spawning one isolate
      // per tiny field and paying excessive isolate/copy overhead.
      final groups = await Future.wait<Map<String, dynamic>>([
        compute(_decodePreloadedGroupInIsolate, userSettingsRaw),
        compute(_decodePreloadedGroupInIsolate, siteRaw),
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

      // Phase 3: non-critical heavy data continues warming concurrently after
      // core hydration. Existing completers let early callers reuse the work.
      _parseTopicListFromPreloaded(
        preloaded,
        revision: revision,
        generation: generation,
      );
      if (_topicTrackingStatesRawJson != null) {
        unawaited(_decodeTopicTrackingStatesAsync());
      }
      return true;
    } catch (e) {
      debugPrint('[PreloadedData] JSON 解析失败: $e');
      return false;
    }
  }

'''
service = replace_between(
    service,
    "  Future<bool> _parsePreloadedDataString(",
    "  /// 从预加载数据中解析话题列表",
    parse_method,
)

old_helper = """Map<String, dynamic>? _decodePreloadedJsonInIsolate(List<String> input) {
  return PreloadedDataDecoder.decode(
    input[0],
    htmlEntityEncoded: input.length > 1 && input[1] == 'entity',
  );
}
"""
new_helper = """Map<String, dynamic>? _scanPreloadedJsonInIsolate(List<String> input) {
  return PreloadedDataDecoder.scan(
    input[0],
    htmlEntityEncoded: input.length > 1 && input[1] == 'entity',
  );
}

Map<String, dynamic> _decodePreloadedGroupInIsolate(
  Map<String, dynamic> rawGroup,
) {
  final result = <String, dynamic>{};
  for (final entry in rawGroup.entries) {
    final value = entry.value;
    if (value is String) {
      try {
        result[entry.key] = jsonDecode(value);
        continue;
      } catch (_) {
        // Preserve unusual non-JSON strings for compatibility.
      }
    }
    result[entry.key] = value;
  }
  return result;
}
"""
if old_helper not in service:
    raise SystemExit("service preload helper marker missing")
service = service.replace(old_helper, new_helper, 1)
service_path.write_text(service)

test_path = Path("test/services/preloaded_data_decoder_test.dart")
test = test_path.read_text()
marker = "    test('handles braces, commas and escapes inside skipped strings', () {\n"
extra = """    test('scan keeps eager inner JSON raw for parallel hydration', () {
      final raw = jsonEncode({
        'currentUser': jsonEncode({'id': 42}),
        'siteSettings': jsonEncode({'chat_enabled': true}),
        'site': jsonEncode({'categories': <Object>[]}),
        'customEmoji': jsonEncode(<Object>[]),
        'topicList': jsonEncode({'topic_list': {'topics': <Object>[]}}),
      });

      final scanned = PreloadedDataDecoder.scan(
        raw,
        htmlEntityEncoded: false,
      );

      expect(scanned, isNotNull);
      expect(scanned!['currentUser'], isA<String>());
      expect(scanned['siteSettings'], isA<String>());
      expect(scanned['site'], isA<String>());
      expect(scanned['customEmoji'], isA<String>());
      expect(scanned['topicList'], isA<String>());

      final decoded = PreloadedDataDecoder.decode(
        raw,
        htmlEntityEncoded: false,
      );
      expect(decoded!['currentUser'], {'id': 42});
      expect(decoded['siteSettings'], {'chat_enabled': true});
      expect(decoded['site'], isA<Map<String, dynamic>>());
    });

"""
if marker not in test:
    raise SystemExit("test insertion marker missing")
test = test.replace(marker, extra + marker, 1)
test_path.write_text(test)
