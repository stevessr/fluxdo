import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../preload_cache_service.dart';

const _preloadRequestTag = 'preload-home';
const _preloadCacheHitExtra = '_fluxPreloadCacheHit';

/// 首页 preload 的实验性持久缓存。
///
/// 只处理 PreloadedDataService 明确打上 `requestTag=preload-home` 的 GET，
/// 不改变其他 Discourse API 的缓存语义。命中时用本账号 7 天内的 HTML
/// 快照直接完成请求；未命中则完全沿用原来的网络/CF/重试链。
class PreloadCacheInterceptor extends Interceptor {
  PreloadCacheInterceptor({PreloadCacheService? cache})
    : _cache = cache ?? PreloadCacheService();

  final PreloadCacheService _cache;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    unawaited(_handleRequest(options, handler));
  }

  Future<void> _handleRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_isPreloadRequest(options)) {
      handler.next(options);
      return;
    }

    try {
      final cached = await _cache.readCurrentAccount();
      if (cached == null || cached.isEmpty) {
        handler.next(options);
        return;
      }

      options.extra[_preloadCacheHitExtra] = true;
      debugPrint('[PreloadCache] 命中当前账号 preload cache');
      handler.resolve(
        Response<String>(
          requestOptions: options,
          data: cached,
          statusCode: 200,
          statusMessage: 'OK (preload cache)',
          headers: Headers.fromMap({
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
            'x-fluxdo-preload-cache': ['hit'],
          }),
          extra: const {'preloadCacheHit': true},
        ),
      );
    } catch (e) {
      // cache 永远只是优化层。任何存储/平台异常都必须无条件回退网络。
      debugPrint('[PreloadCache] 读取异常，回退网络: $e');
      handler.next(options);
    }
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final options = response.requestOptions;
    final status = response.statusCode ?? 0;
    final data = response.data;
    if (_isPreloadRequest(options) &&
        options.extra[_preloadCacheHitExtra] != true &&
        status >= 200 &&
        status < 300 &&
        data is String &&
        data.isNotEmpty) {
      // 写盘不应拉长启动关键路径。失败只记日志，下一次仍可正常走网络。
      unawaited(_persist(data));
    }
    handler.next(response);
  }

  Future<void> _persist(String html) async {
    try {
      await _cache.writeCurrentAccount(html);
    } catch (e) {
      debugPrint('[PreloadCache] 后台持久化失败(忽略): $e');
    }
  }

  bool _isPreloadRequest(RequestOptions options) {
    return options.method.toUpperCase() == 'GET' &&
        options.extra['requestTag'] == _preloadRequestTag;
  }
}
