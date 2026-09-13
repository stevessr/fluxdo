import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import 'network/cookie/cookie_jar_service.dart';

/// 持久化的首页 preload cache。
///
/// - 仅缓存带 `preload-home` 标记的首页 HTML，由网络拦截器接入；
/// - 磁盘快照最长保留 7 天，但正常启动只直接复用很新的快照；
/// - 以站点 + 当前 `_t` 会话为命名空间，不同账号/不同登录会话绝不复用；
/// - 文件名只落不可逆哈希，不额外暴露用户名或 token；
/// - 开关是全局实验开关，关闭后停止读写，但不会隐式删除已有缓存；
/// - 落盘前剥离 CSRF 与 Turnstile sitekey 等不适合长期复用的元数据；
/// - 保留 Discourse `shared_session_key`：它本身由服务端以 7 天 TTL 保存，
///   且外置 MessageBus 认证依赖该字段，生命周期与本缓存上限一致。
///
/// 使用 `_t` 而不是 `linux_do_username` 尤其重要：多账号切换会在目标账号
/// cookie 已恢复、但用户名 registry 尚未 commit 的事务窗口内触发 preload。
/// 令牌命名空间能保证这个窗口仍然命中目标账号，而不是旧账号缓存。
class PreloadCacheService {
  PreloadCacheService._internal()
    : _cacheBaseDirectory = getApplicationCacheDirectory,
      _namespaceSeed = _readCurrentSessionNamespaceSeed,
      _isEnabled = _readEnabledPreference,
      _now = DateTime.now;

  static final PreloadCacheService _instance = PreloadCacheService._internal();

  factory PreloadCacheService() => _instance;

  @visibleForTesting
  PreloadCacheService.testing({
    required Future<Directory> Function() cacheBaseDirectory,
    required Future<String?> Function() namespaceSeed,
    required Future<bool> Function() isEnabled,
    DateTime Function()? now,
  }) : _cacheBaseDirectory = cacheBaseDirectory,
       _namespaceSeed = namespaceSeed,
       _isEnabled = isEnabled,
       _now = now ?? DateTime.now;

  /// 磁盘保留上限。旧快照可用于诊断/未来降级策略，但不代表可在正常
  /// 联网启动时直接作为最新 Discourse bootstrap 数据。
  static const Duration cacheTtl = Duration(days: 7);

  /// 正常启动允许零网络请求直接命中的窗口。
  ///
  /// `currentUser`、`topicTrackingStates`、`topicList` 都属于动态数据；把整个
  /// bootstrap HTML 无条件复用 7 天虽然快，但会把旧未读数/话题列表当成最新。
  /// 2 分钟与当前用户静默刷新冷却窗口一致，兼顾快速重启与数据准确性。
  static const Duration startupFastPathTtl = Duration(minutes: 2);

  static const String enabledPreferenceKey = 'experiment_preload_cache_enabled';
  static const String _cacheDirectoryName = 'preload_cache_v1';

  final Future<Directory> Function() _cacheBaseDirectory;
  final Future<String?> Function() _namespaceSeed;
  final Future<bool> Function() _isEnabled;
  final DateTime Function() _now;

  static Future<String?> _readCurrentSessionNamespaceSeed() async {
    final token = (await CookieJarService().getTToken())?.trim();
    if (token == null || token.isEmpty || token == 'del') return null;
    return token;
  }

  static Future<bool> _readEnabledPreference() async {
    final prefs = await SharedPreferences.getInstance();
    // 这是一个可随时关闭的实验优化；默认开启，升级后即可获得收益。
    return prefs.getBool(enabledPreferenceKey) ?? true;
  }

  Future<Directory> _cacheRoot() async {
    final base = await _cacheBaseDirectory();
    return Directory(p.join(base.path, _cacheDirectoryName));
  }

  Future<File?> _fileForCurrentAccount({required bool createRoot}) async {
    final namespaceSeed = (await _namespaceSeed())?.trim();
    if (namespaceSeed == null || namespaceSeed.isEmpty) return null;

    final root = await _cacheRoot();
    if (createRoot && !await root.exists()) {
      await root.create(recursive: true);
    }

    final namespace = sha256
        .convert(utf8.encode('${AppConstants.baseUrl}\n$namespaceSeed'))
        .toString();
    return File(p.join(root.path, '$namespace.html'));
  }

