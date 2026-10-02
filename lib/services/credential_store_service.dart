import 'dart:convert';

import 'storage/resilient_secure_storage.dart';
import 'storage/secret_store.dart';
import 'storage/system_secret_store.dart';

class SavedLoginCredential {
  const SavedLoginCredential({
    required this.accountId,
    required this.identifier,
    required this.password,
    required this.savedAt,
  });

  final String accountId;
  final String identifier;
  final String password;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
    'account_id': accountId,
    'identifier': identifier,
    'password': password,
    'saved_at': savedAt.toIso8601String(),
  };

  factory SavedLoginCredential.fromJson(Map<String, dynamic> json) {
    return SavedLoginCredential(
      accountId: (json['account_id'] as String?)?.trim() ?? '',
      identifier: (json['identifier'] as String?)?.trim() ?? '',
      password: json['password'] as String? ?? '',
      savedAt:
          DateTime.tryParse(json['saved_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// 登录凭证安全存储服务（单例）。
///
/// 密码按 Discourse 账号隔离存储，不再使用一组全局 username/password key。
/// 注册表只保存账号标识；每个账号的完整凭证均存放在独立的系统安全存储 key 中。
class CredentialStoreService {
  CredentialStoreService._internal(this._store, this._legacyStorage);

  static final CredentialStoreService _instance =
      CredentialStoreService._internal(
        SystemSecretStore.instance,
        ResilientSecureStorage(),
      );

  factory CredentialStoreService() => _instance;

  /// 仅供单元测试注入纯内存 SecretStore。
  CredentialStoreService.forTesting(SecretStore store)
    : _store = store,
      _legacyStorage = null;

  static const _namespace = 'login_credentials';
  static const _legacyKeyUsername = 'login_credential_username';
  static const _legacyKeyPassword = 'login_credential_password';

  final SecretStore _store;
  final ResilientSecureStorage? _legacyStorage;
  bool _legacyMigrationChecked = false;

  static const _indexKey = SecretKey(
    namespace: _namespace,
    name: 'accounts',
  );

  SecretKey _credentialKey(String accountId) => SecretKey(
    namespace: _namespace,
    name: 'credential',
    accountId: _canonicalAccountId(accountId),
  );

  static String _canonicalAccountId(String value) =>
      value.trim().toLowerCase();

  Future<List<String>> _readIndex() async {
    final raw = await _store.read(_indexKey);
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>[];
      final seen = <String>{};
      final result = <String>[];
      for (final item in decoded) {
        if (item is! String) continue;
        final canonical = _canonicalAccountId(item);
        if (canonical.isEmpty || !seen.add(canonical)) continue;
        result.add(canonical);
      }
      return result;
    } catch (_) {
      return <String>[];
    }
  }

  Future<void> _writeIndex(List<String> accountIds) async {
    final seen = <String>{};
    final normalized = <String>[];
    for (final accountId in accountIds) {
      final canonical = _canonicalAccountId(accountId);
      if (canonical.isEmpty || !seen.add(canonical)) continue;
      normalized.add(canonical);
    }
    await _store.write(_indexKey, jsonEncode(normalized));
  }

  Future<SavedLoginCredential?> _readCredential(String accountId) async {
    final raw = await _store.read(_credentialKey(accountId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final credential = SavedLoginCredential.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (credential.accountId.isEmpty ||
          credential.identifier.isEmpty ||
          credential.password.isEmpty) {
        return null;
      }
      return credential;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveInternal(
    String identifier,
    String password, {
    required String accountId,
  }) async {
    final normalizedIdentifier = identifier.trim();
    final normalizedAccountId = accountId.trim();
    if (normalizedIdentifier.isEmpty) {
      throw ArgumentError.value(identifier, 'identifier', 'must not be empty');
    }
    if (normalizedAccountId.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId', 'must not be empty');
    }
    if (password.isEmpty) {
      throw ArgumentError.value(password, 'password', 'must not be empty');
    }

    final credential = SavedLoginCredential(
      accountId: normalizedAccountId,
      identifier: normalizedIdentifier,
      password: password,
      savedAt: DateTime.now().toUtc(),
    );
    final canonical = _canonicalAccountId(normalizedAccountId);

    // 先写凭证，再提交索引；这样即使索引写入失败，也不会先暴露一个空条目。
    await _store.write(
      _credentialKey(normalizedAccountId),
      jsonEncode(credential.toJson()),
    );
    final index = await _readIndex();
    index.remove(canonical);
    index.insert(0, canonical);
    await _writeIndex(index);
  }

  Future<void> _ensureLegacyMigrated() async {
    if (_legacyMigrationChecked) return;
    final legacyStorage = _legacyStorage;
    if (legacyStorage == null) {
      _legacyMigrationChecked = true;
      return;
    }

    final username = await legacyStorage.read(key: _legacyKeyUsername);
    final password = await legacyStorage.read(key: _legacyKeyPassword);
    if (username == null ||
        username.trim().isEmpty ||
        password == null ||
        password.isEmpty) {
      _legacyMigrationChecked = true;
      return;
    }

    // 旧版本只有一组全局凭证。先写入新结构，成功后再删除旧 key，
    // 避免升级过程中因系统安全存储暂时不可用而丢失密码。
    await _saveInternal(username, password, accountId: username);
    await legacyStorage.delete(key: _legacyKeyUsername);
    await legacyStorage.delete(key: _legacyKeyPassword);
    _legacyMigrationChecked = true;
  }

  /// 保存某个账号的凭证。
  ///
  /// [identifier] 是用户实际用于登录的用户名/邮箱；[accountId] 应优先传
  /// Discourse 返回的真实 username，从而让“邮箱登录”和“用户名登录”仍落到
  /// 同一个账号槽位。未提供时使用 identifier 作为账号标识。
  Future<void> save(
    String identifier,
    String password, {
    String? accountId,
  }) async {
    await _ensureLegacyMigrated();
    await _saveInternal(
      identifier,
      password,
      accountId: accountId ?? identifier,
    );
  }

  /// 返回全部已保存凭证，按最近保存时间/使用顺序排列。
  Future<List<SavedLoginCredential>> list() async {
    await _ensureLegacyMigrated();
    final index = await _readIndex();
    if (index.isEmpty) return const <SavedLoginCredential>[];

    final credentials = await Future.wait(
      index.map(_readCredential),
    );
    final result = <SavedLoginCredential>[];
    final validIds = <String>[];
    for (var i = 0; i < index.length; i++) {
      final credential = credentials[i];
      if (credential == null) continue;
      result.add(credential);
      validIds.add(index[i]);
    }

    if (validIds.length != index.length) {
      await _writeIndex(validIds);
    }
    return result;
  }

  /// 读取最近保存的凭证，或按账号/登录标识精确读取。
  Future<({String? username, String? password})> load({
    String? accountId,
  }) async {
    final credentials = await list();
    SavedLoginCredential? selected;
    if (accountId == null || accountId.trim().isEmpty) {
      if (credentials.isNotEmpty) selected = credentials.first;
    } else {
      final canonical = _canonicalAccountId(accountId);
      for (final credential in credentials) {
        if (_canonicalAccountId(credential.accountId) == canonical ||
            _canonicalAccountId(credential.identifier) == canonical) {
          selected = credential;
          break;
        }
      }
    }
    return (
      username: selected?.identifier,
      password: selected?.password,
    );
  }

  /// 清除指定账号的凭证；不传 [accountId] 时清除所有已保存凭证。
  Future<void> clear({String? accountId}) async {
    await _ensureLegacyMigrated();
    final index = await _readIndex();

    if (accountId == null || accountId.trim().isEmpty) {
      for (final id in index) {
        await _store.delete(_credentialKey(id));
      }
      await _store.delete(_indexKey);
      final legacyStorage = _legacyStorage;
      if (legacyStorage != null) {
        await legacyStorage.delete(key: _legacyKeyUsername);
        await legacyStorage.delete(key: _legacyKeyPassword);
      }
      return;
    }

    final canonical = _canonicalAccountId(accountId);
    final retained = <String>[];
    for (final id in index) {
      final credential = await _readCredential(id);
      final matches =
          id == canonical ||
          (credential != null &&
              (_canonicalAccountId(credential.accountId) == canonical ||
                  _canonicalAccountId(credential.identifier) == canonical));
      if (matches) {
        await _store.delete(_credentialKey(id));
      } else {
        retained.add(id);
      }
    }
    await _writeIndex(retained);
  }

  /// 是否存在任意或指定账号的已保存凭证。
  Future<bool> hasCredentials({String? accountId}) async {
    final loaded = await load(accountId: accountId);
    return loaded.username != null &&
        loaded.password != null &&
        loaded.username!.isNotEmpty &&
        loaded.password!.isNotEmpty;
  }
}
