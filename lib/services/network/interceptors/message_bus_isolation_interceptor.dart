import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../flux_request_spec.dart';

/// 把 MessageBus 长轮询声明为“只收消息”的网络通道。
///
/// MessageBus 可能使用主站 origin，也可能由 Discourse 配置到独立 origin。
/// 无论哪种情况，它的 401/403/CF 页面都不应该触发主论坛的 CSRF、认证状态、
/// 会话同步或恢复动作。把约束放在统一 Dio 层，避免前台/iOS 后台/未来调用方
/// 各自遗漏某个 extra 标记。
class MessageBusIsolationInterceptor extends Interceptor {
  MessageBusIsolationInterceptor(String baseUrl) : _baseUri = Uri.parse(baseUrl);

  final Uri _baseUri;

  @visibleForTesting
  static bool isMessageBusRequest(Uri uri, String baseUrl) {
    final base = Uri.parse(baseUrl);
    if (!_sameOrigin(uri, base)) return false;

    final root = _normalizeBasePath(base.path);
    final prefix = root.isEmpty ? '/message-bus' : '$root/message-bus';
    final path = uri.path.isEmpty ? '/' : uri.path;
    return path == prefix || path.startsWith('$prefix/');
  }

  @visibleForTesting
  static void applyIsolationFlags(Map<String, dynamic> extra) {
    extra[FluxRequestKeys.isSilent] = true;
    extra[FluxRequestKeys.skipCsrf] = true;
    extra[FluxRequestKeys.skipAuthCheck] = true;
    extra[FluxRequestKeys.skipSessionStateSync] = true;
    extra[FluxRequestKeys.skipCfChallenge] = true;
    extra[FluxRequestKeys.noRecovery] = true;
    extra[FluxRequestKeys.skipNetworkLog] = true;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (isMessageBusRequest(options.uri, _baseUri.toString())) {
      applyIsolationFlags(options.extra);
    }
    handler.next(options);
  }

  static bool _sameOrigin(Uri a, Uri b) {
    return a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
        a.host.toLowerCase() == b.host.toLowerCase() &&
        _effectivePort(a) == _effectivePort(b);
  }

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return switch (uri.scheme.toLowerCase()) {
      'https' => 443,
      'http' => 80,
      _ => -1,
    };
  }

  static String _normalizeBasePath(String path) {
    if (path.isEmpty || path == '/') return '';
    final withLeadingSlash = path.startsWith('/') ? path : '/$path';
    return withLeadingSlash.replaceFirst(RegExp(r'/+$'), '');
  }
}
