part of 'discourse_service.dart';

/// 通知相关
mixin _NotificationsMixin on _DiscourseServiceBase {
  /// 获取最近通知（recent 模式，非分页，用于快捷面板/通知子分类）
  ///
  /// Discourse 只在 recent 分支真正应用 `filter_by_types`。分类请求应同时
  /// 传 `silent=true`，否则打开一个分类也会 bump last seen notification。
  Future<NotificationListResponse> getRecentNotifications({
    List<String>? filterByTypes,
    int limit = 30,
    bool silent = false,
    bool bumpLastSeenReviewable = true,
  }) async {
    final queryParams = <String, dynamic>{
      'recent': true,
      'limit': limit,
    };
    if (bumpLastSeenReviewable) {
      queryParams['bump_last_seen_reviewable'] = true;
    }
    if (filterByTypes != null && filterByTypes.isNotEmpty) {
      queryParams['filter_by_types'] = filterByTypes.join(',');
    }
    if (silent) {
      queryParams['silent'] = true;
    }

    final response = await _dio.get(
      '/notifications',
      queryParameters: queryParams,
    );
    return NotificationListResponse.fromJson(response.data);
  }

  /// 获取通知历史列表（默认模式，支持完整分页）
  ///
  /// Discourse 原生支持 filter=read / filter=unread；all 不传 filter。
  /// 注意：虽然 controller 会解析 `filter_by_types`，当前 Discourse 的
  /// 非 recent 历史分支并不会把它应用到查询，因此这里不要暴露一个看似
  /// 可用、实际会被服务端忽略的类型过滤参数。
  Future<NotificationListResponse> getNotifications({
    int? offset,
    String? filter,
  }) async {
    final queryParams = <String, dynamic>{
      'limit': 60,
    };
    if (offset != null) {
      queryParams['offset'] = offset;
    }
    if (filter != null && filter.isNotEmpty && filter != 'all') {
      queryParams['filter'] = filter;
    }

    final response = await _dio.get(
      '/notifications',
      queryParameters: queryParams,
    );
    return NotificationListResponse.fromJson(response.data);
  }

  /// 标记所有通知为已读
  Future<void> markAllNotificationsRead() async {
    await _dio.put('/notifications/mark-read');
  }

  /// 标记单条通知为已读
  Future<void> markNotificationRead(int id) async {
    await _dio.put('/notifications/mark-read', data: {'id': id});
  }
}
