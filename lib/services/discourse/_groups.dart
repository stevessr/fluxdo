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
        data: {
          'usernames': normalized.join(','),
          'notify_users': notifyUsers,
        },
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
}
