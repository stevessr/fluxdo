/// 话题链接解析结果
class TopicLinkInfo {
  final int topicId;
  final String? slug;
  final int? postNumber;

  const TopicLinkInfo({required this.topicId, this.slug, this.postNumber});
}

/// 用户链接解析结果
class UserLinkInfo {
  final String username;

  const UserLinkInfo({required this.username});
}

/// 徽章链接解析结果：/badges/:id/:slug
class BadgeLinkInfo {
  final int badgeId;
  final String? slug;

  const BadgeLinkInfo({required this.badgeId, this.slug});
}

/// discourse-cakeday 链接解析结果。
class CakedayLinkInfo {
  final bool birthdays;
  final String? filter;

  const CakedayLinkInfo({required this.birthdays, this.filter});
}

/// 分类链接解析结果。
class CategoryLinkInfo {
  const CategoryLinkInfo({required this.categoryId});

  final int categoryId;
}

/// 聊天链接解析结果(/chat/c/:slug/:channelId[/t/:threadId][/:messageId])
class ChatLinkInfo {
  final int channelId;
  final int? threadId;
  final int? messageId;

  const ChatLinkInfo({required this.channelId, this.threadId, this.messageId});
}

/// 标题中可自动解析的绝对 URL。
class TitleUrlInfo {
  final String url;
  final Uri uri;

  const TitleUrlInfo({required this.url, required this.uri});
}

class DiscourseUrlParser {
  DiscourseUrlParser._();

  /// 纯数字 ID 格式：/t/12345 或 /t/12345/1
  /// 必须优先匹配，否则 /t/12345/1 中的 12345 会被误当作 slug
  static final _topicIdOnlyRegex = RegExp(
    r'/t/(\d+)(?:/(\d+))?(?:[/?#]|$)',
    caseSensitive: false,
  );

  /// 带 slug 格式：/t/topic-slug/12345 或 /t/topic-slug/12345/1
  static final _topicWithSlugRegex = RegExp(
    r'/t/([^/]+)/(\d+)(?:/(\d+))?',
    caseSensitive: false,
  );

  /// 仅含 slug 格式：/t/some-slug（slug 不能以数字开头）
  static final _topicSlugOnlyRegex = RegExp(
    r'/t/([^/\d][^/?#]*)$',
    caseSensitive: false,
  );

  /// 用户链接格式：/u/username
  static final _userRegex = RegExp(r'/u/([^/?#]+)', caseSensitive: false);

  /// 徽章链接格式：/badges/128/-、/badges/128/devotee、/badges/128
  static final _badgeRegex = RegExp(
    r'/badges/(\d+)(?:/([^/?#]+))?(?:[/?#]|$)',
    caseSensitive: false,
  );

  /// discourse-cakeday：/cakeday/birthdays[/today]、anniversaries 同理。
  static final _cakedayRegex = RegExp(
    r'/cakeday/(birthdays|anniversaries)(?:/(today|tomorrow|upcoming))?(?:[/?#]|$)',
    caseSensitive: false,
  );

  static final _categoryRegex = RegExp(
    r'/c/(?:[^/?#]+/)?(\d+)(?:[/?#]|$)',
    caseSensitive: false,
  );

  static final _tagRegex = RegExp(r'/tag/([^/?#]+)', caseSensitive: false);

  /// 聊天链接:官方 chat_message.url 口径
  /// - `/chat/c/:slug/:channelId/t/:threadId/:messageId?`(thread 内消息)
  /// - `/chat/c/:slug/:channelId/:messageId?`(频道消息;slug 常为 "-")
  static final _chatThreadRegex = RegExp(
    r'/chat/c/[^/?#]+/(\d+)/t/(\d+)(?:/(\d+))?(?:[/?#]|$)',
    caseSensitive: false,
  );
  static final _chatChannelRegex = RegExp(
    r'/chat/c/[^/?#]+/(\d+)(?:/(\d+))?(?:[/?#]|$)',
    caseSensitive: false,
  );

