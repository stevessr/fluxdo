part of 'discourse_service.dart';

/// Discourse parity APIs that are shared by multiple UI surfaces.
///
/// Keep these endpoints close to upstream route names instead of hiding them
/// behind linux.do-specific assumptions. Capability and permission checks still
/// belong to serializers/server responses; callers should not infer access from
/// client-side state alone.
mixin _DiscourseParityMixin on _DiscourseServiceBase {
  Future<String> _requireParityUsername() async {
    final username = await getUsername();
    if (username == null || username.isEmpty) {
      throw Exception(S.current.error_notLoggedInNoUsername);
    }
    return username;
  }

  Future<TopicListResponse> getPrivateMessagesUnread({int page = 0}) async {
    final username = await _requireParityUsername();
    final response = await _dio.get(
      '/topics/private-messages-unread/$username.json',
      queryParameters: page > 0 ? {'page': page} : null,
    );
    return TopicListResponse.fromJson(response.data);
  }

  Future<TopicListResponse> getPrivateMessagesNew({int page = 0}) async {
    final username = await _requireParityUsername();
    final response = await _dio.get(
      '/topics/private-messages-new/$username.json',
      queryParameters: page > 0 ? {'page': page} : null,
    );
    return TopicListResponse.fromJson(response.data);
  }

  /// Staff-only warning mailbox. The server remains the source of truth for
  /// whether the current user may access this route.
  Future<TopicListResponse> getPrivateMessagesWarnings({int page = 0}) async {
    final username = await _requireParityUsername();
    final response = await _dio.get(
      '/topics/private-messages-warnings/$username.json',
      queryParameters: page > 0 ? {'page': page} : null,
    );
    return TopicListResponse.fromJson(response.data);
  }

  Future<TopicListResponse> getGroupPrivateMessages(
    String groupName, {
    int page = 0,
    bool unreadOnly = false,
    bool newOnly = false,
    bool archived = false,
  }) async {
    assert(
      [unreadOnly, newOnly, archived].where((value) => value).length <= 1,
      'Only one group PM filter can be active at a time.',
    );
    final username = await _requireParityUsername();
    final encodedGroup = Uri.encodeComponent(groupName);
    final suffix = archived
        ? '/archive'
        : unreadOnly
        ? '/unread'
        : newOnly
        ? '/new'
        : '';
    final response = await _dio.get(
      '/topics/private-messages-group/$username/$encodedGroup$suffix.json',
      queryParameters: page > 0 ? {'page': page} : null,
    );
    return TopicListResponse.fromJson(response.data);
  }

  /// Ask to join a closed/public-request group. The route returns extra data on
  /// some sites (for example a generated topic URL), so preserve the payload.
  Future<Map<String, dynamic>> requestGroupMembership(
    String groupName, {
    String? reason,
  }) async {
    try {
      final encodedGroup = Uri.encodeComponent(groupName);
      final response = await _dio.post(
        '/groups/$encodedGroup/request_membership.json',
        data: {
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return const <String, dynamic>{};
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// Raw group activity payload. Upstream can extend the serializer, therefore
  /// this API intentionally keeps unknown plugin fields instead of dropping them.
  Future<Map<String, dynamic>> getGroupActivityPosts(
    String groupName, {
    int offset = 0,
  }) async {
    final encodedGroup = Uri.encodeComponent(groupName);
    final response = await _dio.get(
      '/groups/$encodedGroup/posts.json',
      queryParameters: offset > 0 ? {'offset': offset} : null,
    );
    if (response.data is! Map) {
      throw const FormatException('Invalid group posts response');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getGroupActivityMentions(
    String groupName, {
    int offset = 0,
  }) async {
    final encodedGroup = Uri.encodeComponent(groupName);
    final response = await _dio.get(
      '/groups/$encodedGroup/mentions.json',
      queryParameters: offset > 0 ? {'offset': offset} : null,
    );
    if (response.data is! Map) {
      throw const FormatException('Invalid group mentions response');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }
}
