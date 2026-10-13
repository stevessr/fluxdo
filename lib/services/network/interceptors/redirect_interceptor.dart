import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../flux_request_spec.dart';
import 'https_security_interceptor.dart';

/// Manual 301/302/303/307/308 handling with cookie re-selection, strict
/// HTTPS downgrade protection, and RFC-compatible request method semantics.
class RedirectInterceptor extends Interceptor {
  RedirectInterceptor(this._dio, {HttpsSecurityPolicy? httpsPolicy})
      : _httpsPolicy = httpsPolicy ?? HttpsSecurityPolicy.instance;

  final Dio _dio;
  final HttpsSecurityPolicy _httpsPolicy;
  static const String _redirectCountKey = '_redirectCount';
  static const int _maxRedirects = 10;

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    final source = response.requestOptions;
    if (source.spec.skipRedirect) {
      handler.next(response);
      return;
    }

    final code = response.statusCode;
    if (code != 301 && code != 302 && code != 303 &&
        code != 307 && code != 308) {
      handler.next(response);
      return;
    }

    final location = response.headers.value('location');
    if (location == null || location.isEmpty) {
      handler.next(response);
      return;
    }

    Uri destination;
    try {
      destination = _httpsPolicy.upgrade(source.uri.resolve(location));
    } on FormatException {
      handler.next(response);
      return;
    }

    // Custom schemes (for example OAuth deep links) belong to the caller.
    if (destination.scheme != 'http' && destination.scheme != 'https') {
      handler.next(response);
      return;
    }

    if (source.uri.scheme == 'https' && destination.scheme != 'https') {
      handler.reject(_redirectError(
        response, 'Blocked HTTPS to HTTP redirect',
      ));
      return;
    }

    final redirectCount = source.extra[_redirectCountKey] as int? ?? 0;
    if (redirectCount >= _maxRedirects) {
      handler.reject(_redirectError(response, 'Too many redirects ($_maxRedirects)'));
      return;
    }

    // RFC 9110: 303 always changes to GET (except HEAD); browsers also turn
    // POST into GET on 301/302. 307/308 preserve method and body.
    final oldMethod = source.method.toUpperCase();
    final switchToGet = (code == 303 && oldMethod != 'HEAD') ||
        ((code == 301 || code == 302) && oldMethod == 'POST');
    final method = switchToGet ? 'GET' : oldMethod;
    final replayBody = !switchToGet && source.data != null;
    final crossOrigin = source.uri.origin != destination.origin;

    // Never replay non-repeatable streams or leak a write body to a different
    // origin via an untrusted redirect. Multipart data is explicitly cloned.
    if (replayBody && crossOrigin) {
      handler.reject(_redirectError(
        response, 'Cross-origin redirect of a request body is not allowed',
      ));
      return;
    }
    if (replayBody && source.data is Stream) {
      handler.reject(_redirectError(
        response, 'Cannot replay a streaming request body after redirect',
      ));
      return;
    }

    final headers = Map<String, dynamic>.from(source.headers);
    // The cookie manager must select cookies for the destination URL again.
    // Validators (ETag / Last-Modified) are scoped to the original target;
    // even an intra-origin redirect can resolve to an unrelated resource.
    _removeHeaders(headers, const {
      'cookie', 'if-none-match', 'if-modified-since', 'if-match',
      'if-unmodified-since',
    });
    final isMultipartReplay = replayBody && source.data is FormData;
    if (switchToGet) {
      // 303 and browser-style POST 301/302 become bodyless GETs. Remove
      // all metadata that describes the old POST entity or its checksum.
      _removeHeaders(headers, const {
        'content-type', 'content-length', 'content-encoding',
        'transfer-encoding', 'content-md5', 'content-range',
        'content-language', 'content-disposition', 'digest', 'trailer',
        'expect',
      });
    } else if (isMultipartReplay) {
      // Derive the multipart boundary and length from the replayed FormData.
      // Clone implementations may preserve or regenerate their boundary;
      // stale caller headers must not override the actual encoded body.
      _removeHeaders(headers, const {
        'content-type', 'content-length', 'transfer-encoding',
      });
    }
    if (crossOrigin) {
      // Only forward innocuous representation/range preferences. An allowlist
      // also protects future custom authentication headers we do not yet know
      // about, instead of relying on an incomplete list of secret names.
      const allowed = {
        // Let each target adapter negotiate an encoding it can decode.
        // An original engine's br/zstd choice may not work after fallback.
        'accept', 'accept-language', 'user-agent',
        'range', 'if-range', 'cache-control', 'pragma',
      };
      headers.removeWhere((name, _) => !allowed.contains(name.toLowerCase()));
    }

