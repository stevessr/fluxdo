import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'storage/resilient_secure_storage.dart';

/// 存储的一个账号信息
class StoredAccount {
  final String username;
  final String token;
  final DateTime lastLoginAt;

  const StoredAccount({
    required this.username,
    required this.token,
    required this.lastLoginAt,
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'token': token,
    'lastLoginAt': lastLoginAt.toIso8601String(),
  };

  factory StoredAccount.fromJson(Map<String, dynamic> json) => StoredAccount(
    username: json['username'] as String,
    token: json['token'] as String,
    lastLoginAt: DateTime.parse(json['lastLoginAt'] as String),
  );

  StoredAccount copyWith({String? username, String? token, DateTime? lastLoginAt}) =>
      StoredAccount(
        username: username ?? this.username,
        token: token ?? this.token,
        lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      );
}

/// 多账号管理服务（单例）
///
/// 保存多个 Discourse 登录账号的 token，支持切换、添加、删除。
/// 账号数据存储在 [ResilientSecureStorage] 中，与浏览器 cookie 独立。
class AccountManager {
  AccountManager._();
  static final AccountManager _instance = AccountManager._();
  factory AccountManager() => _instance;

  static const String _storageKey = 'multi_account_list';

  final ResilientSecureStorage _storage = ResilientSecureStorage();

  /// 读取所有已保存的账号
  Future<List<StoredAccount>> getAccounts() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => StoredAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[AccountManager] 解析失败: $e');
      return [];
    }
  }

  /// 保存账号列表
  Future<void> _saveAccounts(List<StoredAccount> accounts) async {
    final raw = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await _storage.write(key: _storageKey, value: raw);
  }

  /// 添加或更新一个账号（同名覆盖）
  Future<void> addAccount(StoredAccount account) async {
    final accounts = await getAccounts();
    accounts.removeWhere((a) => a.username == account.username);
    accounts.insert(0, account.copyWith(lastLoginAt: DateTime.now()));
    await _saveAccounts(accounts);
  }

  /// 删除指定账号
  Future<void> removeAccount(String username) async {
    final accounts = await getAccounts();
    accounts.removeWhere((a) => a.username == username);
    await _saveAccounts(accounts);
  }

  /// 更新指定账号的最后登录时间
  Future<void> touchAccount(String username) async {
    final accounts = await getAccounts();
    final idx = accounts.indexWhere((a) => a.username == username);
    if (idx < 0) return;
    accounts[idx] = accounts[idx].copyWith(lastLoginAt: DateTime.now());
    // 移到最前
    final account = accounts.removeAt(idx);
    accounts.insert(0, account);
    await _saveAccounts(accounts);
  }

  /// 获取指定账号的 token
  Future<String?> getToken(String username) async {
    final accounts = await getAccounts();
    final account = accounts.cast<StoredAccount?>().firstWhere(
      (a) => a!.username == username,
      orElse: () => null,
    );
    return account?.token;
  }

  /// 是否已保存任何账号
  Future<bool> hasAccounts() async {
    final accounts = await getAccounts();
    return accounts.isNotEmpty;
  }

  /// 清除所有账号
  Future<void> clear() async {
    await _storage.delete(key: _storageKey);
  }
}
