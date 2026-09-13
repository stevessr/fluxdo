from pathlib import Path
import subprocess

BASELINE = "af57bf67cbc3c13235064a7e47dcb6a212b20b48"


def git_show(path: str) -> str:
    return subprocess.check_output(
        ["git", "show", f"{BASELINE}:{path}"], text=True
    )


for target in (
    "lib/pages/topics_screen.dart",
    "lib/providers/topic_list/topic_list_provider.dart",
    "lib/services/preloaded_data_service.dart",
):
    Path(target).write_text(git_show(target))

path = Path("lib/services/preloaded_data_service.dart")
source = path.read_text()
source = source.replace(
    "  Future<void>? _loadingFuture;\n",
    "  bool _loading = false;\n",
    1,
)

old_refresh = """  Future<void> refresh() async {
    final oldLoading = _loadingFuture;
    _invalidateCachedData();
    if (oldLoading != null) {
      try {
        await oldLoading;
      } catch (_) {
        // 旧会话的加载失败不应阻塞新会话重新加载。
      }
    }
    await _loadPreloadedData(
      revision: _dataRevision,
      generation: AuthSession().generation,
    );
  }
"""
new_refresh = """  Future<void> refresh() async {
    await _waitForActiveLoad();
    _invalidateCachedData();
    await _loadPreloadedData(
      revision: _dataRevision,
      generation: AuthSession().generation,
    );
  }
"""
assert old_refresh in source, "refresh block changed"
source = source.replace(old_refresh, new_refresh, 1)

old_hydrate = """  Future<bool> hydrateFromHtml(String html) async {
    final oldLoading = _loadingFuture;
    _invalidateCachedData();
    if (oldLoading != null) {
      try {
        await oldLoading;
      } catch (_) {
        // 当前 HTML 快照仍可独立尝试解析。
      }
    }
    final revision = _dataRevision;
"""
new_hydrate = """  Future<bool> hydrateFromHtml(String html) async {
    await _waitForActiveLoad();
    _invalidateCachedData();
    final revision = _dataRevision;
"""
assert old_hydrate in source, "hydrate block changed"
source = source.replace(old_hydrate, new_hydrate, 1)

ensure_start = source.index("  /// 确保数据已加载\n  Future<void> _ensureLoaded() async {")
load_internal = source.index("  Future<void> _loadPreloadedDataInternal({", ensure_start)
replacement = """  Future<void> _waitForActiveLoad() async {
    while (_loading) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  /// 确保数据已加载。
  ///
  /// 等待语义与 upstream/dev 保持一致：若已有 preload 正在执行，则以
  /// 50ms 间隔等待它结束；成功后直接复用，失败后当前调用者重新加载。
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    if (_loading) {
      await _waitForActiveLoad();
      if (_loaded) return;
    }
    await _loadPreloadedData(
      revision: _dataRevision,
      generation: AuthSession().generation,
    );
  }

  /// 加载预加载数据。只允许一个加载任务占用关键路径。
  Future<void> _loadPreloadedData({
    required int revision,
    required int generation,
  }) async {
    if (_loading) return;
    _loading = true;
    try {
      await _loadPreloadedDataInternal(
        revision: revision,
        generation: generation,
      );
    } finally {
      _loading = false;
    }
  }

"""
source = source[:ensure_start] + replacement + source[load_internal:]

raw_marker = """      final siteRaw = <String, dynamic>{
        if (preloaded.containsKey('site')) 'site': preloaded['site'],
        if (preloaded.containsKey('customEmoji'))
          'customEmoji': preloaded['customEmoji'],
      };

"""
early_topic = raw_marker + """      // topic_list 不参与核心引导数据的发布，尽早启动它的单次 isolate
      // 解码/模型构建，与 currentUser/site/settings 的两组 hydration 并行。
      // 这样恢复 upstream 的“等待完整结果再展示”后，仍不会重新引入串行气泡。
      _parseTopicListFromPreloaded(
        preloaded,
        revision: revision,
        generation: generation,
      );

"""
assert raw_marker in source, "siteRaw marker changed"
source = source.replace(raw_marker, early_topic, 1)

old_groups = """      // Phase 2: use two coarse-grained workers instead of one long decoder.
      // This exposes real multicore parallelism without spawning one isolate
      // per tiny field and paying excessive isolate/copy overhead.
      final groups = await Future.wait<Map<String, dynamic>>([
        compute(_decodePreloadedGroupInIsolate, userSettingsRaw),
        compute(_decodePreloadedGroupInIsolate, siteRaw),
      ]);
"""
new_groups = """      // Phase 2: use at most two coarse-grained workers instead of one long decoder.
      // Empty groups skip isolate startup entirely; topic_list is already decoding
      // concurrently above.
      final coreDecodes = <Future<Map<String, dynamic>>>[
        if (userSettingsRaw.isNotEmpty)
          compute(_decodePreloadedGroupInIsolate, userSettingsRaw),
        if (siteRaw.isNotEmpty)
          compute(_decodePreloadedGroupInIsolate, siteRaw),
      ];
      final groups = await Future.wait<Map<String, dynamic>>(coreDecodes);
"""
assert old_groups in source, "core decode block changed"
source = source.replace(old_groups, new_groups, 1)

old_phase3 = """      // Phase 3: non-critical heavy data continues warming concurrently after
      // core hydration. Existing completers let early callers reuse the work.
      _parseTopicListFromPreloaded(
        preloaded,
        revision: revision,
        generation: generation,
      );
      if (_topicTrackingStatesRawJson != null) {
"""
new_phase3 = """      // Non-critical tracking state continues warming after core hydration.
      if (_topicTrackingStatesRawJson != null) {
"""
assert old_phase3 in source, "phase 3 block changed"
source = source.replace(old_phase3, new_phase3, 1)

assert "_loadingFuture" not in source
assert "PreloadProgress" not in source
path.write_text(source)

progress_test = Path("test/services/preloaded_data_progress_test.dart")
if progress_test.exists():
    progress_test.unlink()

wait_test = r'''import 'dart:io';

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

    final start = preloadSource.indexOf('Future<void> _ensureLoaded() async');
    final end = preloadSource.indexOf(
      'Future<void> _loadPreloadedDataInternal',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final body = preloadSource.substring(start, end);
    expect(body, contains('if (_loading)'));
    expect(body, contains('while (_loading)'));
    expect(body, contains('Duration(milliseconds: 50)'));
    expect(body, contains('if (_loaded) return;'));
  });

  test('top preload progress and progressive feed plumbing stay removed', () {
    expect(preloadSource, isNot(contains('PreloadProgress')));
    expect(preloadSource, isNot(contains('preloadProgressListenable')));
    expect(topicsSource, isNot(contains('LinearProgressIndicator')));
    expect(topicsSource, isNot(contains('preloadProgressListenable')));
    expect(providerSource, isNot(contains('progressiveTopicListListenable')));
    expect(providerSource, isNot(contains('getInitialTopicListFirstBatch')));
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
'''
Path("test/services/preloaded_data_wait_contract_test.dart").write_text(wait_test)

workflow = Path(".github/workflows/preload-startup.yaml")
workflow_text = workflow.read_text().replace(
    "test/services/preloaded_data_progress_test.dart",
    "test/services/preloaded_data_wait_contract_test.dart",
)
workflow.write_text(workflow_text)
