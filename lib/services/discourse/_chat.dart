part of 'discourse_service.dart';

/// Chat 相关 API
mixin _ChatMixin on _DiscourseServiceBase {
  /// 获取当前用户的 Chat 频道列表
  Future<Map<String, dynamic>> getChatChannels() async {
    final response = await _dio.get('/chat/api/me/channels');
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// 获取指定频道的消息列表
  ///
  /// [direction] 可选值: 'forward' | 'backward' | 'around'
  Future<Map<String, dynamic>> getChannelMessages(
    int channelId, {
    int? pageSize,
    int? targetMessageId,
    String? direction,
    bool? fetchFromLastRead,
  }) async {
    final queryParameters = <String, dynamic>{};
    if (pageSize != null) queryParameters['page_size'] = pageSize;
    if (targetMessageId != null) {
      queryParameters['target_message_id'] = targetMessageId;
    }
    if (direction != null) queryParameters['direction'] = direction;
    if (fetchFromLastRead != null) {
      queryParameters['fetch_from_last_read'] = fetchFromLastRead;
    }
    final response = await _dio.get(
      '/chat/api/channels/$channelId/messages',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// 发送 Chat 消息
  ///
  /// 返回服务端分配的 [message_id]
  Future<int> sendChatMessage(
    int channelId,
    String message, {
    int? threadId,
    int? inReplyToId,
    List<int>? uploadIds,
    String? stagedId,
  }) async {
    final data = <String, dynamic>{
      'message': message,
      'chat_channel_id': channelId,
    };
    if (threadId != null) data['thread_id'] = threadId;
    if (inReplyToId != null) data['in_reply_to_id'] = inReplyToId;
    if (uploadIds != null && uploadIds.isNotEmpty) {
      data['upload_ids'] = uploadIds;
    }
    if (stagedId != null) data['staged_id'] = stagedId;

    try {
      final response = await _dio.post(
        '/chat/api/channels/$channelId/messages',
        data: data,
      );
      final respData = Map<String, dynamic>.from(response.data as Map);
      final msgObj = respData['chat_message'] is Map
          ? respData['chat_message'] as Map
          : null;
      return (respData['message_id'] as num?)?.toInt() ??
          (msgObj?['id'] as num?)?.toInt() ??
          (respData['id'] as num?)?.toInt() ??
          0;
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 编辑 Chat 消息
  Future<void> updateChatMessage(
    int channelId,
    int messageId,
    String message,
  ) async {
    try {
      await _dio.put(
        '/chat/api/channels/$channelId/messages/$messageId',
        data: {'message': message, 'chat_channel_id': channelId},
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 删除 Chat 消息
  Future<void> deleteChatMessage(int channelId, int messageId) async {
    try {
      await _dio.delete(
        '/chat/api/channels/$channelId/messages/$messageId',
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 标记频道已读
  Future<void> markChannelRead(int channelId, int messageId) async {
    try {
      await _dio.put(
        '/chat/api/channels/$channelId/read',
        data: {'message_id': messageId},
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 创建私信频道
  ///
  /// 返回新创建的频道 [id]
  Future<int> createDirectMessageChannel(
    List<String> targetUsernames,
  ) async {
    final response = await _dio.post(
      '/chat/api/direct-message-channels',
      data: {'target_usernames': targetUsernames},
    );
    final respData = response.data as Map<String, dynamic>;
    return (respData['id'] as num?)?.toInt() ?? 0;
  }

  /// 搜索 Chat 可提及用户
  Future<Map<String, dynamic>> searchChatables(String filter) async {
    final response = await _dio.get(
      '/chat/api/chatables',
      queryParameters: {'filter': filter},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// 获取指定频道的成员列表
  Future<List<Map<String, dynamic>>> getChannelMembers(
    int channelId, {
    String? filter,
  }) async {
    final queryParameters = <String, dynamic>{};
    if (filter != null && filter.isNotEmpty) {
      queryParameters['filter'] = filter;
    }

    try {
      final response = await _dio.get(
        '/chat/api/channels/$channelId/members',
        queryParameters: queryParameters.isEmpty ? null : queryParameters,
      );
      final data = response.data;
      if (data is Map) {
        final list = data['members'] ??
            data['memberships'] ??
            data['users'] ??
            data['channel_members'];
        if (list is List) {
          return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } else if (data is List) {
        return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 向指定频道添加/邀请成员
  Future<void> addChannelMember(int channelId, String username) async {
    try {
      await _dio.post(
        '/chat/api/channels/$channelId/members',
        data: {'username': username},
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 关注/取消关注（收藏）频道
  Future<void> followChannel(int channelId, {required bool follow}) async {
    try {
      if (follow) {
        await _dio.post('/chat/api/channels/$channelId/follow');
      } else {
        await _dio.post('/chat/api/channels/$channelId/unfollow');
      }
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }
}