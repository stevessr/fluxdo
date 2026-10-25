import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'multi_account_registry_normalizer.dart';
import 'secret_store.dart';
import 'system_secret_store.dart';

/// 旧调用方兼容层。
///
/// 新代码应使用 [SecretStore] + 类型化 [SecretKey]。该兼容层不再降级到
/// 明文 SharedPreferences；系统安全存储不可用时只保留当前进程内存值。
class ResilientSecureStorage {
  ResilientSecureStorage({
    FlutterSecureStorage? secureStorage,
    String fallbackPrefix = '__secure_fallback__',
  }) : _store = secureStorage == null
           ? SystemSecretStore.instance
           : SystemSecretStore(secureStorage: secureStorage),
       _legacyFallbackPrefix = fallbackPrefix;

  final SecretStore _store;
  final String _legacyFallbackPrefix;

  /// 明文 fallback 只在升级后的第一次读取时迁移一次；每个 key 只探测一次。
  ///
  /// 注意：这里缓存的是 SharedPreferences **实例**而不是 Future——
  /// Future 会绑定创建时的 Zone，在 widget 测试里跨测试复用一个来自
  /// 已结束 FakeAsync zone 的 Future 会让 await 永不返回。
  static SharedPreferences? _legacyPrefs;
  static final Set<String> _legacyCheckedKeys = <String>{};

  static Future<SharedPreferences> _legacyPreferences() async =>
      _legacyPrefs ??= await SharedPreferences.getInstance();

  Future<String?> read({required String key}) async {
    final value = await _store.read(SecretKey.raw(key));
    if (value != null) {
      final normalized = _normalizeLegacyValue(key, value);
      if (normalized != value) {
        try {
          // Reading the account list doubles as a one-time migration for
          // duplicate rows left by older builds. Failure to persist the
          // cleanup must not make an otherwise readable secret unavailable.
          await _store.write(SecretKey.raw(key), normalized);
        } catch (_) {}
      }
      return normalized;
    }

    // 只迁移旧版本曾写入的明文 fallback；新代码永不再写该位置。
    if (!_legacyCheckedKeys.add(key)) return null;
    final preferences = await _legacyPreferences();
    final legacyKey = '$_legacyFallbackPrefix$key';
    final legacyValue = preferences.getString(legacyKey);
    if (legacyValue == null) return null;
    final normalizedLegacyValue = _normalizeLegacyValue(key, legacyValue);
    try {
      await _store.write(
        SecretKey.raw(key, fallbackPolicy: SecretFallbackPolicy.deny),
        normalizedLegacyValue,
      );
      await preferences.remove(legacyKey);
    } catch (_) {
      // 系统安全存储仍不可用时保留旧值，避免升级过程丢失凭证。
    }
    return normalizedLegacyValue;
  }

  Future<void> write({required String key, required String value}) async {
    await _store.write(SecretKey.raw(key), _normalizeLegacyValue(key, value));
    final preferences = await _legacyPreferences();
    await preferences.remove('$_legacyFallbackPrefix$key');
  }

  Future<void> delete({required String key}) async {
    await _store.delete(SecretKey.raw(key));
    final preferences = await _legacyPreferences();
    await preferences.remove('$_legacyFallbackPrefix$key');
  }

  String _normalizeLegacyValue(String key, String value) {
    if (key != MultiAccountRegistryNormalizer.registryKey) return value;
    return MultiAccountRegistryNormalizer.normalize(value);
  }
}
