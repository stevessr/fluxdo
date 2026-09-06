import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/flux_request_spec.dart';
import 'package:fluxdo/services/network/interceptors/http_revalidation_interceptor.dart';
import 'package:fluxdo/services/network/interceptors/request_coalescing_interceptor.dart';

void main() {
  group('RequestCoalescingInterceptor', () {
    test('identical concurrent GETs share one physical request', () async {
      final adapter = _DelayedJsonAdapter();
      final dio = _testDio(adapter)
        ..interceptors.add(RequestCoalescingInterceptor())
        ..interceptors.add(RequestCoalescingFinalizerInterceptor());

      final responses = await Future.wait([
        dio.get<Map<String, dynamic>>('/latest.json'),
        dio.get<Map<String, dynamic>>('/latest.json'),
      ]);

      expect(adapter.fetchCount, 1);
      expect(responses[0].data, {'ok': true});
      expect(responses[1].data, {'ok': true});
      expect(
        responses.any((response) => response.extra['requestCoalesced'] == true),
        isTrue,
      );
    });

    test('silent polling requests are not coalesced', () async {
      final adapter = _DelayedJsonAdapter();
      final dio = _testDio(adapter)
        ..interceptors.add(RequestCoalescingInterceptor())
        ..interceptors.add(RequestCoalescingFinalizerInterceptor());

      await Future.wait([
        dio.get<Map<String, dynamic>>(
          '/poll.json',
          options: Options(extra: {FluxRequestKeys.isSilent: true}),
        ),
        dio.get<Map<String, dynamic>>(
          '/poll.json',
          options: Options(extra: {FluxRequestKeys.isSilent: true}),
        ),
      ]);

      expect(adapter.fetchCount, 2);
    });
  });

  group('HttpRevalidationInterceptor', () {
    test('expands server 304 with the cached response body', () async {
      final adapter = _RevalidationAdapter();
      final dio = _testDio(adapter)
        ..interceptors.add(HttpRevalidationInterceptor());

      final first = await dio.get<Map<String, dynamic>>('/latest.json');
      final second = await dio.get<Map<String, dynamic>>('/latest.json');

      expect(first.statusCode, 200);
      expect(first.data, {'version': 1});
      expect(adapter.fetchCount, 2);
      expect(adapter.secondIfNoneMatch, '"latest-v1"');
      expect(second.statusCode, 200);
      expect(second.data, {'version': 1});
      expect(second.extra['httpCacheRevalidated'], isTrue);
      expect(second.extra['httpCacheOriginalStatus'], 304);
    });

    test('Cache-Control no-store prevents validator reuse', () async {
      final adapter = _NoStoreAdapter();
      final dio = _testDio(adapter)
        ..interceptors.add(HttpRevalidationInterceptor());

      await dio.get<Map<String, dynamic>>('/session.json');
      await dio.get<Map<String, dynamic>>('/session.json');

      expect(adapter.fetchCount, 2);
      expect(adapter.secondIfNoneMatch, isNull);
    });

    test('successful mutation invalidates validators for the same origin', () async {
      final adapter = _MutationInvalidationAdapter();
      final dio = _testDio(adapter)
        ..interceptors.add(HttpRevalidationInterceptor());

      await dio.get<Map<String, dynamic>>('/latest.json');
      await dio.post<Map<String, dynamic>>('/posts.json', data: {'raw': 'x'});
      await dio.get<Map<String, dynamic>>('/latest.json');

      expect(adapter.getCount, 2);
      expect(adapter.secondGetIfNoneMatch, isNull);
    });

    test('Vary mismatch does not reuse another representation validator', () async {
      final adapter = _VaryAdapter();
      final dio = _testDio(adapter)
        ..interceptors.add(HttpRevalidationInterceptor());

      await dio.get<Map<String, dynamic>>(
        '/site.json',
        options: Options(headers: {'Accept-Language': 'zh-CN'}),
      );
      await dio.get<Map<String, dynamic>>(
        '/site.json',
        options: Options(headers: {'Accept-Language': 'en-US'}),
      );

      expect(adapter.fetchCount, 2);
      expect(adapter.secondIfNoneMatch, isNull);
    });
  });
}

Dio _testDio(HttpClientAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://linux.do',
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    ),
  );
  dio.httpClientAdapter = adapter;
  return dio;
}

String? _header(RequestOptions options, String name) {
  final lower = name.toLowerCase();
  for (final entry in options.headers.entries) {
    if (entry.key.toLowerCase() == lower) return entry.value?.toString();
  }
  return null;
}

class _DelayedJsonAdapter implements HttpClientAdapter {
  int fetchCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _RevalidationAdapter implements HttpClientAdapter {
  int fetchCount = 0;
  String? secondIfNoneMatch;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount++;
    if (fetchCount == 1) {
      return ResponseBody.fromString(
        '{"version":1}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
          'etag': ['"latest-v1"'],
          'cache-control': ['private, no-cache'],
        },
      );
    }

    secondIfNoneMatch = _header(options, 'if-none-match');
    return ResponseBody.fromString(
      '',
      304,
      headers: {
        'etag': ['"latest-v1"'],
        'cache-control': ['private, no-cache'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _NoStoreAdapter implements HttpClientAdapter {
  int fetchCount = 0;
  String? secondIfNoneMatch;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount++;
    if (fetchCount == 2) {
      secondIfNoneMatch = _header(options, 'if-none-match');
    }
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        'etag': ['"session-v1"'],
        'cache-control': ['no-store'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MutationInvalidationAdapter implements HttpClientAdapter {
  int getCount = 0;
  String? secondGetIfNoneMatch;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method.toUpperCase() == 'POST') {
      return ResponseBody.fromString(
        '{"ok":true}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    getCount++;
    if (getCount == 2) {
      secondGetIfNoneMatch = _header(options, 'if-none-match');
    }
    return ResponseBody.fromString(
      '{"version":$getCount}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        'etag': ['"latest-v$getCount"'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _VaryAdapter implements HttpClientAdapter {
  int fetchCount = 0;
  String? secondIfNoneMatch;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount++;
    if (fetchCount == 2) {
      secondIfNoneMatch = _header(options, 'if-none-match');
    }
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        'etag': ['"site-v$fetchCount"'],
        'vary': ['Accept-Language'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
