part of 'discourse_service.dart';

/// 分类和标签相关
mixin _CategoriesMixin on _DiscourseServiceBase {
  /// 获取站点信息（包含所有分类）
  Future<List<Category>> getCategories() async {
    final preloaded = PreloadedDataService();
    final preloadedCategories = await preloaded.getCategories();
    if (preloadedCategories != null && preloadedCategories.isNotEmpty) {
      return preloadedCategories;
    }

    final response = await _dio.get('/site.json');
    final site = SiteResponse.fromJson(response.data);
    return site.categories;
  }

  /// 获取站点热门标签
  Future<List<String>> getTags() async {
    final preloaded = PreloadedDataService();
    final preloadedTags = await preloaded.getTopTags();
    if (preloadedTags != null) {
      return preloadedTags;
    }

    try {
      final response = await _dio.get('/site.json');
      final data = response.data as Map<String, dynamic>;

      final canTagTopics = data['can_tag_topics'] as bool? ?? false;
      if (!canTagTopics) return [];

      final topTags = data['top_tags'] as List?;
      if (topTags == null) return [];

      return topTags
          .map((t) {
            if (t is Map<String, dynamic>) {
              return t['name'] as String? ?? '';
            }
            return t.toString();
          })
          .where((name) => name.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[DiscourseService] getTags failed: $e');
      return [];
    }
  }

  /// 获取站点全量标签（/tags.json），保留服务端的标签组结构。
  /// 顶层未分组标签归入 name == null 的兜底组;组内按话题数降序。
  /// top_tags 只有名字且数量有限，侧栏标签区需要带 count 的完整数据。
  Future<List<SiteTagGroup>> getSiteTagGroups() async {
    try {
      final response = await _dio.get('/tags.json');
      final data = response.data as Map<String, dynamic>;

      final seen = <String>{};
      List<TagInfo> parse(List? list) {
        if (list == null) return const [];
        final tags = <TagInfo>[];
        for (final item in list) {
          if (item is! Map<String, dynamic>) continue;
          final info = TagInfo.fromJson(item);
          if (info.name.isNotEmpty && seen.add(info.name)) tags.add(info);
        }
        tags.sort((a, b) => b.count.compareTo(a.count));
        return tags;
      }

      final groups = <SiteTagGroup>[];
      final rawGroups =
          (data['extras'] as Map<String, dynamic>?)?['tag_groups'] as List?;
      if (rawGroups != null) {
        for (final group in rawGroups) {
          if (group is! Map<String, dynamic>) continue;
          final tags = parse(group['tags'] as List?);
          if (tags.isNotEmpty) {
            groups.add(
              SiteTagGroup(name: group['name'] as String?, tags: tags),
            );
          }
        }
      }
      final ungrouped = parse(data['tags'] as List?);
      if (ungrouped.isNotEmpty) {
        groups.add(SiteTagGroup(name: null, tags: ungrouped));
      }
      return groups;
    } catch (e) {
      debugPrint('[DiscourseService] getSiteTagGroups failed: $e');
      return [];
    }
  }

  /// 检查站点是否支持标签功能
  Future<bool> canTagTopics() async {
    final preloaded = PreloadedDataService();
    final canTag = await preloaded.canTagTopics();
    if (canTag != null) {
      return canTag;
    }

    try {
      final response = await _dio.get('/site.json');
      final data = response.data as Map<String, dynamic>;
      return data['can_tag_topics'] as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 获取话题标题最小长度
  Future<int> getMinTopicTitleLength() async {
    return PreloadedDataService().getMinTopicTitleLength();
  }

  /// 获取私信标题最小长度
  Future<int> getMinPmTitleLength() async {
    return PreloadedDataService().getMinPmTitleLength();
  }

  /// 获取回复内容最小长度
  Future<int> getMinPostLength() async {
    return PreloadedDataService().getMinPostLength();
  }

  /// 获取首贴内容最小长度
  Future<int> getMinFirstPostLength() async {
    return PreloadedDataService().getMinFirstPostLength();
  }

  /// 获取私信内容最小长度
  Future<int> getMinPmPostLength() async {
    return PreloadedDataService().getMinPmPostLength();
  }

  /// 设置分类通知级别
  Future<void> setCategoryNotificationLevel(int categoryId, int level) async {
    await _dio.post(
      '/category/$categoryId/notifications',
      data: {'notification_level': level},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
  }

  /// 获取当前用户对标签的通知级别。
  Future<TopicNotificationLevel> getTagNotificationLevel(String tag) async {
    final encodedTag = Uri.encodeComponent(tag);
    final response = await _dio.get('/tags/$encodedTag/notifications');
    final data = response.data;
    if (data is Map) {
      final raw = data['tag_notification'];
      if (raw is Map) {
        return TopicNotificationLevel.fromValue(
          (raw['notification_level'] as num?)?.toInt(),
        );
      }
    }
    return TopicNotificationLevel.regular;
  }

  /// 设置标签通知级别，对齐 Discourse TagsController 的嵌套参数。
  Future<void> setTagNotificationLevel(
    String tag,
    TopicNotificationLevel level,
  ) async {
    final encodedTag = Uri.encodeComponent(tag);
    try {
      await _dio.put(
        '/tags/$encodedTag/notifications',
        data: {
          'tag_notification': {'notification_level': level.value},
        },
        options: Options(contentType: Headers.jsonContentType),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 获取首页书签 tab
  Future<TopicListResponse> getBookmarks({int page = 0}) async {
    final response = await _dio.get(
      '/bookmarks.json',
      queryParameters: page > 0 ? {'page': page} : null,
    );
    return TopicListResponse.fromJson(response.data);
  }
}
