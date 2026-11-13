/// Resolved entry point for the official Discourse Mini App runtime.
///
/// The website owns the loader, package decryption, signature validation and
/// sandboxed frame. Fluxdo must not execute an unpacked package itself.
class MiniAppRuntime {
  const MiniAppRuntime({required this.embedUrl});

  final Uri embedUrl;

  factory MiniAppRuntime.parse(
    Object? payload, {
    required Uri site,
    required String appId,
  }) {
    if (payload is! Map || payload['configuration'] is! Map) {
      throw const FormatException('Missing mini app runtime configuration');
    }
    final config = payload['configuration'] as Map;
    if (config['appId'] != appId ||
        config['channel'] != 'production') {
      throw const FormatException('Invalid mini app runtime configuration');
    }
    final rawUrl = config['embedUrl'];
    if (rawUrl is! String || rawUrl.trim().isEmpty) {
      throw const FormatException('Missing mini app embed URL');
    }

    // The /info response is server-controlled, but do not permit an arbitrary
    // redirect or a foreign host to become the privileged app container.
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != site.host.toLowerCase() ||
        uri.port != site.port ||
        uri.userInfo.isNotEmpty ||
        uri.pathSegments.length != 2 ||
        uri.pathSegments.first != 'apps' ||
        uri.pathSegments.last != appId ||
        uri.queryParameters['embed_mode'] != 'true') {
      throw const FormatException('Untrusted mini app embed URL');
    }
    return MiniAppRuntime(embedUrl: uri);
  }
}
