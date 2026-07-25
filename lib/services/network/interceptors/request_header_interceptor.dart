import 'package:dio/dio.dart';

import '../../../constants.dart';
import '../../log/log_writer.dart';
import '../../user_presence_service.dart';
import '../cookie/csrf_token_service.dart';

/// 请求头拦截器
/// 负责设置 User-Agent 和 CSRF Token
/// CSRF 策略对齐 Discourse 官方前端：POST 前 token 为空则先从 /session/csrf 获取
class RequestHeaderInterceptor extends Interceptor {
  RequestHeaderInterceptor(this._cookieSync, {Dio? dioRef})
    : _dioRef = dioRef;

  final CsrfTokenService _cookieSync;

  /// 重试所用的 Dio 实例（由工厂注入，便于 BAD CSRF 时复用整条拦截器链重试）。
  final Dio? _dioRef;

  /// 标记 key：请求已因 BAD CSRF 重试过一次，避免无限循环。
  static const String _csrfRetriedKey = '_csrfRetried';

  /// 判断响应是否为 Discourse 的 BAD CSRF (403 + "BAD CSRF" 文案)。
  /// Discourse 在 CSRF 校验失败时返回 403，响应体可能是 JSON
  /// {"errors":["Bad CSRF token..."]} 或纯文本 "Bad CSRF"。
  bool _isBadCsrfResponse(Response? response) {
    if (response == null) return false;
    final status = response.statusCode ?? 0;
    if (status != 403) return false;
    final data = response.data;
    String? text;
    if (data is String) {
      text = data;
    } else if (data is Map) {
      final errors = data['errors'];
      if (errors is List) {
        text = errors.join(' ');
      } else if (errors is String) {
        text = errors;
      } else {
        text = data['error']?.toString();
      }
    }
    if (text == null) return false;
    final lower = text.toLowerCase();
    return lower.contains('csrf');
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // 1. 设置 User-Agent
    options.headers['User-Agent'] = await AppConstants.getUserAgent();

    // 2. 注入 Client Hints 请求头（Sec-CH-UA 系列，仅移动端可用）
    final hints = AppConstants.clientHints;
    if (hints != null) {
      options.headers.addAll(hints);
    }

    // 3. 设置 CSRF Token（未登录时无法获取，跳过）
    final skipCsrf = options.extra['skipCsrf'] == true;
    if (!skipCsrf) {
      // 非 GET 请求且 token 为空时，先从 /session/csrf 获取
      // 对齐 Discourse 前端: if (type !== "GET" && !csrfToken) { updateCsrfToken() }
      final method = options.method.toUpperCase();
      if (method != 'GET' &&
          (_cookieSync.csrfToken == null || _cookieSync.csrfToken!.isEmpty)) {
        await _cookieSync.updateCsrfToken();
      }

      final csrf = _cookieSync.csrfToken;
      if (method != 'GET' && (csrf == null || csrf.isEmpty)) {
        // 取不到 CSRF token 时不再直接 cancel 整个请求——那样会让所有 POST
        // (发消息、点赞、书签等) 静默失败、用户无感知。改为放行请求 (不带
        // X-CSRF-Token)，由服务端返回 403 BAD CSRF 时再触发刷新重试
        // (见本拦截器 onError 的 BAD CSRF 处理)。这样即使首次刷新失败，也
        // 能在拿到 403 后补救，而不是彻底卡死。
        options.headers.remove('X-CSRF-Token');
        options.extra['_csrfUnavailable'] = true;
        LogWriter.instance.write({
          'timestamp': DateTime.now().toIso8601String(),
          'level': 'warning',
          'type': 'request',
          'event': 'csrf_unavailable_before_request',
          'message': 'POST 前无 CSRF token，放行请求，依赖 403 BAD CSRF 兜底刷新',
          'method': options.method,
          'url': options.uri.toString(),
          'isSilent': options.extra['isSilent'] == true,
        });
        handler.next(options);
        return;
      }
      if (csrf != null && csrf.isNotEmpty) {
        options.headers['X-CSRF-Token'] = csrf;
      } else {
        options.headers.remove('X-CSRF-Token');
      }
    }

    // 4. API 请求（XHR）设置 Origin、Referer 和 Sec-Fetch-* 头
    if (options.headers['X-Requested-With'] == 'XMLHttpRequest') {
      options.headers['Origin'] = AppConstants.baseUrl;
      options.headers['Referer'] = '${AppConstants.baseUrl}/';
      // Sec-Fetch-* 系列头：Chrome 从 2019 年起每个请求都自动添加，
      // 缺失会被 Cloudflare Bot Management 识别为非浏览器客户端
      options.headers['Sec-Fetch-Dest'] = 'empty';
      options.headers['Sec-Fetch-Mode'] = 'cors';
      options.headers['Sec-Fetch-Site'] = 'same-origin';
      // 告知 Discourse 用户当前在线，使后端更新 last_seen_at
      // 对齐 Discourse 前端: if (userPresent()) { headers["Discourse-Present"] = "true"; }
      if (UserPresenceService().isPresent) {
        options.headers['Discourse-Present'] = 'true';
      } else {
        options.headers.remove('Discourse-Present');
      }
    }

    handler.next(options);
  }

