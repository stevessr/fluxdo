import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../auth_session.dart';
import '../flux_request_spec.dart';

const _cacheEntryExtra = '_fluxHttpRevalidationEntry';
const _cacheKeyExtra = '_fluxHttpRevalidationKey';

class _RevalidationEntry {
  _RevalidationEntry({
    required this.generation,
    required this.data,
    required this.headers,
    required this.etag,
    required this.lastModified,
    required this.varyFingerprints,
  });

  final int generation;
  final dynamic data;
  final Map<String, List<String>> headers;
  final String? etag;
  final String? lastModified;
  final Map<String, String> varyFingerprints;
}

/// Small, process-local HTTP validator cache for Discourse API responses.
///
/// It intentionally does *not* invent a TTL. Discourse data such as topic
/// tracking, notification counts and permissions changes frequently, so stale
/// data is more damaging than one cheap revalidation request. Instead we retain
/// only responses carrying ETag/Last-Modified and attach If-None-Match /
/// If-Modified-Since to the next GET. A 304 is expanded back to a normal 200
/// response with the cached body.
///
/// This gives native Dio/rhttp requests the browser-like conditional request
/// behavior expected by Discourse while keeping the server authoritative.
class HttpRevalidationInterceptor extends Interceptor {
  static const int _maxEntries = 64;
  static const int _maxBodyBytes = 768 * 1024;

  static final LinkedHashMap<String, _RevalidationEntry> _entries =
      LinkedHashMap<String, _RevalidationEntry>();

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    if (!_eligibleGet(options)) {
      handler.next(options);
      return;
    }

    // Recovery / redirect replays keep the entry snapshot. Conditional headers
    // are already present and must not be replaced with a different cache entry.
    if (options.extra[_cacheEntryExtra] is _RevalidationEntry) {
      handler.next(options);
      return;
    }

    // Respect caller-owned validators. We must not reinterpret a caller's 304
    // using a body it did not ask this cache to manage.
    if (_header(options, 'if-none-match') != null ||
        _header(options, 'if-modified-since') != null) {
      handler.next(options);
      return;
    }

    final generation = AuthSession().generation;
    _purgeOtherGenerations(generation);

    final key = _cacheKey(options, generation);
    final entry = _touch(key);
    if (entry == null || !_varyMatches(options, entry)) {
      handler.next(options);
      return;
    }

    var attached = false;
    if (entry.etag != null && entry.etag!.isNotEmpty) {
      options.headers['If-None-Match'] = entry.etag;
      attached = true;
    }
    if (entry.lastModified != null && entry.lastModified!.isNotEmpty) {
      options.headers['If-Modified-Since'] = entry.lastModified;
      attached = true;
    }

    if (attached) {
      // Keep a snapshot on the request so an in-flight entry cannot disappear
      // due to LRU eviction before a 304 arrives.
      options.extra[_cacheEntryExtra] = entry;
      options.extra[_cacheKeyExtra] = key;
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final options = response.requestOptions;
    final method = options.method.toUpperCase();

    if (method != 'GET' && method != 'HEAD') {
      final status = response.statusCode ?? 0;
      if (status >= 200 && status < 400) {
        _invalidateScope(options);
      }
      handler.next(response);
      return;
    }

    if (!_eligibleGet(options)) {
      handler.next(response);
      return;
    }

    final snapshot = options.extra.remove(_cacheEntryExtra);
    final attachedKey = options.extra.remove(_cacheKeyExtra);

    if (response.statusCode == 304 && snapshot is _RevalidationEntry) {
      final mergedHeaders = _mergeHeaders(snapshot.headers, response.headers.map);
      final expanded = Response<dynamic>(
        requestOptions: options,
        data: snapshot.data,
        headers: Headers.fromMap(
          mergedHeaders,
          preserveHeaderCase: response.headers.preserveHeaderCase,
        ),
        statusCode: 200,
        statusMessage: response.statusMessage,
        isRedirect: response.isRedirect,
        redirects: List<RedirectRecord>.from(response.redirects),
        extra: Map<String, dynamic>.from(response.extra)
          ..['httpCacheRevalidated'] = true
          ..['httpCacheOriginalStatus'] = 304,
      );

      final key = attachedKey is String
          ? attachedKey
          : _cacheKey(options, AuthSession().generation);
      _storeFromResponse(expanded, keyOverride: key);
      handler.next(expanded);
      return;
    }

    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      _storeFromResponse(response);
    }

