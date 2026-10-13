import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// HSTS policy learned only from authenticated HTTPS responses.
///
/// The application-wide instance persists bounded, expiring host policies
/// across restarts. Standalone policies are in-memory by default for tests.
/// HTTPS upgrades apply to the original request URL, before the proxy/gateway
/// adapter rewrites transport details; a local HTTP proxy must never be mistaken
/// for an insecure origin.
class HttpsSecurityPolicy {
  HttpsSecurityPolicy({DateTime Function()? now, bool persist = false})
      : _now = now ?? DateTime.now,
        _persist = persist;

  static final HttpsSecurityPolicy instance = HttpsSecurityPolicy(persist: true);

  static const String _storageKey = 'network_hsts_policies_v1';
  static const int _maxHosts = 128;
  static const int _maxAgeSeconds = 2 * 365 * 24 * 60 * 60;

  final DateTime Function() _now;
  final bool _persist;
  final LinkedHashMap<String, _HstsEntry> _hosts =
      LinkedHashMap<String, _HstsEntry>();
  // Record in-memory changes made while SharedPreferences is still loading,
  // including max-age=0 deletions. Disk must never resurrect these policies.
  final Set<String> _changedDuringLoad = <String>{};
  SharedPreferences? _preferences;
  Future<void>? _loadFuture;
  bool _loadCompleted = false;
  Timer? _persistTimer;
  Future<void> _writeTail = Future<void>.value();

  /// Lazily load before the first outgoing request so a remembered policy can
  /// prevent a downgrade even before this process has seen a TLS response.
  /// Storage failures must never block the network path.
  bool get isLoaded => !_persist || _loadCompleted;

  Future<void> ensureLoaded() {
    if (isLoaded) return Future<void>.value();
    return _loadFuture ??= _loadStoredPolicies();
  }

  Future<void> _loadStoredPolicies() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      // A corrupt cache must not permanently disable future HSTS writes.
      _preferences = preferences;
      final raw = preferences.getString(_storageKey);
      if (raw != null) {
        Object? decoded;
        try {
          decoded = jsonDecode(raw);
        } on FormatException {
          decoded = null;
        }
        if (decoded is List) {
          final now = _now();
          final maximum = now.add(const Duration(seconds: _maxAgeSeconds));
          for (final item in decoded) {
            if (item is! Map) continue;
            final host = item['host'];
            final epoch = item['until'];
            final include = item['includeSubDomains'];
            if (host is! String || epoch is! int || include is! bool) {
              continue;
            }
            if (!_validHost(host) || _normalizedHost(host) != host) continue;
            final until = DateTime.fromMillisecondsSinceEpoch(epoch);
            if (!until.isAfter(now) || until.isAfter(maximum)) continue;
            // If a live TLS response was observed while loading, that newer
            // response is authoritative over the disk snapshot.
            if (!_changedDuringLoad.contains(host)) {
              _hosts.putIfAbsent(
                host,
                () => _HstsEntry(until: until, includeSubDomains: include),
              );
            }
          }
          while (_hosts.length > _maxHosts) {
            _hosts.remove(_hosts.keys.first);
          }
        }
      }
    } catch (error) {
      debugPrint('[HTTPS] Failed to load HSTS cache: $error');
    }
    if (_changedDuringLoad.isNotEmpty) {
      _changedDuringLoad.clear();
      _schedulePersistence(immediately: true);
    }
    _loadCompleted = true;
  }

  void _schedulePersistence({bool immediately = false}) {
    if (!_persist || _preferences == null) return;
    if (immediately) {
      _persistTimer?.cancel();
      _persistTimer = null;
      unawaited(flushPending());
      return;
    }
    // A single timer, not one preferences write per network response.
    _persistTimer ??= Timer(const Duration(seconds: 5), () {
      _persistTimer = null;
      unawaited(flushPending());
    });
  }

  @visibleForTesting
  Future<void> flushPending() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    final preferences = _preferences;
    if (preferences == null) return;
    final now = _now();
    final serialized = jsonEncode([
      for (final entry in _hosts.entries)
        if (entry.value.until.isAfter(now))
          {
            'host': entry.key,
            'until': entry.value.until.millisecondsSinceEpoch,
            'includeSubDomains': entry.value.includeSubDomains,
          },
    ]);
    _writeTail = _writeTail.then((_) async {
      await preferences.setString(_storageKey, serialized);
    }).catchError((Object error) {
      debugPrint('[HTTPS] Failed to persist HSTS cache: $error');
    });
    await _writeTail;
  }

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
    if (_persist && _preferences == null) {
      _changedDuringLoad.add(host);
    }

    if (parsed.maxAge == 0) {
      _hosts.remove(host);
      _schedulePersistence(immediately: true);
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
    _schedulePersistence();
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
          _schedulePersistence();
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
  void clearForTest() {
    _persistTimer?.cancel();
    _persistTimer = null;
    _hosts.clear();
    _changedDuringLoad.clear();
  }
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
    if (_policy.isLoaded) {
      _upgradeAndContinue(options, handler);
      return;
    }
    // Cold start waits for restored HSTS so the first request is protected.
    // Hot requests stay synchronous (avoids a microtask on every preload).
    _policy.ensureLoaded().then(
      (_) => _upgradeAndContinue(options, handler),
      onError: (Object _) => _upgradeAndContinue(options, handler),
    );
  }

  void _upgradeAndContinue(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
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
    // Informational 1xx responses, including Cloudflare 103 Early Hints,
    // must not alter transport security policy.
    if ((response.statusCode ?? 0) >= 200) {
      _policy.observe(response.requestOptions.uri, response.headers);
    }
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    final response = error.response;
    // A rejected certificate is NOT an authenticated HTTPS response.
    if (error.type != DioExceptionType.badCertificate &&
        response != null &&
        (response.statusCode ?? 0) >= 200) {
      _policy.observe(error.requestOptions.uri, response.headers);
    }
    handler.next(error);
  }
}
