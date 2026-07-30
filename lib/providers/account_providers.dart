import 'package:flutter/foundation.dart';
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
/// 5. 重载用户数据
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

  // 刷新用户数据
  ref.invalidate(currentUserProvider);
  try {
    await ref
        .read(currentUserProvider.future)
        .timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint('[AccountSwitch] 刷新用户数据失败: $e');
  }

  // 更新最后登录时间
  await manager.touchAccount(username);

  // 重载用户数据
  ref.invalidate(currentUserProvider);
  ref.invalidate(accountListProvider);

  return true;
}
