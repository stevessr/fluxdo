import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:rhttp/rhttp.dart' as rhttp;

import '../doh/network_settings_service.dart';
import '../proxy/proxy_settings_service.dart';
import '../rhttp/rhttp_settings_service.dart';
import '../system_proxy_service.dart';

const _http3FailureBackoff = Duration(minutes: 10);
const _http3SuccessTtl = Duration(hours: 1);
const _http3ConnectTimeout = Duration(seconds: 3);
const _normalConnectTimeout = Duration(seconds: 30);

/// 基于 rhttp (Rust reqwest) 的 Dio 适配器。
///
/// 直连 HTTPS 的可安全重放请求优先探测 HTTP/3/QUIC；成功后按 host 记忆，
/// 失败则立即回退 HTTP/2/1.1 并短期熔断 H3，避免 UDP 被阻断时反复等待。
/// 代理/本地中转仍使用普通 HTTP/2/1.1 链路。
class RhttpAdapter implements HttpClientAdapter {
  RhttpAdapter(this._networkSettings, this._proxySettings);

  final NetworkSettingsService _networkSettings;
  final ProxySettingsService _proxySettings;

  final Map<String, _RhttpDelegate> _delegates = {};
  final Map<String, Future<_RhttpDelegate>> _delegateBuilds = {};
  final Map<String, String> _delegateBuildFingerprints = {};
  final Map<String, String> _clientFingerprints = {};
  final Map<String, int> _clientBuildTokens = {};
  final Map<String, rhttp.RhttpClient> _clients = {};
  final Map<String, _Http3Capability> _http3Capabilities = {};

