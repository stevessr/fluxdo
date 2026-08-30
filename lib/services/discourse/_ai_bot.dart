part of 'discourse_service.dart';

/// Discourse AI Bot 会话列表项。
///
/// 官方接口返回的是 ListableTopicSerializer，因此这里只解析页面实际需要的
/// 稳定字段；其余 Topic 字段继续由 TopicDetailPage 按需加载。
class AiBotConversation {
  final int id;
  final String title;
  final String slug;
  final int postsCount;
  final DateTime? lastPostedAt;
  final bool starred;
  final DateTime? starredAt;

  const AiBotConversation({
    required this.id,
    required this.title,
    required this.slug,
    required this.postsCount,
    this.lastPostedAt,
    required this.starred,
    this.starredAt,
  });

  factory AiBotConversation.fromJson(Map<String, dynamic> json) {
    return AiBotConversation(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      postsCount: (json['posts_count'] as num?)?.toInt() ?? 0,
      lastPostedAt: TimeUtils.parseUtcTime(json['last_posted_at'] as String?),
      starred: json['ai_conversation_starred'] as bool? ?? false,
      starredAt: TimeUtils.parseUtcTime(
        json['ai_conversation_starred_at'] as String?,
      ),
    );
  }

  AiBotConversation copyWith({bool? starred, DateTime? starredAt}) {
    return AiBotConversation(
      id: id,
      title: title,
      slug: slug,
      postsCount: postsCount,
      lastPostedAt: lastPostedAt,
      starred: starred ?? this.starred,
      starredAt: starredAt ?? this.starredAt,
    );
  }
}

/// AI Bot 会话分页响应。
class AiBotConversationList {
  final List<AiBotConversation> conversations;
  final Map<String, dynamic> meta;
  final int page;
  final int perPage;

  const AiBotConversationList({
    required this.conversations,
    required this.meta,
    required this.page,
    required this.perPage,
  });

  bool get hasMore {
    final moreTopicsUrl = meta['more_topics_url'];
    if (moreTopicsUrl is String) return moreTopicsUrl.isNotEmpty;

    final total = (meta['total'] as num?)?.toInt();
    if (total != null) return (page + 1) * perPage < total;

    // 不依赖服务端 meta 的具体版本；恰好满页时多请求一次即可确认结束。
    return conversations.length >= perPage;
  }
}

/// 新建 AI Bot 会话后的首帖定位信息。
class AiBotConversationCreateResult {
  final int topicId;
  final int? postId;
  final int? postNumber;
  final String? topicSlug;
  final String? postUrl;

  const AiBotConversationCreateResult({
    required this.topicId,
    this.postId,
    this.postNumber,
    this.topicSlug,
    this.postUrl,
  });

  factory AiBotConversationCreateResult.fromJson(Map<String, dynamic> json) {
    return AiBotConversationCreateResult(
      topicId: (json['topic_id'] as num?)?.toInt() ?? 0,
      postId: (json['id'] as num?)?.toInt(),
      postNumber: (json['post_number'] as num?)?.toInt(),
      topicSlug: json['topic_slug'] as String?,
      postUrl: json['post_url'] as String?,
    );
  }
}

/// Discourse AI 插件在 current_user serializer 注入的 Agent。
class AiBotAgent {
  final int id;
  final String name;
  final String description;
  final String? username;
  final bool allowPersonalMessages;
  final bool forceDefaultLlm;

  const AiBotAgent({
    required this.id,
    required this.name,
    required this.description,
    this.username,
    required this.allowPersonalMessages,
    required this.forceDefaultLlm,
  });

  factory AiBotAgent.fromJson(Map<String, dynamic> json) {
    return AiBotAgent(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      username: json['username'] as String?,
      allowPersonalMessages: json['allow_personal_messages'] as bool? ?? false,
      forceDefaultLlm: json['force_default_llm'] as bool? ?? false,
    );
  }
}

/// Discourse AI 插件在 current_user serializer 注入的可用聊天机器人。
class AiBotLlm {
  final int id;
  final String username;
  final String displayName;
  final int? llmModelId;
  final bool isAgent;

  const AiBotLlm({
    required this.id,
    required this.username,
    required this.displayName,
    this.llmModelId,
    required this.isAgent,
  });

  factory AiBotLlm.fromJson(Map<String, dynamic> json) {
    return AiBotLlm(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: json['username'] as String? ?? '',
      displayName:
          json['display_name'] as String? ?? json['username'] as String? ?? '',
      llmModelId: (json['llm_model_id'] as num?)?.toInt(),
      isAgent: json['is_agent'] as bool? ?? false,
    );
  }
}

/// Discourse AI Bot 相关 API。
mixin _AiBotMixin on _DiscourseServiceBase {
  /// 获取 AI 对话历史。官方默认每页 40 条，最大 100 条。
  Future<AiBotConversationList> getAiBotConversations({
    int page = 0,
    int perPage = 40,
  }) async {
    try {
      final response = await _dio.get(
        '/discourse-ai/ai-bot/conversations.json',
        queryParameters: {'page': page, 'per_page': perPage},
      );
      final data = response.data as Map<String, dynamic>;
      final rows = data['conversations'] as List<dynamic>? ?? const [];
      return AiBotConversationList(
        conversations: rows
            .whereType<Map<String, dynamic>>()
            .map(AiBotConversation.fromJson)
            .where((item) => item.id > 0)
            .toList(),
        meta: data['meta'] is Map<String, dynamic>
            ? data['meta'] as Map<String, dynamic>
            : const <String, dynamic>{},
        page: page,
        perPage: perPage,
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 创建一段新的官方 AI Bot 私信会话。
  Future<AiBotConversationCreateResult> createAiBotConversation({
    required String raw,
    required String targetUsername,
    int? aiAgentId,
  }) async {
    try {
      final response = await _dio.post(
        '/discourse-ai/ai-bot/conversations.json',
        data: <String, dynamic>{
          'raw': raw,
          'target_username': targetUsername,
          if (aiAgentId != null) 'ai_agent_id': aiAgentId,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final body = response.data;
      if (body is! Map) {
        throw Exception('AI Bot 返回了无法识别的数据格式');
      }

      final data = Map<String, dynamic>.from(body);
      if (data['success'] == false) {
        final errors = data['errors'];
        final message = errors is List ? errors.join('\n') : errors?.toString();
        throw Exception(message ?? '创建 AI 对话失败');
      }

      // 当前 Discourse 成功时直接返回 PostSerializer；兼容旧版可能包一层 post。
      final payload = data['post'] is Map
          ? Map<String, dynamic>.from(data['post'] as Map)
          : data;
      final result = AiBotConversationCreateResult.fromJson(payload);
      if (result.topicId <= 0) {
        throw Exception('AI Bot 响应缺少 topic_id');
      }
      return result;
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 收藏或取消收藏 AI 会话。
  Future<bool> setAiBotConversationStarred({
    required int topicId,
    required bool starred,
  }) async {
    try {
      final response = await _dio.put(
        '/discourse-ai/ai-bot/conversations/$topicId/starred.json',
        data: {'starred': starred},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = response.data;
      if (data is Map && data['starred'] is bool) {
        return data['starred'] as bool;
      }
      return starred;
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 停止指定 AI 回复继续流式生成。
  Future<void> stopAiBotStreaming(int postId) async {
    try {
      await _dio.post('/discourse-ai/ai-bot/post/$postId/stop-streaming.json');
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 让服务端重新生成指定 AI 回复。
  Future<void> retryAiBotResponse(int postId) async {
    try {
      await _dio.post('/discourse-ai/ai-bot/post/$postId/retry.json');
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }
}
