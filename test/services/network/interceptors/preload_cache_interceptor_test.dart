import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/interceptors/preload_cache_interceptor.dart';
import 'package:fluxdo/services/preload_cache_service.dart';

void main() {
  late Directory tempDirectory;
  late PreloadCacheService cache;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'fluxdo-preload-cache-interceptor-test-',
    );
    cache = PreloadCacheService.testing(
      cacheBaseDirectory: () async => tempDirectory,
      namespaceSeed: () async => 'account-session-token',
      isEnabled: () async => true,
      now: () => DateTime.utc(2026, 9, 12, 12),
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'does not persist a 200 challenge page without data-preloaded',
    () async {
      final dio = _testDio(
        _HtmlAdapter(
          '<html><title>Just a moment...</title><body>challenge</body></html>',
        ),
        cache,
      );

      final response = await dio.get<String>(
        '/',
        options: Options(extra: {'requestTag': 'preload-home'}),
      );

      expect(response.statusCode, 200);
      expect(response.data, contains('challenge'));
      expect(await cache.readCurrentAccount(), isNull);
    },
  );

  test('persists a Discourse bootstrap response with data-preloaded', () async {
    const html = '''
<html>
<body data-preloaded="{&quot;site&quot;:&quot;{}&quot;}">
Discourse
</body>
</html>
''';
    final dio = _testDio(_HtmlAdapter(html), cache);

    await dio.get<String>(
      '/',
      options: Options(extra: {'requestTag': 'preload-home'}),
    );

    expect(await _waitForCachedHtml(cache), contains('data-preloaded'));
  });
}

Dio _testDio(HttpClientAdapter adapter, PreloadCacheService cache) {
  final dio =
      Dio(
          BaseOptions(
            baseUrl: 'https://linux.do',
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
          ),
        )
        ..httpClientAdapter = adapter
        ..interceptors.add(PreloadCacheInterceptor(cache: cache));
  return dio;
}

Future<String?> _waitForCachedHtml(PreloadCacheService cache) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    final cached = await cache.readCurrentAccount();
    if (cached != null) return cached;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return null;
}

class _HtmlAdapter implements HttpClientAdapter {
  _HtmlAdapter(this.html);

  final String html;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      html,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/html; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
