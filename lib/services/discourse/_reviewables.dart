part of 'discourse_service.dart';

/// 解析 enqueued 响应里的 `pending_post` 字段(可能缺失/形态异常)
PendingPost? _parsePendingPost(dynamic json) {
  if (json is! Map) return null;
  try {
    return PendingPost.fromJson(Map<String, dynamic>.from(json));
  } catch (_) {
    return null;
  }
}

/// 待审核内容(Reviewable)相关 API —— 仅覆盖「自己的待审内容」视角
mixin _ReviewablesMixin on _DiscourseServiceBase, _UsersMixin {
  /// 获取当前用户的待审核内容列表
  ///
  /// 服务端 GET /posts/{username}/pending.json(PendingPostSerializer),
  /// 权限为本人或 staff;未登录直接返回空列表。
  Future<List<PendingPost>> getMyPendingPosts() async {
    final username = await getUsername();
    if (username == null || username.isEmpty) return const [];

    try {
      final response = await _dio.get('/posts/$username/pending.json');
      final data = response.data;
      final list = data is Map ? data['pending_posts'] : null;
      if (list is! List) return const [];

      final pendingPosts = list
          .whereType<Map>()
          .map((e) => PendingPost.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      await PendingReviewContextStore.retainTopicTags(
        site: AppConstants.baseUrl,
        username: username,
        activeReviewableIds: pendingPosts.map((post) => post.id).toSet(),
      );
      return pendingPosts;
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 读取待审新主题送审时补记的标签。
  ///
  /// 服务端若未来直接在 PendingPostSerializer 返回 tags，调用方应优先使用
  /// [PendingPost.tags]；这里仅补足官方当前缺失的作者视角字段。
  Future<List<String>?> getPendingTopicTags(int reviewableId) async {
    final username = await getUsername();
    if (username == null || username.isEmpty) return null;

    return PendingReviewContextStore.readTopicTags(
      site: AppConstants.baseUrl,
      username: username,
      reviewableId: reviewableId,
    );
  }

  /// 撤回自己的待审核内容
  ///
  /// 服务端 DELETE /review/{id},队列帖创建者本人有权,无需 version
  /// (对齐官方前端 topic.js deletePending)。
  Future<void> deleteReviewable(int reviewableId) async {
    final username = await getUsername();

    try {
      await _dio.delete('/review/$reviewableId');
    } on DioException catch (e) {
      // 404:已被审核/已撤回,视为目标达成
      if (e.response?.statusCode != 404) {
        _throwApiError(e);
      }
    }

    if (username != null && username.isNotEmpty) {
      await PendingReviewContextStore.removeTopicTags(
        site: AppConstants.baseUrl,
        username: username,
        reviewableId: reviewableId,
      );
    }
  }
}