  /// 解析话题链接，返回 [TopicLinkInfo] 或 null
  ///
  /// 支持格式：
  /// - `/t/12345` → topicId=12345
  /// - `/t/12345/1` → topicId=12345, postNumber=1
  /// - `/t/topic-slug/12345` → topicId=12345, slug=topic-slug
  /// - `/t/topic-slug/12345/1` → topicId=12345, slug=topic-slug, postNumber=1
  static TopicLinkInfo? parseTopic(String url) {
    final idOnlyMatch = _topicIdOnlyRegex.firstMatch(url);
    if (idOnlyMatch != null) {
      return TopicLinkInfo(
        topicId: int.parse(idOnlyMatch.group(1)!),
        postNumber: int.tryParse(idOnlyMatch.group(2) ?? ''),
      );
    }

    final withSlugMatch = _topicWithSlugRegex.firstMatch(url);
    if (withSlugMatch != null) {
      final slugStr = withSlugMatch.group(1)!;
      return TopicLinkInfo(
        topicId: int.parse(withSlugMatch.group(2)!),
        slug: slugStr != 'topic' ? slugStr : null,
        postNumber: int.tryParse(withSlugMatch.group(3) ?? ''),
      );
    }

    return null;
  }

  /// 解析仅含 slug 的话题链接（/t/some-slug），返回 slug 或 null
  static String? parseTopicSlug(String url) {
    final match = _topicSlugOnlyRegex.firstMatch(url);
    return match?.group(1);
  }

  /// 解析用户链接，返回 [UserLinkInfo] 或 null
  static UserLinkInfo? parseUser(String url) {
    final match = _userRegex.firstMatch(url);
    if (match != null) {
      return UserLinkInfo(username: match.group(1)!);
    }
    return null;
  }

  /// 解析徽章详情链接。slug 为 `-` 时按 Discourse 占位符处理为 null。
  static BadgeLinkInfo? parseBadge(String url) {
    final match = _badgeRegex.firstMatch(url);
    if (match == null) return null;
    final id = int.tryParse(match.group(1) ?? '');
    if (id == null) return null;
    final rawSlug = match.group(2);
    return BadgeLinkInfo(
      badgeId: id,
      slug: rawSlug == null || rawSlug == '-' ? null : Uri.decodeComponent(rawSlug),
    );
  }

  /// 解析生日/周年纪念日页面链接。
  static CakedayLinkInfo? parseCakeday(String url) {
    final match = _cakedayRegex.firstMatch(url);
    if (match == null) return null;
    return CakedayLinkInfo(
      birthdays: match.group(1)!.toLowerCase() == 'birthdays',
      filter: match.group(2)?.toLowerCase(),
    );
  }

  /// discourse-events 的原生近期活动页面。
  static bool isUpcomingEvents(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final path = uri.path.toLowerCase();
    return path == '/upcoming-events' || path.startsWith('/upcoming-events/');
  }

  static CategoryLinkInfo? parseCategory(String url) {
    final match = _categoryRegex.firstMatch(url);
    final id = int.tryParse(match?.group(1) ?? '');
    return id == null ? null : CategoryLinkInfo(categoryId: id);
  }

  static String? parseTag(String url) {
    final match = _tagRegex.firstMatch(url);
    final encoded = match?.group(1);
    return encoded == null ? null : Uri.decodeComponent(encoded);
  }

  /// 解析标题中的单独 HTTP(S) URL。
  static TitleUrlInfo? parseTitleUrl(String value) {
    final url = value.trim();
    if (url.isEmpty || RegExp(r'\s').hasMatch(url)) return null;

    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;

    return TitleUrlInfo(url: url, uri: uri);
  }

  /// 解析聊天链接,返回 [ChatLinkInfo] 或 null(thread 形态优先匹配,
  /// 否则 /t/:threadId 会被当成 messageId)
  static ChatLinkInfo? parseChat(String url) {
    final threadMatch = _chatThreadRegex.firstMatch(url);
    if (threadMatch != null) {
      return ChatLinkInfo(
        channelId: int.parse(threadMatch.group(1)!),
        threadId: int.parse(threadMatch.group(2)!),
        messageId: int.tryParse(threadMatch.group(3) ?? ''),
      );
    }
    final channelMatch = _chatChannelRegex.firstMatch(url);
    if (channelMatch != null) {
      return ChatLinkInfo(
        channelId: int.parse(channelMatch.group(1)!),
        messageId: int.tryParse(channelMatch.group(2) ?? ''),
      );
    }
    return null;
  }

  static bool isHomepage(String url) {
    final resolved = Uri.tryParse(url);
    if (resolved == null) return false;
    return (resolved.path.isEmpty || resolved.path == '/') &&
        resolved.query.isEmpty &&
        resolved.fragment.isEmpty;
  }

  /// 是否是用户链接（用于快速判断）
  static bool isUserLink(String url) {
    return _userRegex.hasMatch(url);
  }
}
