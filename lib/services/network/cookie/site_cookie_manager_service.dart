import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:flutter/foundation.dart';

import 'cookie_jar_service.dart';
import 'cookie_store_observer.dart';
import 'raw_cookie_writer.dart';
import 'site_cookie_cleanup_service.dart';

/// Browser-style cookie entry merged from WebView storage and the persistent jar.
class ManagedSiteCookie {
  const ManagedSiteCookie({
    required this.host,
    required this.name,
    required this.value,
    required this.domain,
    required this.hostOnly,
    required this.path,
    required this.expiresAt,
    required this.secure,
    required this.httpOnly,
    required this.sameSite,
    required this.partitioned,
    required this.inWebView,
    required this.inJar,
    required this.fieldsComplete,
    this.partitionKey,
    this.rawDomain,
  });

  final String host;
  final String name;
  final String value;
  final String domain;
  final String? rawDomain;
  final bool hostOnly;
  final String path;
  final DateTime? expiresAt;
  final bool secure;
  final bool httpOnly;
  final CookieSameSite sameSite;
  final bool partitioned;
  final String? partitionKey;
  final bool inWebView;
  final bool inJar;
  final bool fieldsComplete;

  String get identityKey => SiteCookieManagerService.cookieIdentityKey(
    name: name,
    domain: domain,
    path: path,
  );
}

class SiteCookieDraft {
  const SiteCookieDraft({
    required this.host,
    required this.name,
    required this.value,
    this.domain,
    this.path = '/',
    this.expiresAt,
    this.secure = true,
    this.httpOnly = false,
    this.sameSite = CookieSameSite.unspecified,
    this.partitioned = false,
  });

  final String host;
  final String name;
  final String value;
  final String? domain;
  final String path;
  final DateTime? expiresAt;
  final bool secure;
  final bool httpOnly;
  final CookieSameSite sameSite;
  final bool partitioned;

  factory SiteCookieDraft.fromCookie(ManagedSiteCookie cookie) {
    return SiteCookieDraft(
      host: cookie.host,
      name: cookie.name,
      value: cookie.value,
      domain: cookie.hostOnly ? null : cookie.domain,
      path: cookie.path,
      expiresAt: cookie.expiresAt,
      secure: cookie.secure,
      httpOnly: cookie.httpOnly,
      sameSite: cookie.sameSite,
      partitioned: cookie.partitioned,
    );
  }
}

class _CookieAccumulator {
  _CookieAccumulator(this.cookie);

  ManagedSiteCookie cookie;

  void mergeWebView({
    required String host,
    required String name,
    required String value,
    required String domain,
    required String? rawDomain,
    required String path,
    required bool hostOnly,
    required DateTime? expiresAt,
    required bool secure,
    required bool httpOnly,
    required CookieSameSite sameSite,
    required bool partitioned,
    required bool fieldsComplete,
  }) {
    final current = cookie;
    cookie = ManagedSiteCookie(
      host: host,
      name: name,
      value: value,
      domain: domain,
      rawDomain: rawDomain ?? current.rawDomain,
      hostOnly: fieldsComplete ? hostOnly : current.hostOnly,
      path: fieldsComplete ? path : current.path,
      expiresAt: expiresAt ?? current.expiresAt,
      secure: fieldsComplete ? secure : current.secure,
      httpOnly: fieldsComplete ? httpOnly : current.httpOnly,
      sameSite: fieldsComplete ? sameSite : current.sameSite,
      partitioned: fieldsComplete ? partitioned : current.partitioned,
      partitionKey: current.partitionKey,
      inWebView: true,
      inJar: current.inJar,
      fieldsComplete: current.fieldsComplete || fieldsComplete,
    );
  }
}

/// Cookie manager used by the built-in browser.
///
/// WebView storage and the persistent CookieJar are treated as one logical
/// store. Mutations are mirrored to both sides and followed by a WebView
/// re-read so a partially failed platform operation is not reported as success.
class SiteCookieManagerService {
  SiteCookieManagerService._();