  /// BAD CSRF 自动恢复：收到 403 BAD CSRF 时清空旧 token，重新拉取
  /// /session/csrf，然后带新 token 重试原请求一次。对齐 Discourse 官方
  /// 前端 ajax.js 在 403 BAD CSRF 后 `set("csrfToken", null)` + 重试的行为。
  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final retried = err.requestOptions.extra[_csrfRetriedKey] == true;
    if (retried || !_isBadCsrfResponse(err.response)) {
      handler.next(err);
      return;
    }
    // 先清旧 token，再强制刷新
    _cookieSync.clearCsrfToken();
    try {
      await _cookieSync.updateCsrfToken();
    } catch (_) {
      handler.next(err);
      return;
    }
    final newCsrf = _cookieSync.csrfToken;
    if (newCsrf == null || newCsrf.isEmpty) {
      handler.next(err);
      return;
    }

    final dio = _dioRef;
    if (dio == null) {
      // 没有可用的 Dio 引用，无法重试，透传错误。
      handler.next(err);
      return;
    }
    try {
      final retryOptions = RequestOptions(
        path: err.requestOptions.path,
        method: err.requestOptions.method,
        data: err.requestOptions.data,
        queryParameters: Map<String, dynamic>.from(
          err.requestOptions.queryParameters,
        ),
        headers: Map<String, dynamic>.from(err.requestOptions.headers),
        extra: Map<String, dynamic>.from(err.requestOptions.extra)
          ..[_csrfRetriedKey] = true,
        baseUrl: err.requestOptions.baseUrl,
        connectTimeout: err.requestOptions.connectTimeout,
        sendTimeout: err.requestOptions.sendTimeout,
        receiveTimeout: err.requestOptions.receiveTimeout,
        contentType: err.requestOptions.contentType,
        responseType: err.requestOptions.responseType,
        validateStatus: err.requestOptions.validateStatus,
        receiveDataWhenStatusError:
            err.requestOptions.receiveDataWhenStatusError,
        followRedirects: err.requestOptions.followRedirects,
        maxRedirects: err.requestOptions.maxRedirects,
        persistentConnection: err.requestOptions.persistentConnection,
        requestEncoder: err.requestOptions.requestEncoder,
        responseDecoder: err.requestOptions.responseDecoder,
        listFormat: err.requestOptions.listFormat,
        cancelToken: err.requestOptions.cancelToken,
        onReceiveProgress: err.requestOptions.onReceiveProgress,
        onSendProgress: err.requestOptions.onSendProgress,
      );
      retryOptions.headers['X-CSRF-Token'] = newCsrf;
      final retryResp = await dio.fetch<dynamic>(retryOptions);
      handler.resolve(retryResp);
    } catch (e) {
      handler.next(err);
    }
  }
}
