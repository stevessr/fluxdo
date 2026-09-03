import 'package:dio/dio.dart';

import '../../cf_challenge_service.dart';
import '../exceptions/api_exception.dart';

/// CF 恢复链的最后一道类型化兜底。
///
/// [CfChallengeInterceptor] 会负责展示验证、同步 clearance、重放原请求和必要时
/// 切换 WebView 网络栈。但“验证成功后重放仍然撞盾”等终态此前可能把原始
/// 403/429 DioException 继续抛给业务层，最终被 UI 误显示为“无权限访问资源”。
///
/// 这里不再做任何重试，也不展示 UI；只把仍带 Cloudflare challenge 特征的
/// 原始响应转换成 [CfChallengeException]，并刻意移除 HTTP response，防止
/// 上层再次按 statusCode=403 做权限错误映射。
class CfChallengeTerminalInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(normalize(err));
  }

  static DioException normalize(DioException err) {
    if (err.error is CfChallengeException) return err;
    if (!CfChallengeService.isCfChallengeResponse(err.response)) return err;

    return DioException(
      requestOptions: err.requestOptions,
      type: DioExceptionType.unknown,
      error: CfChallengeException(
        cause: 'Cloudflare challenge remained after recovery',
      ),
      stackTrace: err.stackTrace,
    );
  }
}
