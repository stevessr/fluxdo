import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cdk_user_info.dart';
import '../services/account_manager.dart';
import '../services/auth_session.dart';
import '../services/cdk_oauth_service.dart';
import '../services/network/exceptions/oauth_exception.dart';
import 'core_providers.dart';

final cdkOAuthServiceProvider = Provider((ref) => CdkOAuthService());
final cdkUserInfoProvider =
    AsyncNotifierProvider<CdkUserInfoNotifier, CdkUserInfo?>(() {
      return CdkUserInfoNotifier();
    });

class CdkUserInfoNotifier extends AsyncNotifier<CdkUserInfo?> {
  static const String _cacheKey = 'cdk_user_info';
  static const String _cdkEnabledKey = 'cdk_enabled';
  static const String _cacheUserKey = 'cdk_user_info_username';

  Future<CdkUserInfo?>? _inFlightFetch;
  String? _inFlightUsername;
  int? _inFlightGeneration;
  int _requestGeneration = 0;

  String _key(String base, String username) =>
      AccountManager.accountScopedKey(base, username);

  Future<String?> _currentUsername() async {
    final stored = await ref
        .read(discourseServiceProvider)
        .getCurrentUsername();
    if (stored != null && stored.isNotEmpty) return stored;
    // 安全存储为空（未登录或测试环境）时退回 currentUser provider 的
    // 已加载值；已登录账号仍以安全存储为准，避免切换窗口内旧值泄漏。
    return ref.read(currentUserProvider).value?.username;
  }

  Future<void> _migrateLegacy(SharedPreferences prefs, String username) async {
    final enabledKey = _key(_cdkEnabledKey, username);
    final cacheKey = _key(_cacheKey, username);
    final cacheUserKey = _key(_cacheUserKey, username);
    if (prefs.containsKey(enabledKey) ||
        prefs.containsKey(cacheKey) ||
        prefs.containsKey(cacheUserKey)) {
      return;
    }

    final legacyUser = prefs.getString(_cacheUserKey);
    final legacyCacheUserMatches = legacyUser == null || legacyUser == username;
    if (legacyCacheUserMatches) {
      final legacyEnabled = prefs.getBool(_cdkEnabledKey);
      final legacyCache = prefs.getString(_cacheKey);
      if (legacyEnabled != null) await prefs.setBool(enabledKey, legacyEnabled);
      if (legacyCache != null) await prefs.setString(cacheKey, legacyCache);
      if (legacyUser != null) await prefs.setString(cacheUserKey, username);
    }
    await Future.wait([
      prefs.remove(_cdkEnabledKey),
      prefs.remove(_cacheKey),
      prefs.remove(_cacheUserKey),
    ]);
  }

  @override
  Future<CdkUserInfo?> build() async {
    final generation = AuthSession().generation;
    final requestGeneration = _requestGeneration;
    final service = ref.read(cdkOAuthServiceProvider);
    ref.onDispose(() {
      _requestGeneration++;
      _inFlightFetch = null;
      service.cancelPendingRequests();
    });
    final prefs = await SharedPreferences.getInstance();
    ref.watch(currentUserProvider.select((value) => value.value?.username));
    final username = await _currentUsername();
    if (!AuthSession().isValid(generation) ||
        requestGeneration != _requestGeneration ||
        username == null ||
        username.isEmpty) {
      return null;
    }
    await _migrateLegacy(prefs, username);
    if (!AuthSession().isValid(generation) ||
        requestGeneration != _requestGeneration ||
        await _currentUsername() != username) {
      return null;
    }

    final enabled = prefs.getBool(_key(_cdkEnabledKey, username)) ?? false;
    if (!enabled) return null;

    CdkUserInfo? cachedInfo;
    final cached = prefs.getString(_key(_cacheKey, username));
    if (cached != null) {
      try {
        final cachedUser = prefs.getString(_key(_cacheUserKey, username));
        if (cachedUser == username) {
          final decoded = CdkUserInfo.fromJson(
            jsonDecode(cached) as Map<String, dynamic>,
          );
          if (decoded.username == username) cachedInfo = decoded;
        }
      } catch (_) {
        // 缓存损坏，忽略
      }
    }

    try {
      return await _fetchUserInfo(username, generation, requestGeneration);
    } on OAuthExpiredException catch (_) {
      if (!ref.mounted ||
          requestGeneration != _requestGeneration ||
          !AuthSession().isValid(generation)) {
        return null;
      }
      // 授权过期：清除缓存，让错误状态透传到 UI
      await _clearCache(prefs, username);
      rethrow;
    } catch (e) {
      if (!ref.mounted ||
          requestGeneration != _requestGeneration ||
          !AuthSession().isValid(generation)) {
        return null;
      }
      if (OAuthErrorPolicy.isCfChallenge(e)) rethrow;
      if (cachedInfo != null) return cachedInfo;
      rethrow;
    }
  }

