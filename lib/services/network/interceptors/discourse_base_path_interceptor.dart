import 'package:dio/dio.dart';

/// Keeps relative Discourse API requests inside the configured
/// `relative_url_root`.
///
/// Dio resolves a request path beginning with `/` against the origin root. If
/// the active site lives at `https://example.com/forum`, a normal
/// `dio.get('/latest.json')` would therefore incorrectly request
/// `https://example.com/latest.json`. FluxDO historically targets a root-mounted
/// site, so most call sites correctly use leading-slash Discourse paths. This
/// interceptor centralizes the sub-path adjustment instead of requiring every
/// API call to know about the active instance deployment shape.
class DiscourseBasePathInterceptor extends Interceptor {
  DiscourseBasePathInterceptor(String baseUrl)
    : _basePath = _normalizeBasePath(Uri.parse(baseUrl).path);

  final String _basePath;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.path = resolvePath(_basePath, options.path);
    handler.next(options);
  }

  /// Pure resolver exposed for contract tests.
  static String resolvePath(String basePath, String requestPath) {
    final normalizedBase = _normalizeBasePath(basePath);
    if (normalizedBase.isEmpty || requestPath.isEmpty) return requestPath;

    // `//host/path` is a protocol-relative absolute URL. Uri.hasScheme is false
    // for this form, so it must be checked before treating the value as a local
    // leading-slash Discourse path.
    if (requestPath.startsWith('//')) return requestPath;

    final absolute = Uri.tryParse(requestPath);
    if (absolute != null && absolute.hasScheme) return requestPath;

    final queryIndex = requestPath.indexOf('?');
    final fragmentIndex = requestPath.indexOf('#');
    var suffixIndex = requestPath.length;
    if (queryIndex >= 0 && queryIndex < suffixIndex) suffixIndex = queryIndex;
    if (fragmentIndex >= 0 && fragmentIndex < suffixIndex) {
      suffixIndex = fragmentIndex;
    }

    final rawPath = requestPath.substring(0, suffixIndex);
    final suffix = requestPath.substring(suffixIndex);
    final normalizedRequest = rawPath.startsWith('/') ? rawPath : '/$rawPath';

    if (normalizedRequest == normalizedBase ||
        normalizedRequest.startsWith('$normalizedBase/')) {
      return '$normalizedRequest$suffix';
    }

    return '$normalizedBase$normalizedRequest$suffix';
  }

  static String _normalizeBasePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty || trimmed == '/') return '';
    final leading = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return leading.replaceFirst(RegExp(r'/+$'), '');
  }
}
