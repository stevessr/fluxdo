part of 'discourse_service.dart';

/// 通知相关
mixin _NotificationsMixin on _DiscourseServiceBase {
  /// 获取最近通知（recent 模式，非分页，用于快捷面板）
  /// 会触发服务端 bump_last_seen_notification，重置未读计数
  Future<NotificationListResponse> getRecentNotifications() async {
    final response = await _dio.get('/notifications', queryParameters: {
      'recent': true,
      'limit': 30,
      'bump_last_seen_reviewable': true,
    });
    return NotificationListResponse.fromJson(response.data);
  }

  /// 获取通知列表（默认模式，支持完整分页）
  ///
  /// Discourse 原生支持 filter=read / filter=unread；all 不传 filter，
  /// 与 Web 端通知历史页行为保持一致。
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
