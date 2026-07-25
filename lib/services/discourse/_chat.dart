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
      Response response;
      try {
        response = await _dio.post(
          '/chat/api/channels/$channelId/messages',
          data: data,
        );
      } catch (_) {
        try {
          response = await _dio.post(
            '/chat/chat_channels/$channelId/messages.json',
            data: data,
          );
        } catch (_) {
          response = await _dio.post(
            '/chat/$channelId/create.json',
            data: data,
          );
        }
      }

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

  /// 获取指定频道的成员列表 (Discourse 最新标准 Endpoint)
  Future<List<Map<String, dynamic>>> getChannelMembers(
    int channelId, {
    String? filter,
    int limit = 200,
    int offset = 0,
  }) async {
    final queryParameters = <String, dynamic>{
      'limit': limit,
      'offset': offset,
    };
    if (filter != null && filter.isNotEmpty) {
      queryParameters['filter'] = filter;
    }

    try {
      final response = await _dio.get(
        '/chat/api/channels/$channelId/members',
        queryParameters: queryParameters,
      );
      return _extractMemberList(response.data);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  List<Map<String, dynamic>> _extractMemberList(dynamic data) {
    if (data is Map) {
      final mapData = Map<String, dynamic>.from(data);
      final usersMap = <int, Map<String, dynamic>>{};

      // 1. 提取顶层 users 数组 (Discourse 标准 API 中包含完整的 user 对象)
      final rawUsers = mapData['users'] ??
          (mapData['chat_channel'] is Map ? mapData['chat_channel']['users'] : null) ??
          mapData['target_users'];
      if (rawUsers is List) {
        for (final u in rawUsers) {
          if (u is Map) {
            final uMap = Map<String, dynamic>.from(u);
            final id = (uMap['id'] as num?)?.toInt();
            if (id != null) usersMap[id] = uMap;
          }
        }
      }

      // 2. 提取成员或 membership 列表
      final rawMembers = mapData['members'] ??
          mapData['memberships'] ??
          mapData['channel_members'] ??
          mapData['user_chat_channel_memberships'] ??
          (mapData['chat_channel'] is Map
              ? (mapData['chat_channel']['memberships'] ?? mapData['chat_channel']['members'])
              : null);

      final result = <Map<String, dynamic>>[];
      final addedIds = <int>{};

      if (rawMembers is List) {
        for (final e in rawMembers) {
          if (e is! Map) continue;
          final item = Map<String, dynamic>.from(e);
          Map<String, dynamic>? userObj;

          if (item['user'] is Map) {
            userObj = Map<String, dynamic>.from(item['user'] as Map);
          } else if (item['user_chat_channel_membership'] is Map &&
              item['user_chat_channel_membership']['user'] is Map) {
            userObj = Map<String, dynamic>.from(
                item['user_chat_channel_membership']['user'] as Map);
          } else {
            final userId = (item['user_id'] as num?)?.toInt() ??
                (item['id'] as num?)?.toInt();
            if (userId != null && usersMap.containsKey(userId)) {
              userObj = usersMap[userId];
            } else if (item.containsKey('username')) {
              userObj = item;
            }
          }

          if (userObj != null) {
            final uid = (userObj['id'] as num?)?.toInt() ?? 0;
            if (addedIds.add(uid)) {
              result.add(userObj);
            }
          }
        }
      }

      // 3. 将顶层 usersMap 中尚未包含的成员全部加入列表
      for (final entry in usersMap.entries) {
        if (addedIds.add(entry.key)) {
          result.add(entry.value);
        }
      }

      return result;
    } else if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
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

  /// 对 Chat 消息点赞/回应/取消回应 (Reaction)
  Future<void> reactToChatMessage(
    int channelId,
    int messageId,
    String emoji, {
    required String action, // 'add' | 'remove'
  }) async {
    final data = <String, dynamic>{
      'emoji': emoji,
      'react_action': action,
      'message_id': messageId,
    };
    try {
      await _dio.put(
        '/chat/api/channels/$channelId/messages/$messageId/reactions',
        data: data,
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 设置/取消 Chat 消息书签 (Bookmark)
  Future<void> toggleChatMessageBookmark(
    int channelId,
    int messageId, {
    required bool bookmarked,
  }) async {
    try {
      if (bookmarked) {
        await _dio.post(
          '/bookmarks.json',
          data: {
            'bookmarkable_type': 'ChatMessage',
            'bookmarkable_id': messageId,
          },
        );
      } else {
        await _dio.delete(
          '/chat/api/channels/$channelId/messages/$messageId/bookmark',
        );
      }
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 修改 Chat 频道设置（频道名称、缩略名、表情图标、免打扰、消息串开关等）
  Future<void> updateChannelSettings(
    int channelId, {
    String? name,
    String? slug,
    String? emoji,
    bool? threadingEnabled,
    bool? muted,
    String? notificationLevel,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (slug != null) data['slug'] = slug;
    if (emoji != null) data['emoji'] = emoji;
    if (threadingEnabled != null) data['threading_enabled'] = threadingEnabled;
    if (muted != null) data['muted'] = muted;
    if (notificationLevel != null) data['notification_level'] = notificationLevel;

    if (data.isEmpty) return;

    try {
      await _dio.put('/chat/api/channels/$channelId', data: data);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 浏览论坛中的公开频道
  ///
  /// [status] 可选值: 'open' | 'closed' | null(全部)
  /// [filter] 按名称搜索
  /// [offset] 分页偏移
  Future<Map<String, dynamic>> browseChannels({
    String? status,
    String? filter,
    int offset = 0,
    int limit = 25,
  }) async {
    final queryParameters = <String, dynamic>{
      'limit': limit,
      'offset': offset,
    };
    if (status != null && status.isNotEmpty) {
      queryParameters['status'] = status;
    }
    if (filter != null && filter.isNotEmpty) {
      queryParameters['filter'] = filter;
    }

    try {
      final response = await _dio.get(
        '/chat/api/channels',
        queryParameters: queryParameters,
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 加入（关注）指定频道
  ///
  /// 使用 POST /chat/api/channels/:id/memberships/me 端点
  Future<void> joinChannel(int channelId) async {
    try {
      await _dio.post('/chat/api/channels/$channelId/memberships/me');
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 离开（取消关注）指定频道
  ///
  /// 使用 DELETE /chat/api/channels/:id/memberships/me 端点
  Future<void> leaveChannel(int channelId) async {
    try {
      await _dio.delete('/chat/api/channels/$channelId/memberships/me');
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }
}