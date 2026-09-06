import 'package:dio/dio.dart';

import '../../constants.dart';
import 'adapters/platform_adapter.dart';
import 'cookie/app_cookie_manager.dart';
import 'cookie/cookie_jar_service.dart';
import '../cf_challenge_service.dart';
import 'cookie/csrf_token_service.dart';
import 'interceptors/cf_challenge_interceptor.dart';
import 'interceptors/cf_challenge_terminal_interceptor.dart';
import 'interceptors/error_interceptor.dart';
import 'interceptors/http_revalidation_interceptor.dart';
import 'interceptors/network_log_interceptor.dart';
import 'interceptors/redirect_interceptor.dart';
import 'interceptors/request_coalescing_interceptor.dart';
import 'interceptors/request_header_interceptor.dart';
import 'interceptors/request_scheduler_interceptor.dart';
import 'interceptors/session_guard_interceptor.dart';
import 'recovery/engine_fallback_policy.dart';
import 'recovery/policies.dart';
import 'recovery/recovery_coordinator.dart';
import 'recovery/session_heal_policy.dart';

/// 统一封装的 Dio 工厂
class DiscourseDio {
  static Dio create({
    Duration connectTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 30),
    Map<String, dynamic>? defaultHeaders,
    String? baseUrl,
    /// null 表示不限制（用于下载、MessageBus 等），非 null 启用调度器。
    /// 实际并发数和速率从 [RequestSchedulerConfig] 动态读取。
    int? maxConcurrent = 3,
    bool enableRetry = true,
    bool enableCfChallenge = true,
    bool enableCookies = true,
    bool enableNetworkLog = true,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? AppConstants.baseUrl,
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        headers: defaultHeaders,
        // 禁用自动重定向，手动处理以确保重定向时使用正确的 cookie
        followRedirects: false,
        // 包含重定向状态码，让我们手动处理
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
    );

    // 大响应(>50KB)的 JSON 解码移入 isolate:话题列表/详情等大 JSON
    // 在主线程解码实测把 DartIsolate::HandleMessage 顶到 50~100ms,
    // 滚动/返回列表时直接掉帧。小响应仍同步解码(isolate 往返不划算)。
    dio.transformer = BackgroundTransformer();

    // 1. 配置平台适配器
    //
    // 需要绕开 rhttp 走系统栈的场景(如 MessageBus 长轮询依赖系统级省电)
    // 由请求侧的 FluxRequestKeys.skipRhttpAdapter 逐请求声明,不在这里分档。
    configurePlatformAdapter(dio);

    // 2. 会话代守卫（最先执行，确保过期请求不进入后续拦截器）
    dio.interceptors.add(SessionGuardInterceptor());

    // 3. 同一会话代内，相同 GET 共享正在进行的请求。
    // 放在调度器之前，重复请求不会占用并发/速率槽位；最终结果由靠后的
    // Finalizer 完成，确保重试、重定向、CF 验证都结束后才唤醒跟随者。
    dio.interceptors.add(RequestCoalescingInterceptor());

    // 4. 并发限制 + 滑动窗口速率限制（null 表示不限制）
    // 实际参数从 RequestSchedulerConfig 动态读取
    if (maxConcurrent != null) {
      dio.interceptors.add(RequestSchedulerInterceptor());
    }

    // 5. 恢复协调器:全项目唯一的重放引擎
    //
    // 策略顺序即失败归属(首个 canHandle 者独占决策权):
    //   会话自愈 → 引擎降级 → 限流等待 → 瞬态重试
    //
    // 必须注册在 AppCookieManager **之前**:dio 5.11 三相全 FIFO,先注册者
    // 先看到响应。服务端拒绝时常带 Set-Cookie 清 _t,自愈判定要读的是那条
    // 删除指令**落库前**的 jar 快照——顺序颠倒会让它误判"真登出"跳过自愈。
    // 契约测试: test/services/network/recovery/session_heal_test.dart
    //
    // 取代 dio_smart_retry + SelfHealingInterceptor + CronetFallbackInterceptor。
    // 与 dio_smart_retry 的行为差异是刻意的:
    // - 5xx 只对幂等方法重放,POST 重放会造成重复发帖;
    // - 429 区分挑战型(交 CF 盾)与真限流,并尊重 Retry-After;
    // - 尝试预算集中防环,不再靠各重放点自觉打 skip 标记。
    final cookieJarService = CookieJarService();
    final cookiesEnabled = enableCookies && cookieJarService.isInitialized;
    if (enableRetry) {
      dio.interceptors.add(
        RecoveryCoordinator(
          dio: dio,
          policies: [
            if (cookiesEnabled) SessionSelfHealPolicy(),
            const EngineFallbackPolicy(),
            RateLimitPolicy(
              isChallengeResponse: CfChallengeService.isCfChallengeResponse,
            ),
            const TransientRetryPolicy(),
          ],
        ),
      );
    }

    // 6. Cookie 管理
    if (cookiesEnabled) {
      dio.interceptors.add(AppCookieManager(cookieJarService.cookieJar));
    }

    // 7. 请求头拦截器
    dio.interceptors.add(RequestHeaderInterceptor(CsrfTokenService()));

    // 8. 重定向拦截器
    dio.interceptors.add(RedirectInterceptor(dio));

    // 9. 错误拦截器
    dio.interceptors.add(ErrorInterceptor());

    // 10. CF 验证拦截器 + 终态类型化兜底。
    // 后者不做重试，只确保验证后仍残留的 challenge 不会以裸 403/429
    // 泄漏给业务层并被误显示成“无权限访问资源”。
    if (enableCfChallenge) {
      dio.interceptors.add(
        CfChallengeInterceptor(dio: dio, cookieJarService: cookieJarService),
      );
      dio.interceptors.add(CfChallengeTerminalInterceptor());
    }

    // 11. 浏览器式条件重验证缓存。
    // 仅保存带 ETag/Last-Modified 的小型 GET；不自造 TTL，不让动态 Discourse
    // 数据在客户端长期陈旧。304 在这里展开为缓存 body + 最新响应头。
    dio.interceptors.add(HttpRevalidationInterceptor());

    // 12. 请求合并的最终完成点。必须在恢复/重定向/CF/304 展开之后，
    // 否则跟随者可能收到中间 429/403/304 而不是业务层最终结果。
    dio.interceptors.add(RequestCoalescingFinalizerInterceptor());

    // 13. 网络日志拦截器（最后一个，记录最终结果）
    // 注意：Gateway URL 改写已移至 HttpClientAdapter 层（_GatewayAdapterWrapper），
    // 所有拦截器始终看到原始 URL，无需额外处理。
    if (enableNetworkLog) {
      dio.interceptors.add(NetworkLogInterceptor());
    }

    return dio;
  }
}
