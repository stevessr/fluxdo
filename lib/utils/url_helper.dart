import '../config/discourse_instance_runtime.dart';
import '../constants.dart';
import '../services/preloaded_data_service.dart';

class UrlHelper {
  static String? _debugBaseUriOverride;
  static String? _debugCdnUrlOverride;
  static String? _debugS3CdnUrlOverride;
  static String? _debugS3BaseUrlOverride;

  /// 与 Discourse getURL 一致：仅补全站内相对路径，不走 CDN。
  static String resolveUrl(String url) {
    if (!_shouldResolve(url)) {
      return url;
    }

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    if (url.startsWith('//')) {
      return '$_activeScheme:$url';
    }

    if (_isRelativePath(url)) {
      return '$_origin${_withPrefix(url)}';
    }

    if (url == '/') {
      return '$_origin$_baseUriOrSlash';
    }

    return url;
  }

  /// 与 Discourse getURLWithCDN 一致：媒体资源优先走 CDN，并处理 S3 CDN 重写。
  static String resolveUrlWithCdn(String url) {
    if (!_shouldResolve(url)) {
      return url;
    }

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return _rewriteS3Cdn(url);
    }

    if (url.startsWith('//')) {
      return _rewriteS3Cdn(url);
    }

    if (_isRelativePath(url)) {
      final base = _cdnUrl ?? _origin;
      return '$base${_withPrefix(url)}';
    }

    if (url == '/') {
      return '${_cdnUrl ?? _origin}$_baseUriOrSlash';
    }

    return url;
  }

  static bool _shouldResolve(String url) {
    return url.isNotEmpty && !url.startsWith('upload://');
  }

  static bool _isRelativePath(String url) {
    return url.startsWith('/') && !url.startsWith('//');
  }

  static String withPrefix(String url) {
    if (!_shouldResolve(url)) {
      return url;
    }

    if (!_isRelativePath(url) && url != '/') {
      return url;
    }

    return _withPrefix(url);
  }

  /// 是否是"可信图片域名"(站点主域名/子域名,或站点配置的 CDN / S3 CDN)。
  ///
  /// linux.do 保留历史上的主域 + 子域信任模型；通用 Discourse 实例只默认
  /// 信任精确主机，CDN/S3 必须由站点自己下发，避免把任意子域自动提权。
  static bool isTrustedImageHost(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;

    bool hostMatches(String? base) {
      if (base == null || base.isEmpty) return false;
      final baseUri = Uri.tryParse(
        base.startsWith('//') ? '$_activeScheme:$base' : base,
      );
      final baseHost = baseUri?.host.toLowerCase() ?? '';
      if (baseHost.isEmpty) return false;
      return host == baseHost || host.endsWith('.$baseHost');
    }

    final siteBase = Uri.tryParse(AppConstants.baseUrl)?.host.toLowerCase();
    if (siteBase != null && siteBase.isNotEmpty) {
      if (host == siteBase) return true;
      if (DiscourseInstanceRuntime.isDefaultInstance &&
          host.endsWith('.$siteBase')) {
        return true;
      }
    }
    return hostMatches(_cdnUrl) || hostMatches(_s3CdnUrl);
  }

  static bool samePrefix(String url) {
    final prefix = _baseUri;
    if (prefix.isEmpty) {
      return true;
    }

    if (url.startsWith('/')) {
      return url == prefix || url.startsWith('$prefix/');
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    final path = uri.path.isEmpty ? '/' : uri.path;
    return path == prefix || path.startsWith('$prefix/');
  }

  static String _withPrefix(String url) {
    final prefix = _baseUri;
    if (prefix.isEmpty) {
      return url == '/' ? '/' : url;
    }

    if (url == '/') {
      return prefix;
    }

    if (url == prefix || url.startsWith('$prefix/')) {
      return url;
    }

    return '$prefix$url';
  }

  static String _rewriteS3Cdn(String url) {
    final s3Cdn = _s3CdnUrl;
    final s3Base = _s3BaseUrl;
    if (s3Cdn == null) {
      return url.startsWith('//') ? '$_activeScheme:$url' : url;
    }

    if (s3Base != null && url.startsWith(s3Base)) {
      return url.replaceFirst(s3Base, s3Cdn);
    }

    final s3BaseWithScheme = s3Base == null
        ? null
        : (s3Base.startsWith('//') ? '$_activeScheme:$s3Base' : s3Base);
    if (s3BaseWithScheme != null && url.startsWith(s3BaseWithScheme)) {
      return url.replaceFirst(s3BaseWithScheme, s3Cdn);
    }

    return url.startsWith('//') ? '$_activeScheme:$url' : url;
  }

  static String? get _cdnUrl =>
      _debugCdnUrlOverride ?? PreloadedDataService().cdnUrl;

  static String get _origin {
    final baseUri = Uri.parse(AppConstants.baseUrl);
    return '${baseUri.scheme}://${baseUri.authority}';
  }

  static String get _activeScheme => Uri.parse(AppConstants.baseUrl).scheme;

  static String get _baseUri {
    final preloaded = PreloadedDataService().baseUri;
    // 在首页 preload 尚未解析完成时，直接使用实例配置里的 relative-url-root。
    // debug override 显式传空字符串仍表示“强制按根部署测试”，不触发 fallback。
    final baseUri =
        _debugBaseUriOverride ??
        (preloaded.isNotEmpty
            ? preloaded
            : Uri.parse(AppConstants.baseUrl).path);
    if (baseUri.isEmpty || baseUri == '/') {
      return '';
    }
    return baseUri.startsWith('/') ? baseUri : '/$baseUri';
  }

  static String get _baseUriOrSlash => _baseUri.isEmpty ? '/' : _baseUri;

  static String? get _s3CdnUrl =>
      _debugS3CdnUrlOverride ?? PreloadedDataService().s3CdnUrl;

  static String? get _s3BaseUrl =>
      _debugS3BaseUrlOverride ?? PreloadedDataService().s3BaseUrl;

  static void debugSetOverrides({
    String? baseUri,
    String? cdnUrl,
    String? s3CdnUrl,
    String? s3BaseUrl,
  }) {
    _debugBaseUriOverride = baseUri;
    _debugCdnUrlOverride = cdnUrl;
    _debugS3CdnUrlOverride = s3CdnUrl;
    _debugS3BaseUrlOverride = s3BaseUrl;
  }

  static void debugClearOverrides() {
    _debugBaseUriOverride = null;
    _debugCdnUrlOverride = null;
    _debugS3CdnUrlOverride = null;
    _debugS3BaseUrlOverride = null;
  }
}