  /// 读取当前账号/会话缓存。
  ///
  /// [maxAge] 只控制本次是否允许复用，不会删除仍在 [cacheTtl] 内的快照。
  /// 这样启动 fast-path 可以严格限制动态数据的新鲜度，同时磁盘维护仍采用
  /// 独立的硬 TTL，不把“这次不够新”误当成“缓存文件已经损坏/必须删除”。
  Future<String?> readCurrentAccount({Duration? maxAge}) async {
    if (!await _isEnabled()) return null;

    final file = await _fileForCurrentAccount(createRoot: false);
    if (file == null) return null;
    final root = file.parent;
    if (!await root.exists()) return null;

    // 启动读取只检查当前会话文件，不在关键路径遍历所有账号缓存。
    // 全局过期维护留给后台写入路径执行。
    if (!await file.exists()) return null;

    try {
      final modifiedAt = await file.lastModified();
      if (_isExpired(modifiedAt)) {
        await _deleteFileBestEffort(file);
        return null;
      }

      if (maxAge != null) {
        final age = _now().difference(modifiedAt);
        if (!age.isNegative && age >= maxAge) {
          return null;
        }
      }

      return await file.readAsString();
    } on FileSystemException catch (e) {
      debugPrint('[PreloadCache] 读取缓存失败，回退网络: $e');
      return null;
    }
  }

  /// 写入当前账号/会话缓存。调用方可不等待该 Future，避免阻塞 preload 关键路径。
  Future<void> writeCurrentAccount(String html) async {
    if (html.isEmpty || !await _isEnabled()) return;

    final file = await _fileForCurrentAccount(createRoot: true);
    if (file == null) return;

    final root = file.parent;
    await _pruneExpired(root);

    final stamp = _now();
    final temp = File('${file.path}.tmp-$pid-${stamp.microsecondsSinceEpoch}');
    try {
      await temp.writeAsString(_sanitizeForPersistence(html), flush: true);
      await temp.setLastModified(stamp);

      try {
        await temp.rename(file.path);
      } on FileSystemException {
        // Windows 不允许 rename 覆盖现有文件。临时文件已经完整落盘，
        // 删除旧版本后再做最终替换，避免把半写入内容暴露给读取方。
        if (await file.exists()) await file.delete();
        await temp.rename(file.path);
      }
      if (await file.exists()) await file.setLastModified(stamp);
    } on FileSystemException catch (e) {
      debugPrint('[PreloadCache] 写入缓存失败(忽略): $e');
      await _deleteFileBestEffort(temp);
    }
  }

  /// 统一清理所有账号/会话的 preload cache。
  ///
  /// 返回删除前的缓存文件数量，便于未来 UI 展示统计；清理不受实验开关影响。
  Future<int> clearAll() async {
    final root = await _cacheRoot();
    if (!await root.exists()) return 0;

    var files = 0;
    try {
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) files++;
      }
      await root.delete(recursive: true);
      debugPrint('[PreloadCache] 已统一清理 $files 个缓存文件');
      return files;
    } on FileSystemException catch (e) {
      debugPrint('[PreloadCache] 统一清理失败: $e');
      rethrow;
    }
  }

  bool _isExpired(DateTime modifiedAt) {
    final age = _now().difference(modifiedAt);
    return !age.isNegative && age >= cacheTtl;
  }

  /// 去掉不能安全跨请求长期复用的 HTML 元数据。
  ///
  /// data-preloaded 内的 JSON 字符串会把双引号转义，因此这些正则只会命中
  /// 真正的 HTML meta/attribute，不会误删帖子正文中作为 JSON 内容出现的文本。
  String _sanitizeForPersistence(String html) {
    var sanitized = html.replaceAll(
      RegExp(
        '''<meta\\b[^>]*\\bname=["']csrf-token["'][^>]*>''',
        caseSensitive: false,
      ),
      '',
    );
    sanitized = sanitized.replaceAll(
      RegExp('''\\sdata-sitekey=["'][^"']*["']''', caseSensitive: false),
      '',
    );
    return sanitized;
  }

  Future<void> _pruneExpired(Directory root) async {
    if (!await root.exists()) return;

    try {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.html')) continue;
        try {
          if (_isExpired(await entity.lastModified())) {
            await entity.delete();
          }
        } on FileSystemException {
          // 可能正被另一请求替换，下一次维护再处理即可。
        }
      }
    } on FileSystemException catch (e) {
      debugPrint('[PreloadCache] 过期缓存维护失败(忽略): $e');
    }
  }

  Future<void> _deleteFileBestEffort(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // cache 删除失败不应该影响业务请求。
    }
  }
}
