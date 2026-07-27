import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import 'discourse/discourse_service.dart';
import 'log/log_writer.dart';
import 'network/cookie/cookie_jar_service.dart';

/// 扫码登录 payload。
///
/// 由**已登录设备**把当前 `_t` 会话封装进短时二维码, **待登录设备**扫码后
/// 写入本地 cookie 并走与密码/浏览器授权一致的 [DiscourseService.finalizeNativeLoginSuccess]
/// 收口。
///
/// 协议 (v1):
/// ```
/// fluxdo://qr-login?v=1&t=<token>&u=<username>&exp=<unix_ms>
/// ```
/// - 仅含 Discourse 主站会话 cookie `_t`(足够完成登录)
/// - 默认 2 分钟 TTL,过期拒绝导入
/// - 不传密码;二维码等同临时分享登录态,UI 需提示勿外泄
class QrLoginPayload {
  const QrLoginPayload({
    required this.version,
    required this.token,
    required this.username,
    required this.expiresAt,
  });

  final int version;
  final String token;
  final String username;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt.toUtc());

  Duration get remaining {
    final left = expiresAt.toUtc().difference(DateTime.now().toUtc());
    return left.isNegative ? Duration.zero : left;
  }
}

/// 扫码登录结果
enum QrLoginError {
  /// 不是 FluxDO 扫码登录二维码 / 解析失败
  invalid,

  /// 版本不支持
  unsupportedVersion,

  /// 已过期
  expired,

  /// 本机当前没有可分享的登录会话(展示端)
  noSession,

  /// 写入 cookie 或收口失败
  applyFailed,
}

/// 扫码登录服务
class QrLoginService {
  QrLoginService._();
  static final QrLoginService instance = QrLoginService._();

  static const String scheme = 'fluxdo';
  static const String host = 'qr-login';
  static const int currentVersion = 1;

  /// 二维码默认有效期。短 TTL 降低被旁人拍下后滥用的窗口。
  static const Duration defaultTtl = Duration(minutes: 2);

  final _cookieJar = CookieJarService();

  /// 已登录设备:从本地 jar 组装可编码进二维码的 payload 字符串。
  Future<({String raw, QrLoginPayload payload})> buildPayload({
    Duration ttl = defaultTtl,
    String? username,
  }) async {
    final token = await _cookieJar.getTToken();
    if (token == null || token.isEmpty) {
      throw const QrLoginException(QrLoginError.noSession, '当前没有登录会话');
    }

    var resolvedUsername = username?.trim() ?? '';
    if (resolvedUsername.isEmpty) {
      try {
        resolvedUsername = await DiscourseService().getUsername() ?? '';
      } catch (e) {
        debugPrint('[QrLogin] 取 username 失败(可忽略): $e');
      }
    }

    final expiresAt = DateTime.now().toUtc().add(ttl);
    final payload = QrLoginPayload(
      version: currentVersion,
      token: token,
      username: resolvedUsername,
      expiresAt: expiresAt,
    );
    final raw = encodePayload(payload);
    _log('info', 'qr_login_payload_built', '已生成扫码登录二维码 payload', {
      'ttlSec': ttl.inSeconds,
      'username': resolvedUsername,
      'tokenLen': token.length,
    });
    return (raw: raw, payload: payload);
  }

  /// 把 [payload] 编码为二维码字符串(稳定、可单测)。
  String encodePayload(QrLoginPayload payload) {
    return Uri(
      scheme: scheme,
      host: host,
      queryParameters: {
        'v': '${payload.version}',
        't': payload.token,
        'u': payload.username,
        'exp': '${payload.expiresAt.toUtc().millisecondsSinceEpoch}',
      },
    ).toString();
  }

  /// 解析扫到的原始字符串。非法内容返回 null(不抛)。
  QrLoginPayload? parsePayload(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme != scheme) return null;
    // 兼容 fluxdo://qr-login?... (host) 与 fluxdo:///qr-login?... (path)
    final hostOrPath = uri.host.isNotEmpty
        ? uri.host
        : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
    if (hostOrPath != host) return null;

