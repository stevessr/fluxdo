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
  /// [direction] 可选值: 'past' | 'future' (对齐 Discourse messages_query)
  /// - 'past': 返回 target_message_id 之前的消息（不含 target）
  /// - 'future': 返回 target_message_id 之后的消息
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
      // 对齐 Discourse 官方前端 chat-api: POST /chat/:channelId
      // (plugins/chat/config/routes.rb: post "/:chat_channel_id" => "api/channel_messages#create")
      try {
        response = await _dio.post(
          '/chat/$channelId',
          data: data,
        );
      } catch (_) {
        try {
          response = await _dio.post(
            '/chat/api/channels/$channelId/messages',
            data: data,
          );
        } catch (_) {
          response = await _dio.post(
            '/chat/chat_channels/$channelId/messages.json',
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
  ///
  /// 对齐 Discourse chat-api.markChannelAsRead:
  /// PUT /chat/api/channels/:id/read?message_id=
  Future<void> markChannelRead(int channelId, int messageId) async {
    try {
      await _dio.put(
        '/chat/api/channels/$channelId/read',
        queryParameters: {'message_id': messageId},
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 创建私信频道
  ///
  /// 返回新创建的频道 [id]
  ///
  /// Discourse 响应根为 `channel`（Chat::ChannelSerializer）。
  Future<int> createDirectMessageChannel(
    List<String> targetUsernames,
  ) async {
    final response = await _dio.post(
      '/chat/api/direct-message-channels',
      data: {'target_usernames': targetUsernames},
    );
    final respData = Map<String, dynamic>.from(response.data as Map);
    final channel = respData['channel'] is Map
        ? Map<String, dynamic>.from(respData['channel'] as Map)
        : respData;
    return (channel['id'] as num?)?.toInt() ??
        (respData['id'] as num?)?.toInt() ??
        0;
  }

  /// 搜索 Chat 可提及用户/频道
  ///
  /// 对齐 Discourse Chat::SearchChatable：查询参数为 [term]（不是 filter）。
  Future<Map<String, dynamic>> searchChatables(String term) async {
    final response = await _dio.get(
      '/chat/api/chatables',
      queryParameters: {
        'term': term,
        'include_users': true,
        'include_groups': false,
        'include_category_channels': false,
        'include_direct_message_channels': false,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// 在频道内搜索消息
  ///
  /// 对齐 Discourse: GET /chat/api/search
  /// 参数: query, channel_id, limit, offset, sort
  Future<Map<String, dynamic>> searchChannelMessages({
    required String query,
    int? channelId,
    int limit = 20,
    int offset = 0,
    String sort = 'latest',
  }) async {
    final queryParameters = <String, dynamic>{
      'query': query,
      'limit': limit.clamp(1, 40),
      'offset': offset,
      'sort': sort,
    };
    if (channelId != null) {
      queryParameters['channel_id'] = channelId;
    }
    try {
      final response = await _dio.get(
        '/chat/api/search',
        queryParameters: queryParameters,
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 获取指定频道的成员列表
  ///
  /// 对齐 Discourse: GET /chat/api/channels/:id/memberships
  /// 过滤参数为 [username]（非 filter）。
  Future<List<Map<String, dynamic>>> getChannelMembers(
    int channelId, {
    String? filter,
    String? username,
    int limit = 50,
    int offset = 0,
  }) async {
    // Discourse INDEX_LIMIT = 50；服务端会 clamp 到该上限
    final queryParameters = <String, dynamic>{
      'limit': limit.clamp(1, 50),
      'offset': offset,
    };
    final nameFilter = username ?? filter;
    if (nameFilter != null && nameFilter.isNotEmpty) {
      queryParameters['username'] = nameFilter;
    }

    try {
      final response = await _dio.get(
        '/chat/api/channels/$channelId/memberships',
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

  /// 向指定频道添加成员
  ///
  /// 对齐 Discourse chat-api.addMembersToChannel:
  /// POST /chat/api/channels/:id/memberships  body: { usernames: [...] }
  Future<void> addChannelMember(int channelId, String username) async {
    try {
      await _dio.post(
        '/chat/api/channels/$channelId/memberships',
        data: {
          'usernames': [username],
        },
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 设置/取消频道收藏（starred）
  ///
  /// 对齐 Discourse: PUT /chat/api/channels/:id/memberships/me
  /// body: { starred: true|false }
  ///
  /// 注意：这与 join/leave（memberships/me）和 unfollow（memberships/me/follows）不同。
  Future<void> setChannelStarred(int channelId, {required bool starred}) async {
    try {
      await _dio.put(
        '/chat/api/channels/$channelId/memberships/me',
        data: {'starred': starred},
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 关注频道（加入并 following）
  ///
  /// 对齐 Discourse chat-api.followChannel:
  /// POST /chat/api/channels/:id/memberships/me
  Future<void> followChannel(int channelId) async {
    try {
      await _dio.post('/chat/api/channels/$channelId/memberships/me');
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 取消关注频道（保留 membership，仅 following=false）
  ///
  /// 对齐 Discourse chat-api.unfollowChannel:
  /// DELETE /chat/api/channels/:id/memberships/me/follows
  Future<void> unfollowChannel(int channelId) async {
    try {
      await _dio.delete('/chat/api/channels/$channelId/memberships/me/follows');
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
      // 对齐 Discourse 路由: PUT /chat/:chat_channel_id/react/:message_id
      // (plugins/chat/config/routes.rb)。旧路径 /chat/api/channels/.../reactions 不存在。
      await _dio.put(
        '/chat/$channelId/react/$messageId',
        data: data,
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 为 Chat 消息创建书签
  ///
  /// 对齐 Discourse: POST /bookmarks.json
  /// bookmarkable_type 使用 `Chat::Message`（官方前端 chat-message-interactor）。
  /// 返回新建 bookmark 的 id，供后续删除使用。
  Future<int> createChatMessageBookmark(int messageId) async {
    try {
      final response = await _dio.post(
        '/bookmarks.json',
        data: {
          'bookmarkable_type': 'Chat::Message',
          'bookmarkable_id': messageId,
        },
      );
      final respData = Map<String, dynamic>.from(response.data as Map);
      return (respData['id'] as num?)?.toInt() ?? 0;
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 设置/取消 Chat 消息书签
  ///
  /// [bookmarked] 为 true 时创建并返回 bookmarkId；
  /// 为 false 时必须提供 [bookmarkId]，走核心 DELETE /bookmarks/:id.json
  /// （Chat 插件没有独立的 bookmark 删除路由）。
  Future<int?> toggleChatMessageBookmark(
    int channelId,
    int messageId, {
    required bool bookmarked,
    int? bookmarkId,
  }) async {
    try {
      if (bookmarked) {
        return await createChatMessageBookmark(messageId);
      }
      if (bookmarkId == null || bookmarkId <= 0) {
        throw ArgumentError(
          '取消聊天消息书签需要 bookmarkId（Discourse 仅支持 DELETE /bookmarks/:id）',
        );
      }
      // 复用核心书签删除端点（与 _PostsMixin.deleteBookmark 一致）
      await _dio.delete('/bookmarks/$bookmarkId.json');
      return null;
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 修改 Chat 频道元信息（名称、缩略名、表情、消息串等）
  ///
  /// 对齐 Discourse chat-api.updateChannel:
  /// PUT /chat/api/channels/:id  body: { channel: { ... } }
  Future<void> updateChannel(
    int channelId, {
    String? name,
    String? slug,
    String? emoji,
    String? description,
    bool? threadingEnabled,
  }) async {
    final channel = <String, dynamic>{};
    if (name != null) channel['name'] = name;
    if (slug != null) channel['slug'] = slug;
    if (emoji != null) channel['emoji'] = emoji;
    if (description != null) channel['description'] = description;
    if (threadingEnabled != null) {
      channel['threading_enabled'] = threadingEnabled;
    }
    if (channel.isEmpty) return;

    try {
      await _dio.put(
        '/chat/api/channels/$channelId',
        data: {'channel': channel},
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 修改当前用户在频道中的通知设置（免打扰 / 通知级别）
  ///
  /// 对齐 Discourse chat-api.updateCurrentUserChannelNotificationsSettings:
  /// PUT /chat/api/channels/:id/notifications-settings/me
  /// body: { notifications_settings: { muted, notification_level } }
  Future<void> updateChannelNotificationsSettings(
    int channelId, {
    bool? muted,
    String? notificationLevel,
  }) async {
    final settings = <String, dynamic>{};
    if (muted != null) settings['muted'] = muted;
    if (notificationLevel != null) {
      settings['notification_level'] = notificationLevel;
    }
    if (settings.isEmpty) return;

    try {
      await _dio.put(
        '/chat/api/channels/$channelId/notifications-settings/me',
        data: {'notifications_settings': settings},
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 修改 Chat 频道设置（兼容旧调用）
  ///
  /// 频道元信息走 [updateChannel]；muted / notificationLevel 走通知设置端点。
  Future<void> updateChannelSettings(
    int channelId, {
    String? name,
    String? slug,
    String? emoji,
    String? description,
    bool? threadingEnabled,
    bool? muted,
    String? notificationLevel,
  }) async {
    final hasChannelFields = name != null ||
        slug != null ||
        emoji != null ||
        description != null ||
        threadingEnabled != null;
    final hasNotificationFields = muted != null || notificationLevel != null;

    try {
      if (hasChannelFields) {
        await updateChannel(
          channelId,
          name: name,
          slug: slug,
          emoji: emoji,
          description: description,
          threadingEnabled: threadingEnabled,
        );
      }
      if (hasNotificationFields) {
        await updateChannelNotificationsSettings(
          channelId,
          muted: muted,
          notificationLevel: notificationLevel,
        );
      }
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