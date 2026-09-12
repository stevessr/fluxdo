import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../preload_cache_service.dart';

const _preloadRequestTag = 'preload-home';
const _preloadCacheHitExtra = '_fluxPreloadCacheHit';
final _dataPreloadedScriptPattern = RegExp(
  r'''<script\b[^>]*\bid=["']data-preloaded["'][^>]*>''',
  caseSensitive: false,
);
final _dataPreloadedAttributePattern = RegExp(
  r'''\bdata-preloaded\s*=''',
  caseSensitive: false,
);

/// 首页 preload 的实验性持久缓存。
///
/// 只处理 PreloadedDataService 明确打上 `requestTag=preload-home` 的 GET，
/// 不改变其他 Discourse API 的缓存语义。很新的命中会直接完成请求；较旧
/// 但仍在磁盘硬 TTL 内的快照不会在正常联网启动时短路网络，以免把动态的
/// currentUser / tracking state / topic list 长时间当成最新数据。
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
      final cached = await _cache.readCurrentAccount(
        maxAge: PreloadCacheService.startupFastPathTtl,
      );
      if (cached == null || cached.isEmpty || !_isReusablePreloadHtml(cached)) {
        handler.next(options);
        return;
      }

      options.extra[_preloadCacheHitExtra] = true;
      debugPrint('[PreloadCache] 命中当前账号新鲜 preload cache');
      handler.resolve(
        Response<String>(
          requestOptions: options,
          data: cached,
          statusCode: 200,
          statusMessage: 'OK (preload cache)',
          headers: Headers.fromMap({
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
            'x-fluxdo-preload-cache': ['fresh-hit'],
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
        data.isNotEmpty &&
        _isReusablePreloadHtml(data)) {
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

  bool _isReusablePreloadHtml(String html) {
    // 当前 Discourse 使用 <script id="data-preloaded" type="application/json">；
    // 老版本/部分主题仍可能使用 data-preloaded 属性。两种形态都要识别。
    // Cloudflare challenge / 登录页即使返回 200，也不会命中这两个 bootstrap
    // 标记，因此不会被误写成可复用首页快照。
    return _dataPreloadedScriptPattern.hasMatch(html) ||
        _dataPreloadedAttributePattern.hasMatch(html);
  }
}
