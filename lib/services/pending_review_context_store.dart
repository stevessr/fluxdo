import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 待审核内容中服务端作者接口不会回传的编辑上下文。
///
/// Discourse 的 ReviewableQueuedPost 会保留新主题 payload.tags，但作者可见的
/// PendingPostSerializer / TopicPendingPostSerializer 当前都不序列化 tags。
/// 因此客户端需要在送审成功时补记，撤回并重新编辑时再恢复。
///
/// 数据按站点 + 账号 + reviewable id 隔离，并落 SharedPreferences，避免应用
/// 重启后丢失。标签不是凭据或秘密，不需要进入安全存储。
class PendingReviewContextStore {
  PendingReviewContextStore._();

  static const _topicTagsPrefix = 'pending_review_topic_tags_v1';
  static final Map<String, List<String>> _memory = {};

  @visibleForTesting
  static void resetMemoryCacheForTest() => _memory.clear();

  static String _scopePrefix({
    required String site,
    required String username,
  }) {
    return '$_topicTagsPrefix::'
        '${Uri.encodeComponent(site)}::'
        '${Uri.encodeComponent(username)}::';
  }

  static String _topicTagsKey({
    required String site,
    required String username,
    required int reviewableId,
  }) {
    return '${_scopePrefix(site: site, username: username)}$reviewableId';
  }

  static Future<void> recordTopicTags({
    required String site,
    required String username,
    required int reviewableId,
    required Iterable<String> tags,
  }) async {
    final key = _topicTagsKey(
      site: site,
      username: username,
      reviewableId: reviewableId,
    );
    final value = List<String>.unmodifiable(
      tags.where((tag) => tag.isNotEmpty),
    );
    _memory[key] = value;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, value);
    } catch (_) {
      // 持久化失败不能影响已经成功进入审核队列的发帖。
      // 当前进程仍可由 _memory 恢复。
    }
  }

  static Future<List<String>?> readTopicTags({
    required String site,
    required String username,
    required int reviewableId,
  }) async {
    final key = _topicTagsKey(
      site: site,
      username: username,
      reviewableId: reviewableId,
    );

    final cached = _memory[key];
    if (cached != null) return List<String>.of(cached);

    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(key);
      if (stored == null) return null;

      final value = List<String>.unmodifiable(stored);
      _memory[key] = value;
      return List<String>.of(value);
    } catch (_) {
      return null;
    }
  }

  static Future<void> removeTopicTags({
    required String site,
    required String username,
    required int reviewableId,
  }) async {
    final key = _topicTagsKey(
      site: site,
      username: username,
      reviewableId: reviewableId,
    );
    _memory.remove(key);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {
      // 删除失败最多留下无害的陈旧缓存；下次 retain 会再次清理。
    }
  }

  /// 仅保留该账号当前仍存在于待审核列表中的 reviewable 上下文。
  ///
  /// 审核被通过/拒绝后客户端不会收到单独的本地删除事件，因此每次成功刷新
  /// “我的待审核内容”时顺手清理，避免长期积累陈旧标签。
  static Future<void> retainTopicTags({
    required String site,
    required String username,
    required Set<int> activeReviewableIds,
  }) async {
    final prefix = _scopePrefix(site: site, username: username);

    _memory.removeWhere((key, _) {
      if (!key.startsWith(prefix)) return false;
      final id = int.tryParse(key.substring(prefix.length));
      return id == null || !activeReviewableIds.contains(id);
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final staleKeys = prefs.getKeys().where((key) {
        if (!key.startsWith(prefix)) return false;
        final id = int.tryParse(key.substring(prefix.length));
        return id == null || !activeReviewableIds.contains(id);
      }).toList(growable: false);

      for (final key in staleKeys) {
        await prefs.remove(key);
      }
    } catch (_) {
      // 清理属于维护动作，失败不应影响审核队列加载。
    }
  }
}
