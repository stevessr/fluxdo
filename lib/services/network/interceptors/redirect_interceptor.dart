import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../flux_request_spec.dart';

/// 重定向拦截器
/// 手动处理 301/302/307/308 重定向，确保重定向时使用正确的 cookie。
///
/// 同 origin 跳转可以继续携带 Discourse 请求语义；跨 origin 跳转必须先
/// 去掉会话/CSRF/User API Key 等站点凭证，并关闭 Discourse 会话恢复副作用，
/// 防止论坛返回的外链重定向把当前实例身份带到第三方。
class RedirectInterceptor extends Interceptor {
  RedirectInterceptor(this._dio);

  final Dio _dio;
  static const String _redirectCountKey = '_redirectCount';
  static const int _maxRedirects = 10;

  @visibleForTesting
  static bool isSameOrigin(Uri source, Uri target) {
    return source.scheme.toLowerCase() == target.scheme.toLowerCase() &&
        source.host.toLowerCase() == target.host.toLowerCase() &&
        _effectivePort(source) == _effectivePort(target);
  }

  /// 为重定向复制 header。Cookie 无论是否同源都删除，由 CookieManager 按
  /// 新 URL 重新选择；跨 origin 再额外剥离所有站点身份与浏览器同源提示头。
  @visibleForTesting
  static Map<String, dynamic> sanitizedHeadersForRedirect(
    Map<String, dynamic> headers, {
    required bool sameOrigin,
  }) {
    final result = Map<String, dynamic>.from(headers);
    result.removeWhere((key, _) {
      final lower = key.toLowerCase();
      if (lower == 'cookie') return true;
      if (sameOrigin) return false;

      return lower == 'authorization' ||
          lower == 'proxy-authorization' ||
          lower == 'origin' ||
          lower == 'referer' ||
          lower == 'x-requested-with' ||
          lower == 'discourse-present' ||
          lower.startsWith('x-csrf-') ||
          lower.startsWith('user-api-') ||
          lower.startsWith('sec-fetch-');
    });
    return result;
  }

  @visibleForTesting
  static Map<String, dynamic> redirectExtra(
    Map<String, dynamic> extra, {
    required bool sameOrigin,
    required int redirectCount,
  }) {
    final result = Map<String, dynamic>.from(extra)
      // 当前原请求仍占用调度槽位。内部重定向必须绕过调度器，否则并发槽
      // 和速率窗口会被重定向链自己耗尽，外层响应也无法完成释放。
      ..[FluxRequestKeys.skipScheduler] = true
      ..[_redirectCountKey] = redirectCount + 1;

    if (!sameOrigin) {
      // 外部目标不是当前 Discourse 会话的一部分：不能再次自动注入 CSRF，
      // 也不能让它的 401/403/CF 页面改变当前实例 auth/session 状态。
      result[FluxRequestKeys.skipCsrf] = true;
      result[FluxRequestKeys.skipAuthCheck] = true;
      result[FluxRequestKeys.skipSessionStateSync] = true;
      result[FluxRequestKeys.skipCfChallenge] = true;
      result[FluxRequestKeys.noRecovery] = true;
    }
    return result;
  }

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    // 检查是否跳过重定向处理
    if (response.requestOptions.spec.skipRedirect) {
      return handler.next(response);
    }

    final statusCode = response.statusCode;
    if (statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 307 ||
        statusCode == 308) {
      final location = response.headers.value('location');
      if (location != null) {
        debugPrint('[Dio] Redirect $statusCode -> $location');

        final redirectCount =
            response.requestOptions.extra[_redirectCountKey] as int? ?? 0;
        if (redirectCount >= _maxRedirects) {
          return handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              error: '重定向次数超过上限 $_maxRedirects',
            ),
          );
        }

        // 解析重定向 URL
        final redirectUri = Uri.parse(location);
        final absoluteUri = redirectUri.isAbsolute
            ? redirectUri
            : response.requestOptions.uri.resolveUri(redirectUri);
        final absoluteUrl = absoluteUri.toString();
        final sameOrigin = isSameOrigin(
          response.requestOptions.uri,
          absoluteUri,
        );

        final newOptions = Options(
          method: response.requestOptions.method,
          headers: sanitizedHeadersForRedirect(
            response.requestOptions.headers,
            sameOrigin: sameOrigin,
          ),
          extra: redirectExtra(
            response.requestOptions.extra,
            sameOrigin: sameOrigin,
            redirectCount: redirectCount,
          ),
          responseType: response.requestOptions.responseType,
          validateStatus: response.requestOptions.validateStatus,
        );

        try {
          final redirectResponse = await _dio.request(
            absoluteUrl,
            options: newOptions,
          );
          return handler.resolve(redirectResponse);
        } catch (e) {
          if (e is DioException) {
            return handler.reject(e);
          }
          rethrow;
        }
      }
    }
    handler.next(response);
  }

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return switch (uri.scheme.toLowerCase()) {
      'https' => 443,
      'http' => 80,
      _ => -1,
    };
  }
}