  Future<CdkUserInfo?> _fetchUserInfo(
    String username,
    int generation,
    int requestGeneration,
  ) {
    if (_inFlightFetch != null &&
        _inFlightUsername == username &&
        _inFlightGeneration == generation) {
      return _inFlightFetch!;
    }
    late final Future<CdkUserInfo?> request;
    request = _doFetchUserInfo(username, generation, requestGeneration)
        .whenComplete(() {
          if (identical(_inFlightFetch, request)) {
            _inFlightFetch = null;
            _inFlightUsername = null;
            _inFlightGeneration = null;
          }
        });
    _inFlightFetch = request;
    _inFlightUsername = username;
    _inFlightGeneration = generation;
    return request;
  }

  Future<CdkUserInfo?> _doFetchUserInfo(
    String username,
    int generation,
    int requestGeneration,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (!AuthSession().isValid(generation) ||
        requestGeneration != _requestGeneration ||
        await _currentUsername() != username ||
        !(prefs.getBool(_key(_cdkEnabledKey, username)) ?? false)) {
      return null;
    }

    final currentUser = await ref.read(currentUserProvider.future);
    if (!AuthSession().isValid(generation) ||
        requestGeneration != _requestGeneration ||
        currentUser?.username != username ||
        await _currentUsername() != username) {
      return null;
    }

    // 统一从 provider 取服务实例：测试覆盖与请求取消都经此通道。
    final userInfo = await ref
        .read(cdkOAuthServiceProvider)
        .getUserInfo(expectedUsername: username);
    if (!AuthSession().isValid(generation) ||
        requestGeneration != _requestGeneration ||
        await _currentUsername() != username) {
      return null;
    }
    if (userInfo != null && userInfo.username == username) {
      await prefs.setString(
        _key(_cacheKey, username),
        jsonEncode(userInfo.toJson()),
      );
      await prefs.setString(_key(_cacheUserKey, username), username);
      return userInfo;
    }
    return null;
  }

  Future<void> refresh() async {
    final generation = AuthSession().generation;
    final requestGeneration = _requestGeneration;
    final username = await _currentUsername();
    if (!AuthSession().isValid(generation) || username == null) return;
    final previousData = state.value;
    // ignore: invalid_use_of_internal_member
    state = const AsyncLoading<CdkUserInfo?>().copyWithPrevious(state);
    try {
      final result = await _fetchUserInfo(
        username,
        generation,
        requestGeneration,
      );
      if (!AuthSession().isValid(generation) ||
          requestGeneration != _requestGeneration ||
          await _currentUsername() != username) {
        return;
      }
      state = AsyncValue.data(result);
    } catch (e, st) {
      if (!AuthSession().isValid(generation) ||
          requestGeneration != _requestGeneration ||
          await _currentUsername() != username) {
        return;
      }
      if (e is OAuthExpiredException) {
        final prefs = await SharedPreferences.getInstance();
        await _clearCache(prefs, username);
        state = AsyncValue.error(e, st);
      } else if (OAuthErrorPolicy.isCfChallenge(e)) {
        // 需要验证时保留缓存，但不把旧数据伪装成本次请求成功。
        // ignore: invalid_use_of_internal_member
        state = AsyncValue<CdkUserInfo?>.error(e, st).copyWithPrevious(state);
      } else if (previousData != null) {
        state = AsyncValue.data(previousData);
      } else {
        state = AsyncValue.error(e, st);
      }
    }
  }

  /// 用户已手动通过 CF，取消旧请求并立即重新读取业务会话。
  Future<void> refreshAfterCfVerification() {
    _requestGeneration++;
    _inFlightFetch = null;
    ref.read(cdkOAuthServiceProvider).cancelPendingRequests();
    return refresh();
  }

  Future<void> clear() async {
    final generation = AuthSession().generation;
    final username = await _currentUsername();
    if (!AuthSession().isValid(generation) ||
        username == null ||
        username.isEmpty) {
      return;
    }
    _requestGeneration++;
    _inFlightFetch = null;
    ref.read(cdkOAuthServiceProvider).cancelPendingRequests();
    final prefs = await SharedPreferences.getInstance();
    await _clearCache(prefs, username);
    if (!AuthSession().isValid(generation) ||
        await _currentUsername() != username) {
      return;
    }
    state = const AsyncValue.data(null);
  }

  Future<void> disable() async {
    final generation = AuthSession().generation;
    final username = await _currentUsername();
    if (!AuthSession().isValid(generation) ||
        username == null ||
        username.isEmpty) {
      return;
    }
    _requestGeneration++;
    _inFlightFetch = null;
    ref.read(cdkOAuthServiceProvider).cancelPendingRequests();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_cdkEnabledKey, username), false);
    await _clearCache(prefs, username);
    if (!AuthSession().isValid(generation) ||
        await _currentUsername() != username) {
      return;
    }
    state = const AsyncValue.data(null);
  }

  Future<void> _clearCache(SharedPreferences prefs, String username) async {
    await Future.wait([
      prefs.remove(_key(_cacheKey, username)),
      prefs.remove(_key(_cacheUserKey, username)),
    ]);
  }
}
