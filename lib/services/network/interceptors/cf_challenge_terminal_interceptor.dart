import 'package:dio/dio.dart';

import '../../cf_challenge_service.dart';
import '../exceptions/api_exception.dart';
import '../flux_request_spec.dart';

/// CF 恢复链的最后一道类型化兜底。
///
/// [CfChallengeInterceptor] 会负责展示验证、同步 clearance、重放原请求和必要时
/// 切换 WebView 网络栈。但“验证成功后重放仍然撞盾”等终态此前可能把原始
/// 403/429 DioException 继续抛给业务层，最终被 UI 误显示为“无权限访问资源”。
///
/// 这里不再做任何重试，也不展示 UI；只把最终仍带 Cloudflare challenge 特征
/// 的响应转换成 [CfChallengeException]，并刻意移除 HTTP response，防止上层
/// 再次按 statusCode=403 做权限错误映射。
class CfChallengeTerminalInterceptor extends Interceptor {
  static const _internalReplayPassKey = '_cfTerminalInternalReplayPass';

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(normalize(err));
  }

  static DioException normalize(DioException err) {
    if (err.error is CfChallengeException) return err;
    if (!CfChallengeService.isCfChallengeResponse(err.response)) return err;

    final options = err.requestOptions;

    // CfChallengeInterceptor 在验证成功后会用同一个 RequestOptions 做一次
    // dio.fetch，并设置 skipCfChallenge=true。这个“内部第一次重放”必须保留
    // 原始 response，让外层 CF 拦截器判断“新 clearance 仍无效”并决定是否
    // 切 WebView 兼容栈/进入 cooldown。
    //
    // 内层 fetch 返回外层 CF 拦截器后，若它最终仍 handler.reject，同一个错误
    // 会再次经过本拦截器；第二次才是真正离开 CF 恢复链的终态，此时再类型化。
    if (options.spec.skipCfChallenge) {
      final pass = options.extra[_internalReplayPassKey] as int? ?? 0;
      if (pass == 0) {
        options.extra[_internalReplayPassKey] = 1;
        return err;
      }
    }

    return DioException(
      requestOptions: options,
      type: DioExceptionType.unknown,
      error: CfChallengeException(
        cause: 'Cloudflare challenge remained after recovery',
      ),
      stackTrace: err.stackTrace,
    );
  }
}
