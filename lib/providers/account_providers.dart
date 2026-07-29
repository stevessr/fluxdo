import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/account_manager.dart';
import '../services/discourse/discourse_service.dart';
import '../services/network/cookie/cookie_jar_service.dart';
import '../services/auth_session.dart';
import '../services/preloaded_data_service.dart';
import 'discourse_providers.dart';

/// 账号列表 Provider
///
/// 用 [AccountNotifier] 管理多账号 CRUD。
final accountListProvider =
    AsyncNotifierProvider<AccountNotifier, List<StoredAccount>>(
      AccountNotifier.new,
    );

class AccountNotifier extends AsyncNotifier<List<StoredAccount>> {
  final AccountManager _manager = AccountManager();

  @override
  Future<List<StoredAccount>> build() async {
    return _manager.getAccounts();
  }

  /// 添加账号（登录成功后调用）
  Future<void> addAccount(StoredAccount account) async {
    await _manager.addAccount(account);
    ref.invalidateSelf();
  }

  /// 删除指定账号
  Future<void> removeAccount(String username) async {
    await _manager.removeAccount(username);
    ref.invalidateSelf();
  }

  /// 清除所有账号
  Future<void> clearAccounts() async {
    await _manager.clear();
    ref.invalidateSelf();
  }
}

/// 切换账号到指定用户名。
///
/// 1. 从 [AccountManager] 读取目标 token
/// 2. 写入 CookieJar `_t` cookie
/// 3. 更新 [DiscourseService] 内部状态
/// 4. 推进 [AuthSession] 使旧请求自动失效
/// 5. 探测 token 有效性（避免静默登出）
/// 6. 重载用户数据
///
/// 返回 true 表示切换成功。若 token 已过期/失效返回 false。
Future<bool> switchToAccount({
  required String username,
  required WidgetRef ref,
}) async {
  final service = DiscourseService();
  final manager = AccountManager();

  // 读取目标 token
  final token = await manager.getToken(username);
  if (token == null || token.isEmpty) {
    debugPrint('[AccountSwitch] 目标账号 $username 无有效 token');
    return false;
  }

  // 先缓存当前用户信息，切换失败时恢复
  final prevUsername = service.currentUsername;
  final prevToken = service.tToken;

  // 写入 cookie jar
  final cookieJar = CookieJarService();
  await cookieJar.setCookie('_t', token);

  // 更新内存状态
  service.setToken(token);
  await service.saveUsername(username);

  // 推进会话代，旧请求自动失效
  AuthSession().advance();

  // 重置预加载数据
  PreloadedDataService().reset();

  // 探测 token 有效性（直接 dio 请求，不触发 auth 自愈逻辑）
  var tokenValid = false;
  try {
    final response = await service.dio.get(
      '/session/current.json',
      options: Options(
        extra: const {'skipAuthCheck': true, 'skipCsrf': true},
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    final data = response.data;
    if (data is Map<String, dynamic>) {
      final currentUser = data['current_user'];
      tokenValid =
          currentUser is Map<String, dynamic> &&
          currentUser['username']?.toString() == username;
    }
  } catch (e) {
    debugPrint('[AccountSwitch] token 探测失败: $e');
  }

  if (!tokenValid) {
    debugPrint('[AccountSwitch] token 已失效，回滚到之前的账号');
    // 恢复旧 cookie 和内存状态
    if (prevToken != null) {
      await cookieJar.setCookie('_t', prevToken);
      service.setToken(prevToken);
      if (prevUsername != null) {
        await service.saveUsername(prevUsername);
      }
    } else {
      // 之前没有登录态 → 直接清除
      await cookieJar.deleteCookie('_t');
      service.setToken('');
    }
    AuthSession().advance();
    PreloadedDataService().reset();
    ref.invalidate(currentUserProvider);
    return false;
  }

  // 更新最后登录时间
  await manager.touchAccount(username);
  ref.invalidate(accountListProvider);

  return true;
}