  static final SiteCookieManagerService instance = SiteCookieManagerService._();

  final CookieJarService _jar = CookieJarService();
  final RawCookieWriter _writer = RawCookieWriter.instance;

  Future<List<String>> discoverRelatedHosts(String currentUrl) {
    return SiteCookieCleanupService.instance.discoverRelatedHosts(currentUrl);
  }

  Future<List<ManagedSiteCookie>> listCookies(String currentUrl) async {
    final scope = _parseHttpUrl(currentUrl);
    if (!_jar.isInitialized) await _jar.initialize();

    final hosts = (await discoverRelatedHosts(currentUrl)).toSet();
    hosts.add(scope.host.toLowerCase());

    final jarCookies = await _jar.loadAllCanonicalCookies();
    final byIdentity = <String, _CookieAccumulator>{};

    for (final cookie in jarCookies) {
      final owner = _cookieOwner(
        cookie.normalizedDomain,
        Uri.tryParse(cookie.originUrl ?? '')?.host,
      );
      if (owner == null || !hosts.contains(owner)) continue;

      final originHost = _normalizeHost(
        Uri.tryParse(cookie.originUrl ?? '')?.host ?? owner,
      );
      final host = hosts.contains(originHost) ? originHost : owner;
      final path = _normalizePath(cookie.path);
      final key = cookieIdentityKey(
        name: cookie.name,
        domain: owner,
        path: path,
      );
      byIdentity[key] = _CookieAccumulator(
        ManagedSiteCookie(
          host: host,
          name: cookie.name,
          value: cookie.value,
          domain: owner,
          rawDomain: cookie.domain,
          hostOnly: cookie.hostOnly,
          path: path,
          expiresAt: cookie.expiresAt,
          secure: cookie.secure,
          httpOnly: cookie.httpOnly,
          sameSite: cookie.sameSite,
          partitioned: cookie.partitioned,
          partitionKey: cookie.partitionKey,
          inWebView: false,
          inJar: true,
          fieldsComplete: true,
        ),
      );
    }

    final probes = <String>{};
    for (final host in hosts) {
      final scheme = host == scope.host.toLowerCase() ? scope.scheme : 'https';
      probes.add(Uri(scheme: scheme, host: host, path: '/').toString());
    }
    probes.add(scope.toString());

    for (final cookie in jarCookies) {
      final owner = _cookieOwner(
        cookie.normalizedDomain,
        Uri.tryParse(cookie.originUrl ?? '')?.host,
      );
      if (owner == null || !hosts.contains(owner)) continue;
      final originHost = _normalizeHost(
        Uri.tryParse(cookie.originUrl ?? '')?.host ?? owner,
      );
      final host = hosts.contains(originHost) ? originHost : owner;
      final scheme = host == scope.host.toLowerCase() ? scope.scheme : 'https';
      probes.add(
        Uri(scheme: scheme, host: host, path: _normalizePath(cookie.path))
            .toString(),
      );
    }

    if (scope.path.isNotEmpty && scope.path != '/') {
      final segments = scope.pathSegments;
      for (var i = 1; i <= segments.length; i++) {
        probes.add(
          Uri(
            scheme: scope.scheme,
            host: scope.host,
            pathSegments: segments.take(i).toList(growable: false),
          ).toString(),
        );
      }
    }

    final probeResults = await Future.wait(
      probes.map((url) async => (url, await _writer.getAllCookieInfos(url))),
    );

    for (final (probeUrl, infos) in probeResults) {
      final probe = Uri.parse(probeUrl);
      final probeHost = probe.host.toLowerCase();
      for (final info in infos) {
        if (info.name.isEmpty) continue;
        final owner = _normalizeNullableHost(info.domain) ?? probeHost;
        if (!hosts.contains(owner)) continue;

        var path = info.path == null ? '/' : _normalizePath(info.path!);
        var key = cookieIdentityKey(
          name: info.name,
          domain: owner,
          path: path,
        );
        var existing = byIdentity[key];

        if (info.path == null) {
          final candidates = byIdentity.values
              .where(
                (entry) =>
                    entry.cookie.name == info.name &&
                    entry.cookie.domain == owner &&
                    entry.cookie.value == info.value,
              )
              .toList(growable: false);
          if (candidates.length == 1) {
            existing = candidates.single;
            path = existing.cookie.path;
            key = existing.cookie.identityKey;
          }
        }

        final fieldsComplete = info.path != null;
        final hostOnly = info.domain == null || info.domain!.trim().isEmpty;
        final sameSite = _parseSameSite(info.sameSite);
        final expiresAt = info.expiresMillis == null || info.expiresMillis! <= 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                info.expiresMillis!,
                isUtc: true,
              );

        if (existing == null) {
          byIdentity[key] = _CookieAccumulator(
            ManagedSiteCookie(
              host: probeHost,
              name: info.name,
              value: info.value,
              domain: owner,
              rawDomain: info.domain,
              hostOnly: hostOnly,
              path: path,
              expiresAt: expiresAt,
              secure: info.isSecure ?? probe.scheme == 'https',
              httpOnly: info.isHttpOnly ?? false,
              sameSite: sameSite,
              partitioned: info.isPartitioned ?? false,
              inWebView: true,
              inJar: false,
              fieldsComplete: fieldsComplete,
            ),
          );
        } else {
          existing.mergeWebView(
            host: existing.cookie.host,
            name: info.name,
            value: info.value,
            domain: owner,
            rawDomain: info.domain,
            path: path,
            hostOnly: hostOnly,
            expiresAt: expiresAt,
            secure: info.isSecure ?? existing.cookie.secure,
            httpOnly: info.isHttpOnly ?? existing.cookie.httpOnly,
            sameSite: sameSite,
            partitioned: info.isPartitioned ?? existing.cookie.partitioned,
            fieldsComplete: fieldsComplete,
          );
        }
      }
    }

