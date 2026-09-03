import '../utils/time_utils.dart';
import '../utils/url_helper.dart';

/// Discourse 群组。
///
/// 权限字段直接使用 GroupSerializer 返回值，不在客户端按 admin/moderator
/// 身份猜测。网页版 `currentUser.canManageGroup(group)` 的判断就是
/// `can_admin_group || is_group_owner`，成员管理页还会排除 automatic 群组。
class DiscourseGroup {
  const DiscourseGroup({
    required this.id,
    required this.name,
    this.displayName,
    this.fullName,
    this.userCount,
    this.automatic = false,
    this.visible = true,
    this.canSeeMembers = true,
    this.isGroupUser = false,
    this.isGroupOwner = false,
    this.canAdminGroup = false,
    this.publicAdmission = false,
    this.publicExit = false,
    this.allowMembershipRequests = false,
    this.bioRaw,
    this.bioCooked,
    this.flairUrl,
    this.flairBackgroundColor,
    this.flairColor,
    this.title,
  });

  final int id;
  final String name;
  final String? displayName;
  final String? fullName;
  final int? userCount;
  final bool automatic;
  final bool visible;
  final bool canSeeMembers;
  final bool isGroupUser;
  final bool isGroupOwner;
  final bool canAdminGroup;
  final bool publicAdmission;
  final bool publicExit;
  final bool allowMembershipRequests;
  final String? bioRaw;
  final String? bioCooked;
  final String? flairUrl;
  final String? flairBackgroundColor;
  final String? flairColor;
  final String? title;

  String get label {
    final full = fullName?.trim();
    if (full != null && full.isNotEmpty) return full;
    final display = displayName?.trim();
    if (display != null && display.isNotEmpty) return display;
    return name;
  }

  /// 与 Discourse 原版群组成员页一致：自动群组不可手工加人；普通群组只有
  /// group owner 或服务端明确下发 can_admin_group 的当前用户能管理。
  bool get canManageMembers =>
      !automatic && (canAdminGroup || isGroupOwner);

  /// 对齐 Discourse `group-membership-button`：公开准入且当前不是成员时可加入。
  bool get canJoin => publicAdmission && !isGroupUser;

  /// 对齐 Discourse `group-membership-button`：允许公开退出且当前是成员时可退出。
  bool get canLeave => publicExit && isGroupUser;

  DiscourseGroup copyWith({
    int? userCount,
    bool? isGroupUser,
    bool? isGroupOwner,
  }) => DiscourseGroup(
    id: id,
    name: name,
    displayName: displayName,
    fullName: fullName,
    userCount: userCount ?? this.userCount,
    automatic: automatic,
    visible: visible,
    canSeeMembers: canSeeMembers,
    isGroupUser: isGroupUser ?? this.isGroupUser,
    isGroupOwner: isGroupOwner ?? this.isGroupOwner,
    canAdminGroup: canAdminGroup,
    publicAdmission: publicAdmission,
    publicExit: publicExit,
    allowMembershipRequests: allowMembershipRequests,
    bioRaw: bioRaw,
    bioCooked: bioCooked,
    flairUrl: flairUrl,
    flairBackgroundColor: flairBackgroundColor,
    flairColor: flairColor,
    title: title,
  );

  factory DiscourseGroup.fromJson(Map<String, dynamic> json) {
    return DiscourseGroup(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      displayName: json['display_name']?.toString(),
      fullName: json['full_name']?.toString(),
      userCount: (json['user_count'] as num?)?.toInt(),
      automatic: json['automatic'] as bool? ?? false,
      visible: json['visible'] as bool? ?? true,
      canSeeMembers: json['can_see_members'] as bool? ?? true,
      isGroupUser: json['is_group_user'] as bool? ?? false,
      isGroupOwner: json['is_group_owner'] as bool? ?? false,
      canAdminGroup: json['can_admin_group'] as bool? ?? false,
      publicAdmission: json['public_admission'] as bool? ?? false,
      publicExit: json['public_exit'] as bool? ?? false,
      allowMembershipRequests:
          json['allow_membership_requests'] as bool? ?? false,
      bioRaw: json['bio_raw']?.toString(),
      bioCooked: json['bio_cooked']?.toString(),
      flairUrl: json['flair_url']?.toString(),
      flairBackgroundColor: json['flair_bg_color']?.toString(),
      flairColor: json['flair_color']?.toString(),
      title: json['title']?.toString(),
    );
  }
}

class GroupDirectoryResult {
  const GroupDirectoryResult({
    required this.groups,
    required this.total,
    this.loadMorePath,
  });

  final List<DiscourseGroup> groups;
  final int total;
  final String? loadMorePath;

  bool get hasMore => loadMorePath != null && loadMorePath!.isNotEmpty;