  int _buildEpoch = 0;
  int _settingsVersion = -1;
  int _proxyVersion = -1;
  int _rhttpVersion = -1;
  int _systemProxyVersion = -1;
  bool _closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_closed) {
      throw StateError(
        "Can't establish connection after the adapter was closed.",
      );
    }

    final baseConfig = await _prepareClientConfig(options.uri.host);
    final shouldTryHttp3 = _shouldTryHttp3(options, requestStream, baseConfig);

    if (shouldTryHttp3) {
      final http3Config = baseConfig.withHttpVersion(rhttp.HttpVersionPref.http3);
      try {
        final response = await _fetchOnce(
          options,
          requestStream,
          cancelFuture,
          http3Config,
        );
        if (response.version == rhttp.HttpVersion.http3) {
          _markHttp3Success(baseConfig.host);
        }
        _markConfigSuccess(http3Config, response.remoteIp);
        return response.responseBody;
      } catch (error) {
        if (!_canFallbackFromHttp3(error)) {
          rethrow;
        }
        _markHttp3Failure(baseConfig.host);
        debugPrint(
          '[DIO] RhttpAdapter HTTP/3 failed for ${baseConfig.host}; '
          'falling back to HTTP/2/1.1: $error',
        );
      }
    }

    return _fetchWithAlternateIpRetry(
      options,
      requestStream,
      cancelFuture,
      baseConfig.withHttpVersion(rhttp.HttpVersionPref.all),
    );
  }

  Future<ResponseBody> _fetchWithAlternateIpRetry(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
    _PreparedClientConfig config,
  ) async {
    try {
      final response = await _fetchOnce(
        options,
        requestStream,
        cancelFuture,
        config,
      );
      _markConfigSuccess(config, response.remoteIp);
      return response.responseBody;
    } catch (error) {
      if (!_canRetryWithAlternateIp(options, requestStream, config, error)) {
        rethrow;
      }

      final attemptedIp = config.dnsOverrides.isNotEmpty
          ? config.dnsOverrides.first
          : null;
      _networkSettings.reportHostConnectionFailure(config.host, attemptedIp);

      final retryConfig = (await _prepareClientConfig(config.host))
          .withHttpVersion(rhttp.HttpVersionPref.all);
      if (retryConfig.clientFingerprint == config.clientFingerprint) {
        rethrow;
      }

      debugPrint(
        '[DIO] RhttpAdapter 切换 IP 重试 ${config.host} '
        '(${attemptedIp ?? "system"} -> '
        '${retryConfig.dnsOverrides.isEmpty ? "system" : retryConfig.dnsOverrides.join(", ")})',
      );
      final response = await _fetchOnce(
        options,
        requestStream,
        cancelFuture,
        retryConfig,
      );
      _markConfigSuccess(retryConfig, response.remoteIp);
      return response.responseBody;
    }
  }

  Future<_RhttpFetchResult> _fetchOnce(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
    _PreparedClientConfig config,
  ) async {
    final delegate = await _ensureDelegate(config);
    return delegate.fetch(options, requestStream, cancelFuture);
  }

  bool _shouldTryHttp3(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    _PreparedClientConfig config,
  ) {
    if (!requestCanProbeRhttpHttp3(
      options,
      hasRequestStream: requestStream != null,
    )) {
      return false;
    }
    if (!_usesDirectTransport()) {
      return false;
    }

    final capability = _http3Capabilities[config.host];
    if (capability == null) {
      return true;
    }
    if (DateTime.now().isAfter(capability.expiresAt)) {
      _http3Capabilities.remove(config.host);
      return true;
    }
    return capability.supported;
  }

  bool _usesDirectTransport() {
    final ns = _networkSettings.current;
    final ps = _proxySettings.current;

    if (ns.customHosts.isNotEmpty && ns.proxyPort != null) {
      return false;
    }
    if (ps.isValid) {
      return false;
    }
    if (SystemProxyService.instance.effectiveProxyUrl != null) {
      return false;
    }
    return true;
  }

  bool _canFallbackFromHttp3(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.cancel:
        case DioExceptionType.badCertificate:
        case DioExceptionType.badResponse:
          return false;
        default:
          return true;
      }
    }
    return true;
  }

  void _markHttp3Success(String host) {
    if (host.isEmpty) return;
    final previous = _http3Capabilities[host];
    _http3Capabilities[host] = _Http3Capability(
      supported: true,
      expiresAt: DateTime.now().add(_http3SuccessTtl),
    );
    if (previous?.supported != true) {
      debugPrint('[DIO] RhttpAdapter HTTP/3 available: $host');
    }
  }

  void _markHttp3Failure(String host) {
    if (host.isEmpty) return;
    _http3Capabilities[host] = _Http3Capability(
      supported: false,
      expiresAt: DateTime.now().add(_http3FailureBackoff),
    );
  }

  Future<_RhttpDelegate> _ensureDelegate(_PreparedClientConfig config) {
    final settingsVersion = _networkSettings.version;
    final proxyVersion = _proxySettings.version;
    final rhttpVersion = RhttpSettingsService.instance.version;
    final systemProxyVersion = SystemProxyService.instance.version.value;

    final configChanged =
        _settingsVersion != settingsVersion ||
        _proxyVersion != proxyVersion ||
        _rhttpVersion != rhttpVersion ||
        _systemProxyVersion != systemProxyVersion;
    if (configChanged) {
      _disposeAllClients();
      _settingsVersion = settingsVersion;
      _proxyVersion = proxyVersion;
      _rhttpVersion = rhttpVersion;
      _systemProxyVersion = systemProxyVersion;
    }

    final clientKey = config.clientKey;
    final fingerprint = config.clientFingerprint;
    final delegate = _delegates[clientKey];
    if (delegate != null && _clientFingerprints[clientKey] == fingerprint) {
      return Future.value(delegate);
    }

    final building = _delegateBuilds[clientKey];
    if (building != null &&
        _delegateBuildFingerprints[clientKey] == fingerprint) {
      return building;
    }

    final buildToken = (_clientBuildTokens[clientKey] ?? 0) + 1;
    _clientBuildTokens[clientKey] = buildToken;

    final future = _rebuildDelegate(config, _buildEpoch, buildToken);
    _delegateBuilds[clientKey] = future;
    _delegateBuildFingerprints[clientKey] = fingerprint;
    return future.whenComplete(() {
      if (identical(_delegateBuilds[clientKey], future)) {
        _delegateBuilds.remove(clientKey);
        _delegateBuildFingerprints.remove(clientKey);
      }
    });
  }

  Future<_RhttpDelegate> _rebuildDelegate(
    _PreparedClientConfig config,
    int buildEpoch,
    int buildToken,
  ) async {
    final client = await _createClient(config);
    final clientKey = config.clientKey;
    final stillCurrent =
        !_closed &&
        buildEpoch == _buildEpoch &&
        _clientBuildTokens[clientKey] == buildToken;
    if (!stillCurrent) {
      client.dispose(cancelRunningRequests: true);
      final existing = _delegates[clientKey];
      if (existing != null) {
        return existing;
      }
      return _ensureDelegate(config);
    }

    final delegate = _RhttpDelegate(client);
    _clients.remove(clientKey)?.dispose(cancelRunningRequests: true);
    _clients[clientKey] = client;
    _delegates[clientKey] = delegate;
    _clientFingerprints[clientKey] = config.clientFingerprint;

    debugPrint(
      '[DIO] RhttpAdapter 重建完成 ${config.host} '
      '(HTTP: ${config.httpVersionPref.name}, '
      'DNS: ${config.dnsOverrides.isEmpty ? "system" : config.dnsOverrides.join(", ")}'
      '${config.stickyIp != null ? " [sticky]" : ""}, '
      'ECH: ${config.echConfig == null ? "off" : "on"})',
    );
    return delegate;
  }

  Future<_PreparedClientConfig> _prepareClientConfig(String host) async {
    final normalizedHost = host.trim().toLowerCase();
    final ns = _networkSettings.current;
    final resolvedHost = await _networkSettings.resolveHostForRequest(
      normalizedHost,
    );

    return _PreparedClientConfig(
      host: normalizedHost,
      hostKey: normalizedHost.isEmpty ? '__default__' : normalizedHost,
      dnsOverrides: resolvedHost.dnsOverrides,
      stickyIp: resolvedHost.preferredIp,
      echConfig: resolvedHost.echConfig,
      dohEnabled: ns.dohEnabled,
      httpVersionPref: rhttp.HttpVersionPref.all,
    );
  }

  bool _canRetryWithAlternateIp(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    _PreparedClientConfig config,
    Object error,
  ) {
    if (requestStream != null) {
      return false;
    }

    final method = options.method.toUpperCase();
    if (method != 'GET' && method != 'HEAD' && method != 'OPTIONS') {
      return false;
    }

    if (config.host.isEmpty || config.dnsOverrides.isEmpty) {
      return false;
    }

    return _isRetryableConnectionFailure(error);
  }

  bool _isRetryableConnectionFailure(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionError:
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return true;
        case DioExceptionType.badCertificate:
        case DioExceptionType.badResponse:
        case DioExceptionType.cancel:
          return false;
        case DioExceptionType.unknown:
          final inner = error.error;
          if (inner != null && !identical(inner, error)) {
            return _isRetryableConnectionFailure(inner);
          }
          break;
        default:
          break;
      }
    }

    if (error is SocketException) {
      return true;
    }

    final text = error.toString().toLowerCase();
    return text.contains('rhttpconnectionexception') ||
        text.contains('rhttptimeoutexception') ||
        text.contains('connection reset by peer') ||
        text.contains('connection error') ||
        text.contains('timed out') ||
        text.contains('timeout') ||
        text.contains('broken pipe') ||
        text.contains('connection aborted') ||
        text.contains('connection refused') ||
        text.contains('network is unreachable') ||
        text.contains('no route to host') ||
        text.contains('eof');
  }

  void _markConfigSuccess(_PreparedClientConfig config, String? remoteIp) {
    if (config.host.isEmpty) {
      return;
    }
    final successIp =
        _normalizeIp(remoteIp) ??
        (config.dnsOverrides.length == 1
            ? _normalizeIp(config.dnsOverrides.first)
            : null);
    if (successIp == null) {
      return;
    }
    _networkSettings.reportHostConnectionSuccess(config.host, successIp);
  }

  Future<rhttp.RhttpClient> _createClient(_PreparedClientConfig config) async {
    final ns = _networkSettings.current;
    final ps = _proxySettings.current;
    final connectTimeout = config.httpVersionPref == rhttp.HttpVersionPref.http3
        ? _http3ConnectTimeout
        : _normalConnectTimeout;

    return rhttp.RhttpClient.create(
      settings: rhttp.ClientSettings(
        httpVersionPref: config.httpVersionPref,
        throwOnStatusCode: false,
        dnsSettings: config.toDnsSettings(),
        tlsSettings: rhttp.TlsSettings(echConfigList: config.echConfig),
        proxySettings: _buildProxySettings(ns, ps),
        cookieSettings: const rhttp.CookieSettings(storeCookies: false),
        redirectSettings: const rhttp.RedirectSettings.none(),
        timeoutSettings: rhttp.TimeoutSettings(
          connectTimeout: connectTimeout,
          timeout: const Duration(minutes: 10),
          keepAliveTimeout: const Duration(seconds: 60),
        ),
      ),
    );
  }

  String? _normalizeIp(String? raw) {
    if (raw == null) {
      return null;
    }
    return InternetAddress.tryParse(raw.trim())?.address;
  }

  rhttp.ProxySettings _buildProxySettings(
    NetworkSettings ns,
    ProxySettings ps,
  ) {
    final localProxyPort = ns.proxyPort;
    if (ns.customHosts.isNotEmpty && localProxyPort != null) {
      return rhttp.ProxySettings.proxy('http://127.0.0.1:$localProxyPort');
    }

    if (!ps.isValid) {
      final systemProxy = SystemProxyService.instance.effectiveProxyUrl;
      if (systemProxy != null) {
        return rhttp.ProxySettings.proxy(systemProxy);
      }
      return const rhttp.ProxySettings.noProxy();
    }

    if (ps.isShadowsocks) {
      final port = ns.proxyPort;
      if (port == null) return const rhttp.ProxySettings.noProxy();
      return rhttp.ProxySettings.proxy('http://127.0.0.1:$port');
    }

    final scheme = ps.protocol == UpstreamProxyProtocol.socks5
        ? 'socks5'
        : 'http';
    if (ps.username != null && ps.username!.isNotEmpty) {
      return rhttp.ProxySettings.proxy(
        '$scheme://${ps.username}:${ps.password ?? ""}@${ps.host}:${ps.port}',
      );
    }
    return rhttp.ProxySettings.proxy('$scheme://${ps.host}:${ps.port}');
  }

  @override
  void close({bool force = false}) {
    _closed = true;
    _disposeAllClients(force: force, clearHttp3Capabilities: true);
  }

  void _disposeAllClients({
    bool force = false,
    bool clearHttp3Capabilities = false,
  }) {
    _buildEpoch++;
    _delegateBuilds.clear();
    _delegateBuildFingerprints.clear();
    _clientFingerprints.clear();
    _clientBuildTokens.clear();
    if (clearHttp3Capabilities) {
      _http3Capabilities.clear();
    }
    for (final client in _clients.values) {
      client.dispose(cancelRunningRequests: force);
    }
    _clients.clear();
    _delegates.clear();
  }
}

