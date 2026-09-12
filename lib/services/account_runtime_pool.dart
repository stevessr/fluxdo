import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:flutter/foundation.dart';

import '../models/user.dart';

/// 进程内的账号原生会话 runtime。
///
/// 持久化快照仍由 [AccountManager] 负责；这里仅保存最近实际运行过的账号状态，
/// 用于 A -> B -> A 这种连续切换时复用已经验证过的 cookie / CSRF / currentUser，
/// 避免每次都重新请求 `/session/current.json`。WebView 仍然是共享浏览器上下文，
/// 因此不放进 runtime，继续沿用 AccountManager 的显式清理与回灌边界。
class AccountNativeRuntime {
  const AccountNativeRuntime({
    required this.username,
    required this.cookies,
    required this.sessionToken,
    required this.csrfToken,
    required this.currentUser,
    required this.capturedAt,
    required this.validatedAt,
  });

  final String username;
  final List<CanonicalCookie> cookies;
  final String sessionToken;
  final String? csrfToken;
  final User? currentUser;
  final DateTime capturedAt;
  final DateTime validatedAt;

  bool canReuseValidation({
    DateTime? now,
    Duration window = AccountRuntimePool.validationReuseWindow,
  }) {
    final reference = now ?? DateTime.now();
    final age = reference.difference(validatedAt);
    return !age.isNegative && age <= window;
  }
}

class AccountRuntimePool {
  AccountRuntimePool._();

  static final AccountRuntimePool instance = AccountRuntimePool._();

  /// 仅跳过短时间内重复的服务端 session 校验。
  ///
  /// runtime 本身可以保留更久；超过此窗口只是不再跳过网络校验，仍可用于
  /// 恢复进程内更新过的 cookie / CSRF，避免退回更旧的磁盘快照。
  static const validationReuseWindow = Duration(minutes: 2);
  static const runtimeLifetime = Duration(minutes: 30);
  static const maxEntries = 8;

  final Map<String, AccountNativeRuntime> _entries = {};

  static String _key(String username) => username.trim().toLowerCase();

  /// Cloudflare cookie 属于设备/浏览器通行状态，不属于某一个论坛账号。
  /// 切换时由现有 detach 流程单独保留最新值，不能把旧 runtime 中的 CF
  /// cookie 再覆盖回来。
  static bool _isDeviceCookie(String name) {
    final lower = name.toLowerCase();
    return lower == 'cf_clearance' ||
        lower == '__cf_bm' ||
        lower.startsWith('cf_') ||
        lower.startsWith('__cf');
  }

  void save({
    required String username,
    required Iterable<CanonicalCookie> cookies,
    required String sessionToken,
    String? csrfToken,
    User? currentUser,
    DateTime? capturedAt,
    DateTime? validatedAt,
  }) {
    final normalizedUsername = username.trim();
    final normalizedToken = sessionToken.trim();
    if (normalizedUsername.isEmpty || normalizedToken.isEmpty) return;

    final now = capturedAt ?? DateTime.now();
    final runtimeCookies = cookies
        .where(
          (cookie) =>
              !_isDeviceCookie(cookie.name) &&
              cookie.value.isNotEmpty &&
              cookie.value != 'del' &&
              !cookie.isExpired,
        )
        .toList(growable: false);
    final hasMatchingSession = runtimeCookies.any(
      (cookie) => cookie.name == '_t' && cookie.value == normalizedToken,
    );
    if (!hasMatchingSession) return;

    _entries[_key(normalizedUsername)] = AccountNativeRuntime(
      username: normalizedUsername,
      cookies: runtimeCookies,
      sessionToken: normalizedToken,
      csrfToken: csrfToken,
      currentUser: currentUser,
      capturedAt: now,
      validatedAt: validatedAt ?? now,
    );
    _evictExpiredAndOverflow(now);
  }

  /// 只接受与磁盘快照 `_t` 一致的 runtime。
  ///
  /// 这条约束很重要：账号被重新登录、token 已轮换或旧账号被同名重新添加时，
  /// 内存里残留的 runtime 都不能越过持久化快照边界。
  AccountNativeRuntime? findMatching(
    String username,
    String restoredSessionToken, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    _evictExpiredAndOverflow(reference);
    final runtime = _entries[_key(username)];
    if (runtime == null || runtime.sessionToken != restoredSessionToken) {
      return null;
    }
    return runtime;
  }

  void remove(String username) {
    _entries.remove(_key(username));
  }

  void clear() {
    _entries.clear();
  }

  void _evictExpiredAndOverflow(DateTime now) {
    _entries.removeWhere((_, runtime) {
      final age = now.difference(runtime.capturedAt);
      return age.isNegative || age > runtimeLifetime;
    });

    if (_entries.length <= maxEntries) return;
    final sorted = _entries.entries.toList(growable: false)
      ..sort((a, b) => a.value.capturedAt.compareTo(b.value.capturedAt));
    final overflow = _entries.length - maxEntries;
    for (var index = 0; index < overflow; index++) {
      _entries.remove(sorted[index].key);
    }
  }

  @visibleForTesting
  void resetForTest() => clear();

  @visibleForTesting
  int get lengthForTest => _entries.length;
}
