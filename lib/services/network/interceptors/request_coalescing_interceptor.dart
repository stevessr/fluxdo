import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../auth_session.dart';
import '../flux_request_spec.dart';

const _ownerKey = '_fluxRequestCoalescingOwnerKey';

class _PendingResult {
  const _PendingResult.response(this.response) : error = null;
  const _PendingResult.error(this.error) : response = null;

  final Response<dynamic>? response;
  final DioException? error;
}

class _PendingRequest {
  final Completer<_PendingResult> completer = Completer<_PendingResult>();
}

/// Registry shared by all [DiscourseDio] instances.
///
/// The session generation is part of every key, so responses can never be
/// shared across account switches. API-key based callers are additionally
/// separated by a digest of their auth headers.
class _RequestCoalescingRegistry {
  static final Map<String, _PendingRequest> _pending =
      <String, _PendingRequest>{};

  static _PendingRequest? joinOrRegister(String key) {
    final existing = _pending[key];
    if (existing != null) return existing;
    _pending[key] = _PendingRequest();
    return null;
  }

  static void completeResponse(String key, Response<dynamic> response) {
    final pending = _pending.remove(key);
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.complete(_PendingResult.response(response));
    }
  }

  static void completeError(String key, DioException error) {
    final pending = _pending.remove(key);
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.complete(_PendingResult.error(error));
    }
  }
}

/// Collapses identical in-flight GET requests into one physical request.
///
/// This mirrors the useful property of Discourse's model/store layer where a
/// single load promise is shared by all consumers, but does it below the
/// service layer so every endpoint benefits automatically.
///
/// The interceptor is deliberately registered before the scheduler. Followers
/// therefore do not consume concurrency/rate-limit slots. Completion is done by
/// [RequestCoalescingFinalizerInterceptor], which is registered after recovery,
/// redirects and Cloudflare handling so followers always observe the final
/// response rather than an intermediate retry/challenge response.
class RequestCoalescingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Recovery/redirect/CF replay keeps the owner marker. Treat it as the same
    // physical request instead of joining its own pending future.
    if (options.extra[_ownerKey] is String) {
      handler.next(options);
      return;
    }

    final key = _coalescingKey(options);
    if (key == null) {
      handler.next(options);
      return;
    }

    final existing = _RequestCoalescingRegistry.joinOrRegister(key);
    if (existing == null) {
      options.extra[_ownerKey] = key;
      handler.next(options);
      return;
    }

    unawaited(_resolveFollower(options, handler, existing));
  }

  Future<void> _resolveFollower(
    RequestOptions options,
    RequestInterceptorHandler handler,
    _PendingRequest pending,
  ) async {
    final cancelToken = options.cancelToken;
    final result = cancelToken == null
        ? await pending.completer.future
        : await Future.any<_PendingResult?>([
            pending.completer.future,
            cancelToken.whenCancel.then<_PendingResult?>((_) => null),
          ]);

    if (result == null || (cancelToken?.isCancelled ?? false)) {
      handler.reject(
        DioException.requestCancelled(
          requestOptions: options,
          reason: cancelToken?.cancelError?.error ?? '重复请求等待期间已取消',
        ),
        true,
      );
      return;
    }

    final response = result.response;
    if (response != null) {
      final extra = Map<String, dynamic>.from(response.extra)
        ..['requestCoalesced'] = true;
      handler.resolve(
        Response<dynamic>(
          requestOptions: options,
          data: response.data,
          headers: Headers.fromMap(
            response.headers.map.map(
              (key, values) => MapEntry(key, List<String>.from(values)),
            ),
            preserveHeaderCase: response.headers.preserveHeaderCase,
          ),
          statusCode: response.statusCode,
          statusMessage: response.statusMessage,
          isRedirect: response.isRedirect,
          redirects: List<RedirectRecord>.from(response.redirects),
          extra: extra,
        ),
        true,
      );
      return;
    }

    final error = result.error!;
    handler.reject(
      DioException(
        requestOptions: options,
        response: error.response == null
            ? null
            : Response<dynamic>(
                requestOptions: options,
                data: error.response!.data,
                headers: Headers.fromMap(
                  error.response!.headers.map.map(
                    (key, values) => MapEntry(key, List<String>.from(values)),
                  ),
                  preserveHeaderCase:
                      error.response!.headers.preserveHeaderCase,
                ),
                statusCode: error.response!.statusCode,
                statusMessage: error.response!.statusMessage,
                isRedirect: error.response!.isRedirect,
                redirects: List<RedirectRecord>.from(error.response!.redirects),
                extra: Map<String, dynamic>.from(error.response!.extra),
              ),
        type: error.type,
        error: error.error,
        stackTrace: error.stackTrace,
        message: error.message,
      ),
      true,
    );
  }

  String? _coalescingKey(RequestOptions options) {
    if (options.method.toUpperCase() != 'GET') return null;
    if (options.spec.isSilent) return null;
    if (options.responseType == ResponseType.stream ||
        options.responseType == ResponseType.bytes) {
      return null;
    }
    if (_header(options, 'range') != null) return null;

    final requestCacheControl = _header(
      options,
      'cache-control',
    )?.toLowerCase();
    if (requestCacheControl?.contains('no-store') ?? false) return null;

    final uri = options.uri;
    final queryEntries = uri.queryParametersAll.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final canonicalQuery = jsonEncode(<String, List<String>>{
      for (final entry in queryEntries) entry.key: entry.value,
    });

    final authMaterial = <String>[
      _header(options, 'authorization') ?? '',
      _header(options, 'api-key') ?? '',
      _header(options, 'api-username') ?? '',
    ].join('\n');
    final authDigest = sha256.convert(utf8.encode(authMaterial)).toString();

    final representationMaterial = <String>[
      _header(options, 'accept') ?? '',
      _header(options, 'accept-language') ?? '',
      _header(options, 'discourse-track-view') ?? '',
      _header(options, 'discourse-track-view-topic-id') ?? '',
    ].join('\n');
    final representationDigest = sha256
        .convert(utf8.encode(representationMaterial))
        .toString();

    return '${AuthSession().generation}|${uri.scheme.toLowerCase()}://'
        '${uri.authority.toLowerCase()}${uri.path}|$canonicalQuery|'
        '${options.responseType.name}|$authDigest|$representationDigest';
  }

  String? _header(RequestOptions options, String name) {
    final lower = name.toLowerCase();
    for (final entry in options.headers.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value?.toString();
      }
    }
    return null;
  }
}

/// Completes coalesced requests only after all response-recovery machinery has
/// produced its final result.
class RequestCoalescingFinalizerInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final key = response.requestOptions.extra.remove(_ownerKey);
    if (key is String) {
      _RequestCoalescingRegistry.completeResponse(key, response);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final key = err.requestOptions.extra.remove(_ownerKey);
    if (key is String) {
      _RequestCoalescingRegistry.completeError(key, err);
    }
    handler.next(err);
  }
}