  factory GroupDirectoryResult.fromJson(Map<String, dynamic> json) {
    final rawGroups = json['groups'] as List? ?? const [];
    return GroupDirectoryResult(
      groups: rawGroups
          .whereType<Map>()
          .map((raw) => DiscourseGroup.fromJson(Map<String, dynamic>.from(raw)))
          .where((group) => group.name.isNotEmpty)
          .toList(growable: false),
      total: (json['total_rows_groups'] as num?)?.toInt() ?? rawGroups.length,
      loadMorePath: json['load_more_groups']?.toString(),
    );
  }
}

class GroupMember {
  const GroupMember({
    required this.id,
    required this.username,
    this.name,
    this.avatarTemplate,
    this.lastSeenAt,
    this.primaryGroupName,
    this.owner = false,
  });

  final int id;
  final String username;
  final String? name;
  final String? avatarTemplate;
  final DateTime? lastSeenAt;
  final String? primaryGroupName;
  final bool owner;

  String? get avatarUrl {
    final template = avatarTemplate;
    if (template == null || template.isEmpty) return null;
    return template.replaceAll('{size}', '96');
  }

  GroupMember copyWith({bool? owner}) => GroupMember(
    id: id,
    username: username,
    name: name,
    avatarTemplate: avatarTemplate,
    lastSeenAt: lastSeenAt,
    primaryGroupName: primaryGroupName,
    owner: owner ?? this.owner,
  );

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    final rawAvatar = json['avatar_template']?.toString();
    return GroupMember(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: json['username']?.toString() ?? '',
      name: json['name']?.toString(),
      avatarTemplate:
          rawAvatar == null ? null : UrlHelper.resolveUrlWithCdn(rawAvatar),
      lastSeenAt: TimeUtils.parseUtcTime(json['last_seen_at']?.toString()),
      primaryGroupName: json['primary_group_name']?.toString(),
    );
  }
}

class GroupMembersResult {
  const GroupMembersResult({
    required this.members,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<GroupMember> members;
  final int total;
  final int limit;
  final int offset;

  bool get hasMore => offset + members.length < total;
  int get nextOffset => offset + limit;

  factory GroupMembersResult.fromJson(Map<String, dynamic> json) {
    final ownerIds = <int>{};
    for (final raw in (json['owners'] as List? ?? const [])) {
      if (raw is Map) {
        final id = (raw['id'] as num?)?.toInt();
        if (id != null) ownerIds.add(id);
      }
    }

    final members = (json['members'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => GroupMember.fromJson(Map<String, dynamic>.from(raw)))
        .where((member) => member.username.isNotEmpty)
        .map((member) => member.copyWith(owner: ownerIds.contains(member.id)))
        .toList(growable: false);

    final meta = json['meta'] is Map
        ? Map<String, dynamic>.from(json['meta'] as Map)
        : const <String, dynamic>{};
    return GroupMembersResult(
      members: members,
      total: (meta['total'] as num?)?.toInt() ?? members.length,
      limit: (meta['limit'] as num?)?.toInt() ?? members.length,
      offset: (meta['offset'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A pending request to join a group. Upstream `GroupRequesterSerializer`
/// extends `BasicUserSerializer` with `reason` and `requested_at`.
class GroupRequester {
  const GroupRequester({
    required this.id,
    required this.username,
    this.name,
    this.avatarTemplate,
    this.reason,
    this.requestedAt,
  });

  final int id;
  final String username;
  final String? name;
  final String? avatarTemplate;
  final String? reason;
  final DateTime? requestedAt;

  String get displayName {
    final value = name?.trim();
    return value == null || value.isEmpty ? username : value;
  }

  String? get avatarUrl {
    final template = avatarTemplate;
    if (template == null || template.isEmpty) return null;
    return UrlHelper.resolveUrlWithCdn(template.replaceAll('{size}', '96'));
  }

  factory GroupRequester.fromJson(Map<String, dynamic> json) {
    return GroupRequester(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: json['username']?.toString() ?? '',
      name: json['name']?.toString(),
      avatarTemplate: json['avatar_template']?.toString(),
      reason: json['reason']?.toString(),
      requestedAt: TimeUtils.parseUtcTime(json['requested_at']?.toString()),
    );
  }
}

class GroupRequestersResult {
  const GroupRequestersResult({
    required this.requesters,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<GroupRequester> requesters;
  final int total;
  final int limit;
  final int offset;

  bool get hasMore => offset + requesters.length < total;
  int get nextOffset => offset + limit;

  factory GroupRequestersResult.fromJson(Map<String, dynamic> json) {
    final requesters = (json['members'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => GroupRequester.fromJson(Map<String, dynamic>.from(raw)))
        .where((requester) => requester.id > 0 && requester.username.isNotEmpty)
        .toList(growable: false);
    final meta = json['meta'] is Map
        ? Map<String, dynamic>.from(json['meta'] as Map)
        : const <String, dynamic>{};
    return GroupRequestersResult(
      requesters: requesters,
      total: (meta['total'] as num?)?.toInt() ?? requesters.length,
      limit: (meta['limit'] as num?)?.toInt() ?? requesters.length,
      offset: (meta['offset'] as num?)?.toInt() ?? 0,
    );
  }
}
