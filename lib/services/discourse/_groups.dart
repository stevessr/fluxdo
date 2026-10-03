part of 'discourse_service.dart';

/// Discourse 原生群组 API。
///
/// 对齐上游 GroupsController / Group model：目录使用 `/groups.json`，详情
/// `/groups/:name.json`，成员 `/groups/:name/members.json`，手工加成员使用
/// `PUT /groups/:id/members.json`。自助加入/退出分别使用
/// `PUT /groups/:id/join.json` 与 `DELETE /groups/:id/leave.json`。
mixin _GroupsMixin on _DiscourseServiceBase {
  Future<GroupDirectoryResult> fetchGroups({
    int page = 0,
    String? filter,
    String? type,
    String? order,
    bool? asc,
    String? username,
  }) async {
    try {
      final response = await _dio.get(
        '/groups.json',
        queryParameters: {
          'page': page,
          if (filter != null && filter.isNotEmpty) 'filter': filter,
          if (type != null && type.isNotEmpty) 'type': type,
          if (order != null && order.isNotEmpty) 'order': order,
          if (asc != null) 'asc': asc,
          if (username != null && username.isNotEmpty) 'username': username,
        },
      );
      if (response.data is! Map) {
        throw const FormatException('Invalid groups response');
      }
      return GroupDirectoryResult.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<DiscourseGroup> fetchGroup(String name) async {
    try {
      final encoded = Uri.encodeComponent(name);
      final response = await _dio.get('/groups/$encoded.json');
      if (response.data is! Map) {
        throw const FormatException('Invalid group response');
      }
      final root = Map<String, dynamic>.from(response.data as Map);
      final raw = root['group'];
      if (raw is! Map) {
        throw const FormatException('Group payload is missing');
      }
      return DiscourseGroup.fromJson(Map<String, dynamic>.from(raw));
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<GroupMembersResult> fetchGroupMembers(
    String name, {
    int offset = 0,
    String? filter,
    String? order,
    bool? asc,
    bool requesters = false,
  }) async {
    try {
      final encoded = Uri.encodeComponent(name);
      final response = await _dio.get(
        '/groups/$encoded/members.json',
        queryParameters: {
          'offset': offset,
          if (filter != null && filter.isNotEmpty) 'filter': filter,
          if (order != null && order.isNotEmpty) 'order': order,
          if (asc != null) 'asc': asc,
          if (requesters) 'requesters': true,
        },
      );
      if (response.data is! Map) {
        throw const FormatException('Invalid group members response');
      }
      return GroupMembersResult.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 获取待审批的群组加入申请。Discourse 复用 members 端点并加
  /// requesters=true；分页元信息与普通成员列表相同。
  Future<GroupMembersResult> fetchGroupMembershipRequests(
    String name, {
    int offset = 0,
    String? filter,
    String? order,
    bool? asc,
  }) => fetchGroupMembers(
    name,
    offset: offset,
    filter: filter,
    order: order,
    asc: asc,
    requesters: true,
  );

  /// 当前用户自助加入群组。入口是否展示由 GroupSerializer 下发的
  /// `public_admission` / `is_group_user` 决定，最终权限仍由服务端校验。
  Future<void> joinGroup(int groupId) async {
    try {
      await _dio.put('/groups/$groupId/join.json');
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 当前用户自助退出群组。入口是否展示由 GroupSerializer 下发的
  /// `public_exit` / `is_group_user` 决定，最终权限仍由服务端校验。
  Future<void> leaveGroup(int groupId) async {
    try {
      await _dio.delete('/groups/$groupId/leave.json');
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 手工添加成员。调用方只负责按 serializer 权限决定是否展示入口，真正的
  /// 权限校验仍由 Discourse 服务端执行，避免客户端权限状态过期造成越权。
  Future<List<String>> addGroupMembers({
    required int groupId,
    required List<String> usernames,
    bool notifyUsers = true,
  }) async {
    final normalized = usernames
        .map((username) => username.trim())
        .where((username) => username.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalized.isEmpty) return const [];

    try {
      final response = await _dio.put(
        '/groups/$groupId/members.json',
        data: {'usernames': normalized.join(','), 'notify_users': notifyUsers},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      if (response.data is Map) {
        final raw = (response.data as Map)['usernames'];
        if (raw is List) {
          return raw.map((item) => item.toString()).toList(growable: false);
        }
        if (raw is String && raw.isNotEmpty) {
          return raw
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false);
        }
      }
      return normalized;
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 从群组移除成员。
  Future<void> removeGroupMember({
    required int groupId,
    required String username,
  }) async {
    final normalized = username.trim();
    if (normalized.isEmpty) return;
    try {
      await _dio.delete(
        '/groups/$groupId/members.json',
        data: {'username': normalized},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 添加群组所有者。
  Future<void> addGroupOwners({
    required int groupId,
    required List<String> usernames,
  }) async {
    final normalized = usernames
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalized.isEmpty) return;
    try {
      await _dio.put(
        '/groups/$groupId/owners.json',
        data: {'usernames': normalized.join(',')},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 移除群组所有者。
  Future<void> removeGroupOwner({
    required int groupId,
    required int userId,
  }) async {
    try {
      // Admin::GroupsController#remove_owner accepts user_id directly (or
      // group[usernames]). Prefer the stable scalar form to avoid nested form
      // encoding differences between Dio versions.
      await _dio.delete(
        '/admin/groups/$groupId/owners.json',
        data: {'user_id': userId},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 为一批用户设置/取消该主要群组（Discourse admin API）。
  Future<void> setPrimaryGroupForUsers({
    required int groupId,
    required List<String> usernames,
    required bool primary,
  }) async {
    final normalized = usernames
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalized.isEmpty) return;
    try {
      await _dio.put(
        '/admin/groups/$groupId/primary.json',
        data: {
          'usernames': normalized.join(','),
          'primary': primary.toString(),
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 申请加入需要审核的群组。
  Future<void> requestGroupMembership(
    String groupName, {
    required String reason,
  }) async {
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'must not be empty');
    }
    final encoded = Uri.encodeComponent(groupName);
    try {
      await _dio.post(
        '/groups/$encoded/request_membership.json',
        data: {'reason': normalizedReason},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 审批群组加入申请。
  Future<void> handleGroupMembershipRequest({
    required int groupId,
    required int userId,
    required bool accept,
  }) async {
    try {
      await _dio.put(
        '/groups/$groupId/handle_membership_request.json',
        data: {'user_id': userId, 'accept': accept},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 设置当前用户对群组的通知级别。
  Future<void> setGroupNotificationLevel(
    String groupName, {
    required int notificationLevel,
    int? userId,
  }) async {
    final encoded = Uri.encodeComponent(groupName);
    try {
      await _dio.post(
        '/groups/$encoded/notifications.json',
        data: {
          'notification_level': notificationLevel,
          if (userId != null) 'user_id': userId,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 获取群组帖子/提及列表，供原生群组页扩展 activity。
  Future<Map<String, dynamic>> fetchGroupActivity(
    String name, {
    String type = 'posts',
    int? offset,
  }) async {
    if (type != 'posts' && type != 'mentions') {
      throw ArgumentError.value(type, 'type', 'must be posts or mentions');
    }
    final encoded = Uri.encodeComponent(name);
    try {
      final response = await _dio.get(
        '/groups/$encoded/$type.json',
        queryParameters: {if (offset != null) 'offset': offset},
      );
      return response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }
}