@visibleForTesting
bool requestCanProbeRhttpHttp3(
  RequestOptions options, {
  bool hasRequestStream = false,
}) {
  if (hasRequestStream) return false;
  final uri = options.uri;
  if (uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
    return false;
  }
  final method = options.method.toUpperCase();
  return method == 'GET' || method == 'HEAD' || method == 'OPTIONS';
}

class _Http3Capability {
  const _Http3Capability({required this.supported, required this.expiresAt});

  final bool supported;
  final DateTime expiresAt;
}

class _RhttpFetchResult {
  const _RhttpFetchResult({
    required this.responseBody,
    required this.remoteIp,
    required this.version,
  });

  final ResponseBody responseBody;
  final String? remoteIp;
  final rhttp.HttpVersion version;
}

class _RhttpDelegate {
  const _RhttpDelegate(this.client);

  final rhttp.RhttpClient client;

  Future<_RhttpFetchResult> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final cancelToken = rhttp.CancelToken();
    cancelFuture?.whenComplete(cancelToken.cancel);

    try {
      final response = await client.requestStream(
        method: rhttp.HttpMethod(options.method.toUpperCase()),
        url: options.uri.toString(),
        headers: _buildHeaders(options),
        body: _buildBody(options, requestStream),
        cancelToken: cancelToken,
      );

      final responseBody = ResponseBody(
        response.body.cast<Uint8List>().handleError(
          (error) {},
          test: (error) => error.toString().contains('STREAM_CANCEL_ERROR'),
        ),
        response.statusCode,
        headers: response.headerMapList,
        isRedirect: false,
      )
        ..extra['remote_ip'] = response.remoteIp
        ..extra['http_version'] = response.version.name;

      return _RhttpFetchResult(
        responseBody: responseBody,
        remoteIp: response.remoteIp,
        version: response.version,
      );
    } on rhttp.RhttpException catch (error) {
      throw _mapRhttpException(options, error);
    }
  }

  rhttp.HttpHeaders? _buildHeaders(RequestOptions options) {
    if (options.headers.isEmpty) {
      return null;
    }

    final headers = <String, String>{};
    options.headers.forEach((key, value) {
      if (value == null) {
        return;
      }
      final headerValue = switch (value) {
        Iterable<Object?> values =>
          values
              .where((e) => e != null)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .join(', '),
        _ => value.toString().trim(),
      };
      if (headerValue.isNotEmpty) {
        headers[key] = headerValue;
      }
    });
    if (headers.isEmpty) {
      return null;
    }
    return rhttp.HttpHeaders.rawMap(headers);
  }

  rhttp.HttpBody? _buildBody(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
  ) {
    if (requestStream != null) {
      final contentLength = int.tryParse(
        options.headers['content-length']?.toString() ?? '',
      );
      return rhttp.HttpBody.stream(
        requestStream,
        length: contentLength != null && contentLength >= 0
            ? contentLength
            : null,
      );
    }

    final data = options.data;
    if (data == null) {
      return null;
    }
    if (data is Uint8List) {
      return rhttp.HttpBody.bytes(data);
    }
    if (data is List<int>) {
      return rhttp.HttpBody.bytes(Uint8List.fromList(data));
    }
    if (data is String) {
      return rhttp.HttpBody.text(data);
    }
    if (data is Map<String, String>) {
      return rhttp.HttpBody.form(data);
    }
    return rhttp.HttpBody.json(data);
  }

  DioException _mapRhttpException(
    RequestOptions options,
    rhttp.RhttpException error,
  ) {
    if (error is rhttp.RhttpCancelException) {
      return DioException(
        requestOptions: options,
        error: error,
        type: DioExceptionType.cancel,
        message: error.toString(),
      );
    }
    if (error is rhttp.RhttpTimeoutException) {
      return DioException.connectionTimeout(
        requestOptions: options,
        timeout:
            options.connectTimeout ?? options.receiveTimeout ?? Duration.zero,
        error: error,
      );
    }
    if (error is rhttp.RhttpInvalidCertificateException) {
      return DioException.badCertificate(requestOptions: options, error: error);
    }
    if (error is rhttp.RhttpConnectionException) {
      return DioException.connectionError(
        requestOptions: options,
        reason: error.message,
        error: error,
      );
    }
    if (error is rhttp.RhttpStatusCodeException) {
      return DioException.badResponse(
        statusCode: error.statusCode,
        requestOptions: options,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: error.statusCode,
          headers: Headers.fromMap(error.headerMapList),
          data: error.body,
        ),
      );
    }
    return DioException(
      requestOptions: options,
      error: error,
      type: DioExceptionType.unknown,
    );
  }
}