    // A redirect is an internal subrequest; retaining the scheduling slot
    // without bypassing the scheduler could deadlock at concurrency = 1.
    final extra = crossOrigin
        ? _crossOriginRequestExtras(source.extra)
        : Map<String, dynamic>.from(source.extra);
    // Avoid expanding a destination 304 against the original URL's cached
    // representation. This applies to same-origin redirects as well.
    extra.remove('_fluxHttpRevalidationEntry');
    extra.remove('_fluxHttpRevalidationKey');
    extra[FluxRequestKeys.skipScheduler] = true;
    extra[_redirectCountKey] = redirectCount + 1;
    if (crossOrigin) {
      // A foreign origin must not borrow forum credentials, trigger CSRF
      // refreshes, mutate the current Discourse auth state or engage the
      // forum-specific Cloudflare/session-recovery machinery on its 401/403.
      extra[FluxRequestKeys.skipCsrf] = true;
      extra[FluxRequestKeys.skipAuthCheck] = true;
      extra[FluxRequestKeys.skipSessionStateSync] = true;
      extra[FluxRequestKeys.skipCfChallenge] = true;
      extra[FluxRequestKeys.noRecovery] = true;
    }

    final data = replayBody
        ? (source.data is FormData
              ? (source.data as FormData).clone()
              : source.data)
        : null;

    debugPrint('[Dio] Redirect $code -> ${destination.scheme}://${destination.host}');
    try {
      // Dio.request() would merge BaseOptions.headers *again*, silently
      // reinstating Authorization / Cookie / custom secrets on an external
      // origin after our allowlist stripped them. Dio.fetch(RequestOptions)
      // keeps the already-composed request context while still re-running
      // all request/response interceptors for target-domain cookie selection.
      final redirectedOptions = RequestOptions(
        path: destination.toString(),
        baseUrl: '',
        queryParameters: <String, dynamic>{},
        method: method,
        data: data,
        headers: headers,
        extra: extra,
        cancelToken: source.cancelToken,
        onSendProgress: source.onSendProgress,
        onReceiveProgress: source.onReceiveProgress,
        connectTimeout: source.connectTimeout,
        sendTimeout: source.sendTimeout,
        receiveTimeout: source.receiveTimeout,
        transformTimeout: source.transformTimeout,
        responseType: source.responseType,
        contentType: switchToGet || isMultipartReplay
            ? null
            : source.contentType,
        validateStatus: source.validateStatus,
        receiveDataWhenStatusError: source.receiveDataWhenStatusError,
        followRedirects: false,
        maxRedirects: source.maxRedirects,
        persistentConnection: source.persistentConnection,
        preserveHeaderCase: source.preserveHeaderCase,
        requestEncoder: source.requestEncoder,
        responseDecoder: source.responseDecoder,
        listFormat: source.listFormat,
      );
      final redirected = await _dio.fetch<dynamic>(redirectedOptions);
      handler.resolve(redirected);
    } on DioException catch (error) {
      handler.reject(error);
    } catch (error) {
      handler.reject(DioException(
        requestOptions: source,
        error: error,
        type: DioExceptionType.unknown,
      ));
    }
  }

  /// Drop cache snapshots, auth-cookie copying intent, stale request-scoped
  /// recovery state, and future private metadata when redirecting off-origin.
  /// Only retain known non-credential request behavior flags.
  Map<String, dynamic> _crossOriginRequestExtras(
    Map<String, dynamic> original,
  ) {
    const allowedKeys = <String>{
      FluxRequestKeys.isSilent,
      FluxRequestKeys.showErrorToast,
      FluxRequestKeys.priority,
      FluxRequestKeys.requestTag,
      FluxRequestKeys.skipNetworkLog,
      FluxRequestKeys.skipSessionStateSync,
      FluxRequestKeys.skipAuthCheck,
      FluxRequestKeys.skipRhttpAdapter,
      FluxRequestKeys.skipWebViewAdapter,
      FluxRequestKeys.noRecovery,
      FluxRequestKeys.skipCfChallenge,
      FluxRequestKeys.skipCfBlock,
    };
    return <String, dynamic>{
      for (final entry in original.entries)
        if (allowedKeys.contains(entry.key)) entry.key: entry.value,
    };
  }

  DioException _redirectError(Response response, String reason) =>
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: reason,
      );

  void _removeHeaders(Map<String, dynamic> headers, Set<String> names) {
    headers.removeWhere((name, _) => names.contains(name.toLowerCase()));
  }
}
