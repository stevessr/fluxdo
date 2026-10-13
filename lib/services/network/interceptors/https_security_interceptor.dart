import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Process-local HSTS policy learned only from authenticated HTTPS responses.
///
/// This is intentionally not a preload list or a persistent browser profile.
/// HTTPS upgrades apply to the original request URL, before the proxy/gateway
/// adapter rewrites transport details; a local HTTP proxy must never be mistaken
/// for an insecure origin.
class HttpsSecurityPolicy {
  HttpsSecurityPolicy({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static final HttpsSecurityPolicy instance = HttpsSecurityPolicy();

  static const int _maxHosts = 128;
  static const int _maxAgeSeconds = 2 * 365 * 24 * 60 * 60;

  final DateTime Function() _now;
  final LinkedHashMap<String, _HstsEntry> _hosts =
      LinkedHashMap<String, _HstsEntry>();

  /// Upgrade only hosts for which a valid HSTS directive was observed.
  Uri upgrade(Uri uri) {
    if (uri.scheme.toLowerCase() != 'http' || !_hasHsts(uri.host)) {
      return uri;
    }
    // RFC 6797: map port 80 to 443; preserve other explicit ports.
    return uri.replace(scheme: 'https', port: uri.port == 80 ? 443 : uri.port);
  }

  /// Never accept HSTS over plaintext HTTP, from IP literals or localhost.
  void observe(Uri uri, Headers headers) {
    if (uri.scheme.toLowerCase() != 'https') return;
    final host = _normalizedHost(uri.host);
    if (!_validHost(host)) return;

    final values = headers['strict-transport-security'];
    // Multiple STS headers are ambiguous; fail closed by ignoring the update.
    if (values == null || values.length != 1) return;
    final parsed = _parse(values.single);
    if (parsed == null) return;

    if (parsed.maxAge == 0) {
      _hosts.remove(host);
      return;
    }

    _hosts.remove(host);
    _hosts[host] = _HstsEntry(
      until: _now().add(Duration(seconds: parsed.maxAge)),
      includeSubDomains: parsed.includeSubDomains,
    );
    while (_hosts.length > _maxHosts) {
      _hosts.remove(_hosts.keys.first);
    }
  }

  bool _hasHsts(String rawHost) {
    final host = _normalizedHost(rawHost);
    if (!_validHost(host)) return false;
    final now = _now();
    var current = host;
    var exact = true;
    while (current.isNotEmpty) {
      final entry = _hosts[current];
      if (entry != null) {
        if (!now.isBefore(entry.until)) {
          _hosts.remove(current);
        } else if (exact || entry.includeSubDomains) {
          return true;
        }
      }
      final dot = current.indexOf('.');
      if (dot < 0) break;
      current = current.substring(dot + 1);
      exact = false;
    }
    return false;
  }

  String _normalizedHost(String host) =>
      host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');

  bool _validHost(String host) =>
      host.contains('.') &&
      host != 'localhost' &&
      !host.endsWith('.localhost') &&
      InternetAddress.tryParse(host) == null;

  _ParsedHsts? _parse(String header) {
    int? maxAge;
    var includeSubDomains = false;
    for (final part in header.split(';')) {
      final directive = part.trim();
      if (directive.isEmpty) continue;
      final equal = directive.indexOf('=');
      final name = (equal < 0 ? directive : directive.substring(0, equal))
          .trim()
          .toLowerCase();
      if (name == 'includesubdomains') {
        if (equal < 0) includeSubDomains = true;
        continue;
      }
      if (name != 'max-age') continue;
      if (maxAge != null || equal < 0) return null;
      var raw = directive.substring(equal + 1).trim();
      if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
        raw = raw.substring(1, raw.length - 1);
      }
      if (!RegExp(r'^\d+$').hasMatch(raw)) return null;
      final age = int.tryParse(raw);
      if (age == null) return null;
      maxAge = age > _maxAgeSeconds ? _maxAgeSeconds : age;
    }
    if (maxAge == null) return null;
    return _ParsedHsts(maxAge: maxAge, includeSubDomains: includeSubDomains);
  }

  @visibleForTesting
  void clearForTest() => _hosts.clear();
}

class _HstsEntry {
  const _HstsEntry({required this.until, required this.includeSubDomains});

  final DateTime until;
  final bool includeSubDomains;
}

class _ParsedHsts {
  const _ParsedHsts({required this.maxAge, required this.includeSubDomains});

  final int maxAge;
  final bool includeSubDomains;
}

/// Applies HSTS before request scheduling/cookies and learns from responses,
/// including error status responses with valid TLS.
class HttpsSecurityInterceptor extends Interceptor {
  HttpsSecurityInterceptor({HttpsSecurityPolicy? policy})
      : _policy = policy ?? HttpsSecurityPolicy.instance;

  final HttpsSecurityPolicy _policy;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final origin = options.uri;
    final upgraded = _policy.upgrade(origin);
    if (upgraded != origin) {
      // Change only the URL component that owns the scheme. Replacing path
      // with options.uri (which already includes queryParameters) would make
      // Dio append those parameters a second time on the next uri read.
      final pathUri = Uri.tryParse(options.path);
      if (pathUri != null &&
          pathUri.scheme.toLowerCase() == 'http' &&
          pathUri.host == origin.host) {
        options.path = _policy.upgrade(pathUri).toString();
      } else {
        final baseUri = Uri.tryParse(options.baseUrl);
        if (baseUri != null &&
            baseUri.scheme.toLowerCase() == 'http' &&
            baseUri.host == origin.host) {
          options.baseUrl = _policy.upgrade(baseUri).toString();
        } else {
          // Uncommon scheme-relative URLs: use the complete resolved URI,
          // clearing the query map to avoid duplicate parameters.
          options.baseUrl = '';
          options.path = upgraded.toString();
          // The map can originate from an immutable caller-owned map.
          // Replace it instead of mutating it in place.
          options.queryParameters = <String, dynamic>{};
        }
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _policy.observe(response.requestOptions.uri, response.headers);
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    final response = error.response;
    if (response != null) {
      _policy.observe(error.requestOptions.uri, response.headers);
    }
    handler.next(error);
  }
}