class _PreparedClientConfig {
  const _PreparedClientConfig({
    required this.host,
    required this.hostKey,
    required this.dnsOverrides,
    required this.stickyIp,
    required this.echConfig,
    required this.dohEnabled,
    required this.httpVersionPref,
  });

  final String host;
  final String hostKey;
  final List<String> dnsOverrides;
  final String? stickyIp;
  final Uint8List? echConfig;
  final bool dohEnabled;
  final rhttp.HttpVersionPref httpVersionPref;

  String get clientKey => '$hostKey|${httpVersionPref.name}';

  String get clientFingerprint {
    final dnsPart = dnsOverrides.isEmpty ? 'system' : dnsOverrides.join(',');
    final echPart = echConfig == null || echConfig!.isEmpty
        ? 'no-ech'
        : '${echConfig!.length}:${Object.hashAll(echConfig!)}';
    return '$dohEnabled|$dnsPart|$echPart|${httpVersionPref.name}';
  }

  _PreparedClientConfig withHttpVersion(rhttp.HttpVersionPref value) {
    return _PreparedClientConfig(
      host: host,
      hostKey: hostKey,
      dnsOverrides: dnsOverrides,
      stickyIp: stickyIp,
      echConfig: echConfig,
      dohEnabled: dohEnabled,
      httpVersionPref: value,
    );
  }

  rhttp.DnsSettings? toDnsSettings() {
    if (host.isEmpty || dnsOverrides.isEmpty) {
      return null;
    }
    return rhttp.DnsSettings.static(overrides: {host: dnsOverrides});
  }
}
