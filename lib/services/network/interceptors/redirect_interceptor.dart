import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../config/discourse_instance_runtime.dart';
import '../cookie/app_cookie_manager.dart';

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

  /// Only requests inside the active instance's origin AND relative root may
  /// retain Discourse credentials. A sibling application on the same host is
  /// not the same authentication boundary as a sub-path Discourse deployment.
  @visibleForTesting
  static bool isSameDiscourseScope(Uri source, Uri target) =>
      isSameOrigin(source, target) &&
      DiscourseInstanceRuntime.containsUri(
        source,
        allowDefaultSubdomains: false,
      ) &&
      DiscourseInstanceRuntime.containsUri(
        target,
        allowDefaultSubdomains: false,
      );

  /// HTTP redirect semantics: 303 becomes GET (except HEAD), while 301/302
  /// change POST into GET; 307/308 and other methods retain their method/body.
  @visibleForTesting
  static String redirectedMethod(int statusCode, String originalMethod) {
    final method = originalMethod.toUpperCase();
    if (statusCode == 303 && method != 'HEAD') return 'GET';
    if ((statusCode == 301 || statusCode == 302) && method == 'POST') {
      return 'GET';
    }
    return method;
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
          lower == 'x-shared-session-key' ||
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
        statusCode == 303 ||
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

        // Reject malformed / non-HTTP redirects before they enter the shared
        // client. In particular, a Location must not be able to introduce
        // userinfo credentials or an unsupported protocol.
        late final Uri absoluteUri;
        try {
          absoluteUri = response.requestOptions.uri.resolve(location);
        } on FormatException catch (error) {
          return handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              error: error,
              message: '无效的重定向地址',
            ),
          );
        }
        if ((absoluteUri.scheme != 'http' && absoluteUri.scheme != 'https') ||
            absoluteUri.host.isEmpty ||
            absoluteUri.userInfo.isNotEmpty) {
          return handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              message: '重定向目标不是有效的 HTTP(S) 地址',
            ),
          );
        }

        final original = response.requestOptions;
        final sameOrigin = isSameOrigin(original.uri, absoluteUri);
        final sameDiscourseScope = isSameDiscourseScope(
          original.uri,
          absoluteUri,
        );
        final method = redirectedMethod(statusCode, original.method);
        final preservesBody = method != 'GET' && method != 'HEAD';
        final body = preservesBody ? original.data : null;

        // A 307/308 must never silently lose the POST/PUT body. Conversely,
        // replaying an authenticated write body onto a different origin is
        // unsafe, even after removing credential headers.
        if (!sameOrigin && body != null) {
          return handler.reject(
            DioException(
              requestOptions: original,
              response: response,
              type: DioExceptionType.badResponse,
              message: '拒绝向外部站点重放带有请求体的重定向',
            ),
          );
        }

        final headers = sanitizedHeadersForRedirect(
          original.headers,
          sameOrigin: sameDiscourseScope,
        );
        if (!preservesBody) {
          headers.removeWhere((key, _) {
            final lower = key.toLowerCase();
            return lower == 'content-type' ||
                lower == 'content-length' ||
                lower == 'transfer-encoding';
          });
        }

        final extra = redirectExtra(
          original.extra,
          sameOrigin: sameDiscourseScope,
          redirectCount: redirectCount,
        );
        // A same-host redirect out of a custom forum's relative root must
        // not reload the forum's root-path session cookie via CookieManager.
        if (sameOrigin &&
            !sameDiscourseScope &&
            !DiscourseInstanceRuntime.containsUri(
              absoluteUri,
              allowDefaultSubdomains: false,
            )) {
          extra[AppCookieManager.skipCookieManagerExtraKey] = true;
        }

        final newOptions = Options(
          method: method,
          headers: headers,
          extra: extra,
          responseType: original.responseType,
          validateStatus: original.validateStatus,
          followRedirects: false,
        );

        try {
          final redirectResponse = await _dio.request(
            absoluteUri.toString(),
            data: body,
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
