/// discourse-boards 看板。
class DiscourseBoard {
  const DiscourseBoard({
    required this.id,
    required this.name,
    required this.unicodeName,
    required this.slug,
    required this.categoryIds,
    required this.tagIds,
    required this.tagNames,
    required this.anonymousCanRead,
    required this.requireConfirmation,
    required this.showTags,
    required this.cardStyle,
    required this.showTopicThumbnail,
    required this.archived,
    this.oldSlugUsed = false,
    this.createdBy,
    required this.canArchive,
    required this.canUnarchive,
    required this.canWrite,
    required this.canManage,
    required this.acl,
    required this.columns,
  });

  final int id;
  final String name;
  final String unicodeName;
  final String slug;
  final List<int> categoryIds;
  final List<int> tagIds;
  final List<String> tagNames;
  final bool anonymousCanRead;
  final bool requireConfirmation;
  final bool showTags;
  final String cardStyle;
  final bool showTopicThumbnail;
  final bool archived;
  final bool oldSlugUsed;
  final BoardCreator? createdBy;
  final bool canArchive;
  final bool canUnarchive;
  final bool canWrite;
  final bool canManage;
  final List<BoardAclEntry> acl;
  final List<BoardColumn> columns;

  factory DiscourseBoard.fromJson(Map<String, dynamic> json) {
    final canManage = json['can_manage'] as bool? ?? false;
    final columns =
        (json['columns'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(BoardColumn.fromJson)
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    return DiscourseBoard(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      unicodeName:
          json['unicode_name'] as String? ?? json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      categoryIds: _intList(json['category_ids']),
      tagIds: _intList(json['tag_ids']),
      tagNames: _stringList(json['tag_names']),
      anonymousCanRead: json['anonymous_can_read'] as bool? ?? false,
      requireConfirmation: json['require_confirmation'] as bool? ?? false,
      showTags: json['show_tags'] as bool? ?? true,
      cardStyle: json['card_style'] as String? ?? 'detailed',
      showTopicThumbnail: json['show_topic_thumbnail'] as bool? ?? false,
      archived: json['archived'] as bool? ?? false,
      oldSlugUsed: json['old_slug_used'] as bool? ?? false,
      createdBy: json['created_by'] is Map
          ? BoardCreator.fromJson(
              Map<String, dynamic>.from(json['created_by'] as Map),
            )
          : null,
      canArchive: json['can_archive'] as bool? ?? canManage,
      canUnarchive: json['can_unarchive'] as bool? ?? canManage,
      canWrite: json['can_write'] as bool? ?? false,
      canManage: canManage,
      acl: (json['acl'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => BoardAclEntry.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
      columns: columns,
    );
  }

  /// show 接口把完整 columns 放在顶层，board.columns 只适合作元信息。
  factory DiscourseBoard.fromDetailResponse(Map<String, dynamic> json) {
    final raw = json['board'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Boards 响应缺少 board');
    }
    final merged = Map<String, dynamic>.from(raw);
    if (json['columns'] is List<dynamic>) merged['columns'] = json['columns'];
    return DiscourseBoard.fromJson(merged);
  }

  String get displayName => unicodeName.trim().isNotEmpty ? unicodeName : name;
}

class BoardAclEntry {
  const BoardAclEntry({
    required this.type,
    required this.id,
    required this.permission,
    this.displayName,
  });

  final String type;
  final int id;
  final String permission;
  final String? displayName;

  factory BoardAclEntry.fromJson(Map<String, dynamic> json) {
    return BoardAclEntry(
      type: json['type']?.toString() ?? 'group',
      id: (json['id'] as num?)?.toInt() ?? 0,
      permission: json['permission']?.toString() ?? 'view',
      displayName: json['display_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'id': id,
    'permission': permission,
  };

  BoardAclEntry copyWith({String? permission}) => BoardAclEntry(
    type: type,
    id: id,
    permission: permission ?? this.permission,
    displayName: displayName,
  );
}

class BoardColumn {
  const BoardColumn({
    required this.id,
    required this.title,
    required this.unicodeTitle,
    required this.position,
    required this.defaultSort,
    this.icon,
    this.tagId,
    this.tagName,
    this.moveToCategoryId,
    this.moveToAssigned,
    required this.moveToStatus,
    required this.color,
    required this.cards,
  });

  final int id;
  final String title;
  final String unicodeTitle;
  final int position;
  final String defaultSort;
  final String? icon;
  final int? tagId;
  final String? tagName;
  final int? moveToCategoryId;
  final String? moveToAssigned;
  final String moveToStatus;
  final String color;
  final List<BoardCard> cards;

  factory BoardColumn.fromJson(Map<String, dynamic> json) {
    final cards =
        (json['cards'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(BoardCard.fromJson)
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    return BoardColumn(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      unicodeTitle:
          json['unicode_title'] as String? ?? json['title'] as String? ?? '',
      position: (json['position'] as num?)?.toInt() ?? 0,
      defaultSort: json['default_sort'] as String? ?? 'priority',
      icon: json['icon'] as String?,
      tagId: (json['tag_id'] as num?)?.toInt(),
      tagName: json['tag_name'] as String?,
      moveToCategoryId: (json['move_to_category_id'] as num?)?.toInt(),
      moveToAssigned: json['move_to_assigned'] as String?,
      moveToStatus: json['move_to_status'] as String? ?? '',
      color: json['color'] as String? ?? '',
      cards: cards,
    );
  }

  String get displayTitle =>
      unicodeTitle.trim().isNotEmpty ? unicodeTitle : title;

  /// Boards 没有独立 solved 布尔值。优先看动作状态，再兼容常见完成列标题。
  /// 这里只用于隐藏“指定用户”入口，不改变任何服务端状态。
  bool get isResolvedLike {
    final status = moveToStatus.trim().toLowerCase();
    if (const {
      'closed',
      'solved',
      'resolved',
      'done',
      'completed',
    }.contains(status)) {
      return true;
    }
    final normalized = displayTitle.trim().toLowerCase().replaceAll(' ', '');
    return normalized.contains('已解决') ||
        normalized.contains('已完成') ||
        normalized == '完成' ||
        normalized == 'done' ||
        normalized.contains('resolved') ||
        normalized.contains('completed');
  }
}

class BoardCard {
  const BoardCard({
    required this.id,
    required this.boardId,
    required this.columnId,
    required this.cardType,
    required this.position,
    this.title,
    this.unicodeTitle,
    this.notes,
    this.inlineOneboxData,
    this.tagIds = const [],
    required this.tags,
    this.topicId,
    this.createdAt,
    this.updatedAt,
    this.columnChangedAt,
    this.recencyAt,
    this.createdBy,
    this.assignedTo,
    this.topic,
  });

  final int id;
  final int boardId;
  final int columnId;
  final String cardType;
  final double position;
  final String? title;
  final String? unicodeTitle;
  final String? notes;
  final Map<String, dynamic>? inlineOneboxData;
  final List<int> tagIds;
  final List<BoardTag> tags;
  final int? topicId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? columnChangedAt;
  final DateTime? recencyAt;
  final BoardCreator? createdBy;
  final BoardAssignee? assignedTo;
  final BoardTopic? topic;

  factory BoardCard.fromJson(Map<String, dynamic> json) {
    return BoardCard(
      id: (json['id'] as num?)?.toInt() ?? 0,
      boardId: (json['board_id'] as num?)?.toInt() ?? 0,
      columnId: (json['column_id'] as num?)?.toInt() ?? 0,
      cardType: json['card_type'] as String? ?? 'floater',
      position: (json['position'] as num?)?.toDouble() ?? 0,
      title: json['title'] as String?,
      unicodeTitle: json['unicode_title'] as String?,
      notes: json['notes'] as String?,
      inlineOneboxData: json['inline_onebox_data'] is Map
          ? Map<String, dynamic>.from(json['inline_onebox_data'] as Map)
          : null,
      tagIds: _intList(json['tag_ids']),
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map(BoardTag.fromJson)
          .toList(),
      topicId: (json['topic_id'] as num?)?.toInt(),
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
      columnChangedAt: _parseDateTime(json['column_changed_at']),
      recencyAt: _parseDateTime(json['recency_at']),
      createdBy: json['created_by'] is Map<String, dynamic>
          ? BoardCreator.fromJson(json['created_by'] as Map<String, dynamic>)
          : null,
      assignedTo: json['assigned_to'] is Map<String, dynamic>
          ? BoardAssignee.fromJson(json['assigned_to'] as Map<String, dynamic>)
          : null,
      topic: json['topic'] is Map<String, dynamic>
          ? BoardTopic.fromJson(json['topic'] as Map<String, dynamic>)
          : null,
    );
  }

  bool get isTopic => cardType == 'topic' && topic != null && topicId != null;

  String get displayTitle {
    final topicTitle = topic?.displayTitle.trim();
    if (topicTitle != null && topicTitle.isNotEmpty) return topicTitle;
    final unicode = unicodeTitle?.trim();
    if (unicode != null && unicode.isNotEmpty) return unicode;
    return title?.trim() ?? '';
  }

  List<BoardTag> get displayTags => isTopic ? topic!.tags : tags;

  DateTime? get activityAt =>
      recencyAt ?? topic?.bumpedAt ?? updatedAt ?? createdAt;

  List<BoardAssignee> get assignedUsers {
    final topicUsers = topic?.assignedUsers ?? const <BoardAssignee>[];
    if (topicUsers.isNotEmpty) return topicUsers;
    final direct = assignedTo;
    return direct != null && direct.isUser ? [direct] : const [];
  }

  String? get assignedGroupName {
    final topicGroup = topic?.assignedGroupName;
    if (topicGroup != null && topicGroup.isNotEmpty) return topicGroup;
    final direct = assignedTo;
    return direct != null && direct.isGroup ? direct.name : null;
  }
}

class BoardTopic {
  const BoardTopic({
    required this.id,
    required this.title,
    required this.unicodeTitle,
    required this.slug,
    required this.categoryId,
    required this.tags,
    this.bumpedAt,
    required this.closed,
    this.imageUrl,
    required this.postsCount,
    required this.highestPostNumber,
    this.lastReadPostNumber,
    this.lastPosterUsername,
    required this.assignedUsers,
    this.assignedGroupName,
  });

  final int id;
  final String title;
  final String unicodeTitle;
  final String slug;
  final int categoryId;
  final List<BoardTag> tags;
  final DateTime? bumpedAt;
  final bool closed;
  final String? imageUrl;
  final int postsCount;
  final int highestPostNumber;
  final int? lastReadPostNumber;
  final String? lastPosterUsername;
  final List<BoardAssignee> assignedUsers;
  final String? assignedGroupName;

  String get displayTitle =>
      unicodeTitle.trim().isNotEmpty ? unicodeTitle : title;

  factory BoardTopic.fromJson(Map<String, dynamic> json) {
    final users = (json['all_assigned_users'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BoardAssignee.userFromJson)
        .toList();
    if (users.isEmpty && json['assigned_to_user'] is Map<String, dynamic>) {
      users.add(
        BoardAssignee.userFromJson(
          json['assigned_to_user'] as Map<String, dynamic>,
        ),
      );
    }
    final group = json['assigned_to_group'];
    final lastPoster = json['last_poster'];

    return BoardTopic(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      unicodeTitle:
          json['unicode_title'] as String? ?? json['title'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      categoryId: (json['category_id'] as num?)?.toInt() ?? 0,
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map(BoardTag.fromJson)
          .toList(),
      bumpedAt: _parseDateTime(json['bumped_at']),
      closed: json['closed'] as bool? ?? false,
      imageUrl: json['image_url'] as String?,
      postsCount: (json['posts_count'] as num?)?.toInt() ?? 0,
      highestPostNumber: (json['highest_post_number'] as num?)?.toInt() ?? 0,
      lastReadPostNumber: (json['last_read_post_number'] as num?)?.toInt(),
      lastPosterUsername: lastPoster is Map<String, dynamic>
          ? lastPoster['username'] as String?
          : null,
      assignedUsers: users,
      assignedGroupName: group is Map<String, dynamic>
          ? group['name'] as String?
          : null,
    );
  }
}

class BoardTag {
  const BoardTag({this.id, required this.name, this.slug});

  final int? id;
  final String name;
  final String? slug;

  factory BoardTag.fromJson(dynamic json) {
    if (json is String) return BoardTag(name: json);
    if (json is Map<String, dynamic>) {
      return BoardTag(
        id: (json['id'] as num?)?.toInt(),
        name: json['name'] as String? ?? '',
        slug: json['slug'] as String?,
      );
    }
    return BoardTag(name: json.toString());
  }
}

class BoardCreator {
  const BoardCreator({required this.username, this.avatarTemplate});

  final String username;
  final String? avatarTemplate;

  factory BoardCreator.fromJson(Map<String, dynamic> json) => BoardCreator(
    username: json['username'] as String? ?? '',
    avatarTemplate: json['avatar_template'] as String?,
  );
}

class BoardAssignee {
  const BoardAssignee({
    required this.type,
    this.username,
    this.name,
    this.avatarTemplate,
  });

  final String type;
  final String? username;
  final String? name;
  final String? avatarTemplate;

  bool get isUser => type.toLowerCase() == 'user' || username != null;
  bool get isGroup => !isUser;
  String get displayName => username ?? name ?? '';

  factory BoardAssignee.fromJson(Map<String, dynamic> json) => BoardAssignee(
    type:
        json['type'] as String? ??
        (json['username'] != null ? 'User' : 'Group'),
    username: json['username'] as String?,
    name: json['name'] as String?,
    avatarTemplate: json['avatar_template'] as String?,
  );

  factory BoardAssignee.userFromJson(Map<String, dynamic> json) =>
      BoardAssignee(
        type: 'User',
        username: json['username'] as String?,
        name: json['name'] as String?,
        avatarTemplate: json['avatar_template'] as String?,
      );
}

DateTime? _parseDateTime(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}

List<int> _intList(dynamic value) {
  if (value is! List) return const [];
  return value.map((e) => (e as num?)?.toInt()).whereType<int>().toList();
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value.map((e) => e.toString()).toList();
}