    final result = byIdentity.values.map((entry) => entry.cookie).toList()
      ..sort((a, b) {
        final domainCompare = a.domain.compareTo(b.domain);
        if (domainCompare != 0) return domainCompare;
        final nameCompare = a.name.compareTo(b.name);
        if (nameCompare != 0) return nameCompare;
        return b.path.length.compareTo(a.path.length);
      });
    return result;
  }

  Future<void> saveCookie(
    String currentUrl,
    SiteCookieDraft draft, {
    ManagedSiteCookie? original,
  }) async {
    final scope = _parseHttpUrl(currentUrl);
    if (!_jar.isInitialized) await _jar.initialize();

    final hosts = (await discoverRelatedHosts(currentUrl)).toSet()
      ..add(scope.host.toLowerCase());
    final host = _normalizeHost(draft.host);
    if (!hosts.contains(host)) {
      throw ArgumentError('Cookie host is outside the current site scope.');
    }

    final name = draft.name.trim();
    if (name.isEmpty || _invalidCookieName.hasMatch(name)) {
      throw ArgumentError('Invalid cookie name.');
    }
    if (_invalidCookieValue.hasMatch(draft.value)) {
      throw ArgumentError('Cookie value contains unsupported control characters.');
    }

    final path = _normalizePath(draft.path);
    final rawDomain = draft.domain?.trim();
    final hostOnly = rawDomain == null || rawDomain.isEmpty;
    final domain = hostOnly ? host : _normalizeHost(rawDomain);
    if (!hostOnly && host != domain && !host.endsWith('.$domain')) {
      throw ArgumentError('Domain must be the cookie host or one of its parents.');
    }

    final secure =
        draft.secure || draft.sameSite == CookieSameSite.none || draft.partitioned;
    final scheme = secure ? 'https' : scope.scheme;
    final origin = Uri(scheme: scheme, host: host, path: '/');
    final canonical = CanonicalCookie(
      name: name,
      value: draft.value,
      domain: domain,
      path: path,
      expiresAt: draft.expiresAt?.toUtc(),
      secure: secure,
      httpOnly: draft.httpOnly,
      sameSite: draft.sameSite,
      hostOnly: hostOnly,
      persistent: draft.expiresAt != null,
      partitionKey: draft.partitioned ? original?.partitionKey : null,
      partitioned: draft.partitioned,
      originUrl: origin.toString(),
      source: CookieSource.manualRestore,
      rawSetCookie: null,
    );

    final written = await _writer.setRawCookie(
      origin.toString(),
      canonical.toSetCookieHeader(),
    );
    if (!written) {
      throw StateError('WebView rejected the cookie write.');
    }

    final jar = _jar.cookieJar;
    if (jar is EnhancedPersistCookieJar) {
      await jar.saveCanonicalCookies(origin, [canonical], trusted: true);
    } else {
      await jar.saveFromResponse(origin, [canonical.toIoCookie()]);
    }

    final nextIdentity = cookieIdentityKey(
      name: name,
      domain: domain,
      path: path,
    );
    if (original != null && original.identityKey != nextIdentity) {
      await _deleteCookieStorageOnly(original);
    }

    final verified = await _verifyWrite(origin.toString(), canonical);
    if (!verified) {
      throw StateError('Cookie write could not be verified in WebView storage.');
    }

    CookieStoreObserver.instance.notifyExternalChange();
  }

  Future<void> deleteCookie(
    String currentUrl,
    ManagedSiteCookie cookie,
  ) async {
    _parseHttpUrl(currentUrl);
    if (!_jar.isInitialized) await _jar.initialize();

    await _deleteCookieStorageOnly(cookie);
    if (await _stillContainsExactCookie(cookie)) {
      throw StateError(
        'WebView still contains the cookie after deletion. '
        'The platform cookie store may be refusing this variant.',
      );
    }
    CookieStoreObserver.instance.notifyExternalChange();
  }

  Future<void> deleteCookies(
    String currentUrl,
    Iterable<ManagedSiteCookie> cookies,
  ) async {
    _parseHttpUrl(currentUrl);
    if (!_jar.isInitialized) await _jar.initialize();

    final unique = <String, ManagedSiteCookie>{
      for (final cookie in cookies) cookie.identityKey: cookie,
    }.values.toList(growable: false);
    if (unique.isEmpty) return;

    final requests = unique
        .map(
          (cookie) => (
            url: _cookieUrl(cookie),
            name: cookie.name,
            domain: cookie.hostOnly
                ? null
                : (cookie.rawDomain ?? cookie.domain),
            path: cookie.path,
          ),
        )
        .toList(growable: false);

    await _writer.deleteExactCookiesBatch(requests);

    final jar = _jar.cookieJar;
    if (jar is EnhancedPersistCookieJar) {
      for (final cookie in unique) {
        await jar.deleteCookieIdentity(
          name: cookie.name,
          domain: cookie.domain,
          path: cookie.path,
        );
      }
    } else {
      for (final cookie in unique) {
        await jar.delete(Uri.parse(_cookieUrl(cookie)), true);
      }
    }

    final residual = <String>[];
    for (final cookie in unique) {
      if (await _stillContainsExactCookie(cookie)) {
        residual.add(cookie.name);
      }
    }
    if (residual.isNotEmpty) {
      throw StateError(
        'Failed to remove \${residual.length} WebView cookie(s): '
        '\${residual.take(4).join(', ')}',
      );
    }

    CookieStoreObserver.instance.notifyExternalChange();
  }

  Future<void> clearHosts(String currentUrl, Iterable<String> rawHosts) async {
    final scope = _parseHttpUrl(currentUrl);
    final selected =
        rawHosts.map(_normalizeHost).where((e) => e.isNotEmpty).toSet();
    if (selected.isEmpty) return;

    final allowed = (await discoverRelatedHosts(currentUrl)).toSet()
      ..add(scope.host.toLowerCase());
    if (selected.any((host) => !allowed.contains(host))) {
      throw ArgumentError('A selected host is outside the current site scope.');
    }

    final snapshot = await listCookies(currentUrl);
    await deleteCookies(
      currentUrl,
      snapshot.where((cookie) => selected.contains(cookie.domain)),
    );

    final jar = _jar.cookieJar;
    if (jar is EnhancedPersistCookieJar) {
      await jar.deleteDomainsExactly(selected);
    }
    CookieStoreObserver.instance.notifyExternalChange();
  }

  Future<void> _deleteCookieStorageOnly(ManagedSiteCookie cookie) async {
    final deleted = await _writer.deleteExactCookie(
      url: _cookieUrl(cookie),
      name: cookie.name,
      domain: cookie.hostOnly ? null : (cookie.rawDomain ?? cookie.domain),
      path: cookie.path,
    );
    if (!deleted && cookie.inWebView) {
      await _writer.nukeAllVariants(
        url: _cookieUrl(cookie),
        name: cookie.name,
        domainCandidates: [
          cookie.hostOnly ? null : (cookie.rawDomain ?? cookie.domain),
        ],
        pathCandidates: [cookie.path],
      );
    }

    final jar = _jar.cookieJar;
    if (jar is EnhancedPersistCookieJar) {
      await jar.deleteCookieIdentity(
        name: cookie.name,
        domain: cookie.domain,
        path: cookie.path,
      );
    } else if (cookie.inJar) {
      await jar.delete(Uri.parse(_cookieUrl(cookie)), true);
    }
  }

  Future<bool> _verifyWrite(String url, CanonicalCookie expected) async {
    final infos = await _writer.getAllCookieInfos(url);
    for (final info in infos) {
      if (info.name != expected.name || info.value != expected.value) continue;
      if (info.path == null) return true;
      final owner = _normalizeNullableHost(info.domain) ?? Uri.parse(url).host;
      if (owner == expected.normalizedDomain &&
          _normalizePath(info.path!) == expected.path) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _stillContainsExactCookie(ManagedSiteCookie cookie) async {
    final infos = await _writer.getAllCookieInfos(_cookieUrl(cookie));
    for (final info in infos) {
      if (info.name != cookie.name) continue;
      if (info.path == null) continue;

      final owner = _normalizeNullableHost(info.domain) ?? cookie.host;
      if (owner == cookie.domain &&
          _normalizePath(info.path!) == cookie.path) {
        return true;
      }
    }
    return false;
  }

  static final RegExp _invalidCookieName = RegExp(
    r'[\x00-\x20\x7f()<>@,;:\\"/\[\]?={}]+',
  );
  static final RegExp _invalidCookieValue = RegExp(r'[\x00-\x1f\x7f;\r\n]');

  @visibleForTesting
  static String cookieIdentityKey({
    required String name,
    required String domain,
    required String path,
  }) {
    return '$name\\u0000\${_normalizeHost(domain)}\\u0000\${_normalizePath(path)}';
  }

  static Uri _parseHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw ArgumentError('A valid HTTP(S) URL is required.');
    }
    return uri;
  }

  static String _cookieUrl(ManagedSiteCookie cookie) {
    final scheme = cookie.secure ? 'https' : 'http';
    return Uri(
      scheme: scheme,
      host: cookie.host,
      path: cookie.path,
    ).toString();
  }

  static String? _cookieOwner(String? domain, String? originHost) {
    return _normalizeNullableHost(domain) ?? _normalizeNullableHost(originHost);
  }

  static String _normalizeHost(String value) {
    return value.trim().toLowerCase().replaceFirst(RegExp(r'^\\.'), '');
  }

  static String? _normalizeNullableHost(String? value) {
    if (value == null) return null;
    final normalized = _normalizeHost(value);
    return normalized.isEmpty ? null : normalized;
  }

  static String _normalizePath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '/';
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  static CookieSameSite _parseSameSite(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'lax':
        return CookieSameSite.lax;
      case 'strict':
        return CookieSameSite.strict;
      case 'none':
        return CookieSameSite.none;
      default:
        return CookieSameSite.unspecified;
    }
  }
}