    final version = int.tryParse(uri.queryParameters['v'] ?? '');
    final token = uri.queryParameters['t']?.trim() ?? '';
    final username = uri.queryParameters['u']?.trim() ?? '';
    final expMs = int.tryParse(uri.queryParameters['exp'] ?? '');
    if (version == null || token.isEmpty || expMs == null) return null;
    if (expMs <= 0) return null;

    return QrLoginPayload(
      version: version,
      token: token,
      username: username,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expMs, isUtc: true),
    );
  }

  /// 校验并返回可用 payload;失败抛 [QrLoginException]。
  QrLoginPayload requireValidPayload(String raw) {
    final payload = parsePayload(raw);
    if (payload == null) {
      throw const QrLoginException(QrLoginError.invalid, '无效的登录二维码');
    }
    if (payload.version != currentVersion) {
      throw const QrLoginException(
        QrLoginError.unsupportedVersion,
        '二维码版本不受支持,请升级 App',
      );
    }
    if (payload.isExpired) {
      throw const QrLoginException(QrLoginError.expired, '二维码已过期,请让对方刷新');
    }
    return payload;
  }

  /// 待登录设备:用扫到的内容完成登录。
  ///
  /// 成功返回解析出的用户名(可能为空);失败抛 [QrLoginException]。
  Future<String> loginWithScannedContent(String raw) async {
    final payload = requireValidPayload(raw);

    try {
      await _cookieJar.setCookie(
        '_t',
        payload.token,
        httpOnly: true,
        trusted: true,
      );
      final written = await _cookieJar.getTToken();
      if (written == null || written.isEmpty || written != payload.token) {
        throw const QrLoginException(
          QrLoginError.applyFailed,
          '写入登录凭证失败',
        );
      }

      final identifier = payload.username.isNotEmpty
          ? payload.username
          : 'user';
      await DiscourseService().finalizeNativeLoginSuccess(identifier);

      _log('info', 'qr_login_success', '扫码登录成功', {
        'username': payload.username,
        'tokenLen': payload.token.length,
      });
      return payload.username;
    } on QrLoginException {
      rethrow;
    } catch (e, st) {
      debugPrint('[QrLogin] 应用登录态失败: $e\n$st');
      _log('warning', 'qr_login_apply_failed', '扫码登录收口失败', {
        'error': e.toString(),
      });
      throw QrLoginException(QrLoginError.applyFailed, '登录失败: $e');
    }
  }

  /// 从图片字节解码二维码文本(相册/截图兜底,全平台可用)。
  /// 找不到二维码返回 null。
  Future<String?> decodeQrFromImageBytes(Uint8List bytes) async {
    try {
      return await compute(_decodeQrInIsolate, bytes);
    } catch (e) {
      debugPrint('[QrLogin] 图片解码二维码失败: $e');
      return null;
    }
  }

  void _log(
    String level,
    String event,
    String message, [
    Map<String, dynamic>? fields,
  ]) {
    LogWriter.instance.write({
      'timestamp': DateTime.now().toIso8601String(),
      'level': level,
      'type': 'auth',
      'event': event,
      'message': message,
      ...?fields,
    });
  }
}

/// 扫码登录业务异常
class QrLoginException implements Exception {
  const QrLoginException(this.error, this.message);
  final QrLoginError error;
  final String message;

  @override
  String toString() => 'QrLoginException($error): $message';
}

/// isolate 入口:图片 → 二维码文本
String? _decodeQrInIsolate(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;

  // 大图缩到合理宽度,加快解码且不伤识别
  final src = image.width > 1200
      ? img.copyResize(image, width: 1200)
      : image;

  final abgr = src
      .convert(numChannels: 4)
      .getBytes(order: img.ChannelOrder.abgr)
      .buffer
      .asInt32List();
  final source = RGBLuminanceSource(src.width, src.height, abgr);
  final bitmap = BinaryBitmap(HybridBinarizer(source));
  try {
    return QRCodeReader().decode(bitmap).text;
  } catch (_) {
    // 反色再试一次(深色主题截图常见)
    try {
      final inverted = BinaryBitmap(
        HybridBinarizer(InvertedLuminanceSource(source)),
      );
      return QRCodeReader().decode(inverted).text;
    } catch (_) {
      return null;
    }
  }
}
