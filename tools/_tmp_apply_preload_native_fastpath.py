from pathlib import Path


def replace_one(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match, got {count}")
    p.write_text(text.replace(old, new, 1))


# PreloadedDataService: let the coordinator perform a native probe without
# invoking CF UI, and keep preload ahead of background traffic in the scheduler.
replace_one(
    "lib/services/preloaded_data_service.dart",
    "import 'network/discourse_dio.dart';\nimport 'network/cookie/csrf_token_service.dart';",
    "import 'network/discourse_dio.dart';\nimport 'network/flux_request_spec.dart';\nimport 'network/cookie/csrf_token_service.dart';",
)

replace_one(
    "lib/services/preloaded_data_service.dart",
    "  Future<void> ensureLoaded() async {\n    await _ensureLoaded();\n  }",
    "  Future<void> ensureLoaded({bool suppressCfChallenge = false}) async {\n    await _ensureLoaded(suppressCfChallenge: suppressCfChallenge);\n  }",
)

replace_one(
    "lib/services/preloaded_data_service.dart",
    """  Future<void> _ensureLoaded() async {
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
""",
    """  Future<void> _ensureLoaded({bool suppressCfChallenge = false}) async {
    if (_loaded) return;
    if (_loading) {
      await _waitForActiveLoad();
      if (_loaded) return;
    }
    await _loadPreloadedData(
      revision: _dataRevision,
      generation: AuthSession().generation,
      suppressCfChallenge: suppressCfChallenge,
    );
  }
""",
)

replace_one(
    "lib/services/preloaded_data_service.dart",
    """  Future<void> _loadPreloadedData({
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

  Future<void> _loadPreloadedDataInternal({
    required int revision,
    required int generation,
  }) async {
""",
    """  Future<void> _loadPreloadedData({
    required int revision,
    required int generation,
    bool suppressCfChallenge = false,
  }) async {
    if (_loading) return;
    _loading = true;
    try {
      await _loadPreloadedDataInternal(
        revision: revision,
        generation: generation,
        suppressCfChallenge: suppressCfChallenge,
      );
    } finally {
      _loading = false;
    }
  }

  Future<void> _loadPreloadedDataInternal({
    required int revision,
    required int generation,
    required bool suppressCfChallenge,
  }) async {
""",
)

replace_one(
    "lib/services/preloaded_data_service.dart",
    """          extra: {
            if (AppConstants.skipCsrfForHomeRequest) 'skipCsrf': true,
            // 诊断标注:首页 HTML 是 CF 盾高发路径,日志里需可辨识
            'requestTag': 'preload-home',
          },
""",
    """          extra: {
            if (AppConstants.skipCsrfForHomeRequest)
              FluxRequestKeys.skipCsrf: true,
            // 首页 bootstrap 决定首屏可用时间，永远排在后台请求之前。
            FluxRequestKeys.priority: FluxRequestPriority.high,
            // native probe 只负责判断正常 HTTP 是否已经可用。真的撞 CF 时
            // 立即把控制权还给 BrowserTrustCoordinator，避免先弹一次验证
            // 再创建 startup WebView，形成重复的浏览器成本。
            if (suppressCfChallenge) FluxRequestKeys.skipCfChallenge: true,
            // 诊断标注:首页 HTML 是 CF 盾高发路径,日志里需可辨识
            FluxRequestKeys.requestTag: 'preload-home',
          },
""",
)

# BrowserTrustCoordinator: native/cache first. Headless WebView is now a
# fallback after a real HTTP failure, not a prerequisite inferred from the
# presence of cf_clearance.
replace_one(
    "lib/services/browser_trust_coordinator.dart",
    """  Future<void> _ensurePreloadedInternal({required String reason}) async {
    final nativeTrusted = await _isNativePreloadTrusted();
    if (nativeTrusted) {
      _lastPreloadPath = BrowserTrustPreloadPath.native;
      _log('preload path=native reason=$reason');
      try {
        await _preload.ensureLoaded();
        _log('native preload success reason=$reason');
        _startBrowserTrustAfterPreload(reason: reason, path: 'native');
        return;
      } catch (e) {
        _log(
          'trusted native preload failed, switching to startup WebView: $e',
          level: 'warning',
        );
      }
    }

    _log('preload path=startup_webview reason=$reason');
""",
    """  Future<void> _ensurePreloadedInternal({required String reason}) async {
    // A missing/short-lived cf_clearance is not proof that the homepage needs a
    // browser. Discourse may answer native HTTP normally, and the preload cache
    // interceptor may satisfy this request without touching the network at all.
    // Probe native first and suppress CF UI for this one attempt; a genuine CF
    // rejection falls through to the startup WebView below.
    if (!_clearanceRecentlyRejected) {
      _lastPreloadPath = BrowserTrustPreloadPath.native;
      _log('preload path=native_probe reason=$reason');
      try {
        await _preload.ensureLoaded(suppressCfChallenge: true);
        _log('native preload fast path success reason=$reason');
        _startBrowserTrustAfterPreload(reason: reason, path: 'native');
        return;
      } catch (e) {
        _log(
          'native preload fast path unavailable, switching to startup WebView: $e',
          level: 'warning',
        );
      }
    } else {
      _log(
        'skip native preload probe after recent CF rejection reason=$reason',
        level: 'warning',
      );
    }

    _log('preload path=startup_webview reason=$reason');
""",
)

replace_one(
    "lib/services/browser_trust_coordinator.dart",
    """  Future<bool> _isNativePreloadTrusted() async {
    if (_clearanceRecentlyRejected) {
      _log(
        'native trust check: untrusted, clearance recently rejected by server',
        level: 'warning',
      );
      return false;
    }
    if (!_jar.isInitialized) {
      await _jar.initialize();
    }
    final clearance = await _jar.getCanonicalCookie('cf_clearance');
    if (clearance == null || clearance.value.isEmpty) {
      _log('native trust check: untrusted, no cf_clearance');
      return false;
    }
    if (!CookieJarService.matchesAppHost(clearance.domain)) {
      _log(
        'native trust check: untrusted, domain=${clearance.domain}',
        level: 'warning',
      );
      return false;
    }
    final expiresAt = clearance.expiresAt?.toLocal();
    if (expiresAt == null) {
      _log('native trust check: trusted, no expires');
      return true;
    }
    final ttl = expiresAt.difference(DateTime.now());
    final trusted = ttl >= _trustedClearanceMinTtl;
    _log(
      'native trust check: trusted=$trusted ttl=${ttl.inSeconds}s expires=${expiresAt.toIso8601String()}',
    );
    return trusted;
  }

""",
    "",
)

# The preload-only 10 minute trust threshold is gone; request-gate trust keeps
# its own shorter threshold below.
replace_one(
    "lib/services/browser_trust_coordinator.dart",
    "  static const Duration _trustedClearanceMinTtl = Duration(minutes: 10);\n",
    "",
)

# Contracts: preserve upstream loading wait semantics while covering the new
# native-first behavior and request flags.
replace_one(
    "test/services/preloaded_data_progress_test.dart",
    "    expect(body, contains('Future<void> _ensureLoaded() async'));",
    """    expect(
      body,
      contains(
        'Future<void> _ensureLoaded({bool suppressCfChallenge = false}) async',
      ),
    );""",
)

replace_one(
    "test/services/preloaded_data_progress_test.dart",
    """  test('top preload progress and progressive feed plumbing stay removed', () {
""",
    """  test('native preload probe is high priority and can suppress CF UI', () {
    expect(
      preloadSource,
      contains("import 'network/flux_request_spec.dart';"),
    );

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

  test('top preload progress and progressive feed plumbing stay removed', () {
""",
)

replace_one(
    "test/services/browser_trust_preload_latency_contract_test.dart",
    """  test('startup WebView preload avoids full-load and bootstrap waits', () {
""",
    """  test('native preload probe runs before startup WebView fallback', () {
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
    expect(body, contains('if (!_clearanceRecentlyRejected)'));
    expect(body, isNot(contains('_isNativePreloadTrusted')));
  });

  test('startup WebView preload avoids full-load and bootstrap waits', () {
""",
)

print("preload native fast-path patch applied")