    handler.next(response);
  }

  bool _eligibleGet(RequestOptions options) {
    if (options.method.toUpperCase() != 'GET') return false;
    if (options.spec.isSilent) return false;
    if (options.responseType == ResponseType.stream ||
        options.responseType == ResponseType.bytes) {
      return false;
    }
    if (_header(options, 'range') != null) return false;

    final cacheControl = _header(options, 'cache-control')?.toLowerCase();
    if (cacheControl?.contains('no-store') ?? false) return false;
    return true;
  }

  void _storeFromResponse(Response response, {String? keyOverride}) {
    final options = response.requestOptions;
    final cacheControl = _responseHeader(response.headers, 'cache-control')
        ?.toLowerCase();
    final key = keyOverride ?? _cacheKey(options, AuthSession().generation);

    if (cacheControl?.contains('no-store') ?? false) {
      _entries.remove(key);
      return;
    }

    final vary = _responseHeader(response.headers, 'vary');
    if (vary != null &&
        vary.split(',').any((part) => part.trim() == '*')) {
      _entries.remove(key);
      return;
    }

    final etag = _responseHeader(response.headers, 'etag');
    final lastModified = _responseHeader(response.headers, 'last-modified');
    if ((etag == null || etag.isEmpty) &&
        (lastModified == null || lastModified.isEmpty)) {
      _entries.remove(key);
      return;
    }

    if (!_withinBodyBudget(response)) {
      _entries.remove(key);
      return;
    }

    final varyNames = vary
            ?.split(',')
            .map((name) => name.trim().toLowerCase())
            .where((name) => name.isNotEmpty)
            .toSet() ??
        const <String>{};
    final varyFingerprints = <String, String>{
      for (final name in varyNames)
        name: _fingerprint(_header(options, name) ?? ''),
    };

    final entry = _RevalidationEntry(
      generation: AuthSession().generation,
      data: response.data,
      headers: _copyHeaderMap(response.headers.map),
      etag: etag,
      lastModified: lastModified,
      varyFingerprints: varyFingerprints,
    );

    _entries.remove(key);
    _entries[key] = entry;
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  bool _withinBodyBudget(Response response) {
    final contentLength = int.tryParse(
      _responseHeader(response.headers, Headers.contentLengthHeader) ?? '',
    );
    if (contentLength != null) {
      return contentLength <= _maxBodyBytes;
    }
    return _estimateSize(response.data, _maxBodyBytes + 1) <= _maxBodyBytes;
  }

  int _estimateSize(Object? value, int stopAfter) {
    var total = 0;

    void visit(Object? node) {
      if (total >= stopAfter || node == null) return;
      if (node is String) {
        total += node.length * 2;
      } else if (node is num || node is bool) {
        total += 16;
      } else if (node is Map) {
        for (final entry in node.entries) {
          total += entry.key.toString().length * 2;
          visit(entry.value);
          if (total >= stopAfter) return;
        }
      } else if (node is Iterable) {
        for (final item in node) {
          visit(item);
          if (total >= stopAfter) return;
        }
      } else {
        total += node.toString().length * 2;
      }
    }

    visit(value);
    return total;
  }

  bool _varyMatches(RequestOptions options, _RevalidationEntry entry) {
    for (final vary in entry.varyFingerprints.entries) {
      if (_fingerprint(_header(options, vary.key) ?? '') != vary.value) {
        return false;
      }
    }
    return true;
  }

  _RevalidationEntry? _touch(String key) {
    final entry = _entries.remove(key);
    if (entry != null) _entries[key] = entry;
    return entry;
  }

  void _purgeOtherGenerations(int generation) {
    _entries.removeWhere((_, entry) => entry.generation != generation);
  }

  void _invalidateScope(RequestOptions options) {
    final generation = AuthSession().generation;
    final uri = options.uri;
    final scope = '$generation|${uri.scheme.toLowerCase()}://'
        '${uri.authority.toLowerCase()}|';
    _entries.removeWhere((key, _) => key.startsWith(scope));
  }

  String _cacheKey(RequestOptions options, int generation) {
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
    final authDigest = _fingerprint(authMaterial);

    return '$generation|${uri.scheme.toLowerCase()}://'
        '${uri.authority.toLowerCase()}|${uri.path}|$canonicalQuery|'
        '${options.responseType.name}|$authDigest';
  }

  String _fingerprint(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  String? _header(RequestOptions options, String name) {
    final lower = name.toLowerCase();
    for (final entry in options.headers.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value?.toString();
      }
    }
    return null;
  }

  String? _responseHeader(Headers headers, String name) {
    final values = headers[name];
    if (values == null || values.isEmpty) return null;
    return values.join(',');
  }

  Map<String, List<String>> _copyHeaderMap(
    Map<String, List<String>> source,
  ) =>
      source.map(
        (key, values) => MapEntry(key, List<String>.from(values)),
      );

  Map<String, List<String>> _mergeHeaders(
    Map<String, List<String>> cached,
    Map<String, List<String>> fresh,
  ) {
    final merged = _copyHeaderMap(cached);
    for (final entry in fresh.entries) {
      merged[entry.key] = List<String>.from(entry.value);
    }
    return merged;
  }
}
