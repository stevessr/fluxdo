/// One visible Discourse group that can contribute account preference choices.
class CommunityPreferenceGroup {
  const CommunityPreferenceGroup({
    required this.id,
    required this.name,
    this.displayName,
    this.automatic = false,
    this.primaryGroup = false,
    this.title,
    this.flairUrl,
    this.flairBgColor,
    this.flairColor,
  });

  final int id;
  final String name;
  final String? displayName;
  final bool automatic;
  final bool primaryGroup;
  final String? title;
  final String? flairUrl;
  final String? flairBgColor;
  final String? flairColor;

  String get label =>
      displayName != null && displayName!.isNotEmpty ? displayName! : name;

  /// Mirrors Discourse User#filteredGroups: automatic groups are hidden except
  /// the moderators group, which remains eligible when the site allows users to
  /// choose a primary group.
  bool get selectableAsPrimaryGroup => !automatic || name == 'moderators';

  /// Discourse User#availableFlairs only includes visible groups that expose a
  /// flair URL.
  bool get providesFlair => flairUrl != null && flairUrl!.isNotEmpty;

  factory CommunityPreferenceGroup.fromJson(Map<dynamic, dynamic> json) {
    int readInt(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return CommunityPreferenceGroup(
      id: readInt(json['id']),
      name: json['name']?.toString() ?? '',
      displayName: json['display_name']?.toString(),
      automatic: json['automatic'] as bool? ?? false,
      primaryGroup: json['primary_group'] as bool? ?? false,
      title: json['title']?.toString(),
      flairUrl: json['flair_url']?.toString(),
      flairBgColor: json['flair_bg_color']?.toString(),
      flairColor: json['flair_color']?.toString(),
    );
  }
}

/// Editable server-side Discourse preferences for the current community account.
///
/// This deliberately lives outside the general [User] model: most fields only
/// exist for the profile/preferences surface and should not enlarge every user
/// card/topic payload in the app.
class CommunityUserPreferences {
  const CommunityUserPreferences({
    required this.username,
    this.name,
    this.title,
    this.primaryGroupId,
    this.flairGroupId,
    this.groups = const [],
    this.availableBadgeTitles = const [],
    this.userSelectedPrimaryGroups = false,
    this.bioRaw,
    this.location,
    this.website,
    this.locale,
    this.profileBackgroundUploadUrl,
    this.cardBackgroundUploadUrl,
    this.canEdit = false,
    this.canEditName = false,
    this.canChangeBio = false,
    this.canChangeLocation = false,
    this.canChangeWebsite = false,
    this.canUploadProfileHeader = false,
    this.canUploadUserCardBackground = false,
    this.timezone,
    this.emailDigests = false,
    this.mailingListMode = false,
    this.externalLinksInNewTab = false,
    this.enableQuoting = true,
    this.dynamicFavicon = false,
    this.automaticallyUnpinTopics = true,
    this.notifyOnLinkedPosts = true,
    this.includeTl0InDigests = false,
    this.allowPrivateMessages = true,
    this.hideProfile = false,
    this.hidePresence = false,
    this.skipNewUserTips = false,
    this.sidebarLinkToFilteredList = false,
    this.sidebarShowCountOfNewItems = false,
    this.watchedPrecedenceOverMuted = false,
    this.automaticallyTranslate = false,
    this.bookmarkAutoDeletePreference,
    this.emailLevel,
    this.emailMessagesLevel,
    this.likeNotificationFrequency,
    this.pushNotificationLevel,
    this.notificationLevelWhenReplying,
    this.userOptionRaw = const {},
    this.raw = const {},
  });

  final String username;
  final String? name;
  final String? title;
  final int? primaryGroupId;
  final int? flairGroupId;
  final List<CommunityPreferenceGroup> groups;
  final List<String> availableBadgeTitles;
  final bool userSelectedPrimaryGroups;
  final String? bioRaw;
  final String? location;
  final String? website;
  final String? locale;
  final String? profileBackgroundUploadUrl;
  final String? cardBackgroundUploadUrl;

  final bool canEdit;
  final bool canEditName;
  final bool canChangeBio;
  final bool canChangeLocation;
  final bool canChangeWebsite;
  final bool canUploadProfileHeader;
  final bool canUploadUserCardBackground;

  final String? timezone;
  final bool emailDigests;
  final bool mailingListMode;
  final bool externalLinksInNewTab;
  final bool enableQuoting;
  final bool dynamicFavicon;
  final bool automaticallyUnpinTopics;
  final bool notifyOnLinkedPosts;
  final bool includeTl0InDigests;
  final bool allowPrivateMessages;
  final bool hideProfile;
  final bool hidePresence;
  final bool skipNewUserTips;
  final bool sidebarLinkToFilteredList;
  final bool sidebarShowCountOfNewItems;
  final bool watchedPrecedenceOverMuted;
  final bool automaticallyTranslate;
  final int? bookmarkAutoDeletePreference;
  final int? emailLevel;
  final int? emailMessagesLevel;
  final int? likeNotificationFrequency;
  final int? pushNotificationLevel;
  final int? notificationLevelWhenReplying;

  List<String> get availableTitles {
    final result = <String>{};
    for (final group in groups) {
      final groupTitle = group.title;
      if (groupTitle != null && groupTitle.isNotEmpty) result.add(groupTitle);
    }
    result.addAll(availableBadgeTitles.where((value) => value.isNotEmpty));
    if (title != null && title!.isNotEmpty) result.add(title!);
    return List.unmodifiable(result);
  }

  List<CommunityPreferenceGroup> get availablePrimaryGroups {
    if (!userSelectedPrimaryGroups) return const [];
    return List.unmodifiable(
      groups.where((group) => group.selectableAsPrimaryGroup),
    );
  }

  List<CommunityPreferenceGroup> get availableFlairGroups => List.unmodifiable(
        groups.where((group) => group.providesFlair),
      );

  /// Preserve plugin/new-core options so diagnostics and later adapters do not
  /// lose information merely because this client has not exposed the field yet.
  final Map<String, dynamic> userOptionRaw;
  final Map<String, dynamic> raw;

  factory CommunityUserPreferences.fromUserJson(Map<String, dynamic> json) {
    final option = json['user_option'] is Map
        ? Map<String, dynamic>.from(json['user_option'] as Map)
        : const <String, dynamic>{};

    bool optionBool(String key, bool fallback) =>
        option[key] is bool ? option[key] as bool : fallback;
    int? optionInt(String key) => (option[key] as num?)?.toInt();
    int? rootInt(String key) {
      final value = json[key];
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    final groups = (json['groups'] as List?)
            ?.whereType<Map>()
            .map(CommunityPreferenceGroup.fromJson)
            .where((group) => group.id > 0 && group.name.isNotEmpty)
            .toList(growable: false) ??
        const <CommunityPreferenceGroup>[];
    final badgeTitles = (json['_fluxdo_available_badge_titles'] as List?)
            ?.map((value) => value?.toString() ?? '')
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(growable: false) ??
        const <String>[];

    return CommunityUserPreferences(
      username: json['username']?.toString() ?? '',
      name: json['name']?.toString(),
      title: json['title']?.toString(),
      primaryGroupId: rootInt('primary_group_id'),
      flairGroupId: rootInt('flair_group_id'),
      groups: List.unmodifiable(groups),
      availableBadgeTitles: List.unmodifiable(badgeTitles),
      userSelectedPrimaryGroups:
          json['_fluxdo_user_selected_primary_groups'] as bool? ?? false,
      bioRaw: json['bio_raw']?.toString(),
      location: json['location']?.toString(),
      website: json['website']?.toString(),
      locale: json['locale']?.toString(),
      profileBackgroundUploadUrl:
          json['profile_background_upload_url']?.toString(),
      cardBackgroundUploadUrl:
          json['card_background_upload_url']?.toString(),
      canEdit: json['can_edit'] as bool? ?? false,
      canEditName: json['can_edit_name'] as bool? ?? false,
      canChangeBio: json['can_change_bio'] as bool? ?? false,
      canChangeLocation: json['can_change_location'] as bool? ?? false,
      canChangeWebsite: json['can_change_website'] as bool? ?? false,
      canUploadProfileHeader:
          json['can_upload_profile_header'] as bool? ?? false,
      canUploadUserCardBackground:
          json['can_upload_user_card_background'] as bool? ?? false,
      // Current Discourse serializes timezone at the user root and its
      // frontend moves it into user_option after loading. Keep compatibility
      // with older/plugin serializers that may already nest it.
      timezone: json['timezone']?.toString() ?? option['timezone']?.toString(),
      emailDigests: optionBool('email_digests', false),
      mailingListMode: optionBool('mailing_list_mode', false),
      externalLinksInNewTab:
          optionBool('external_links_in_new_tab', false),
      enableQuoting: optionBool('enable_quoting', true),
      dynamicFavicon: optionBool('dynamic_favicon', false),
      automaticallyUnpinTopics:
          optionBool('automatically_unpin_topics', true),
      notifyOnLinkedPosts: optionBool('notify_on_linked_posts', true),
      includeTl0InDigests: optionBool('include_tl0_in_digests', false),
      allowPrivateMessages: optionBool('allow_private_messages', true),
      hideProfile: optionBool('hide_profile', false),
      hidePresence: optionBool('hide_presence', false),
      skipNewUserTips: optionBool('skip_new_user_tips', false),
      sidebarLinkToFilteredList:
          optionBool('sidebar_link_to_filtered_list', false),
      sidebarShowCountOfNewItems:
          optionBool('sidebar_show_count_of_new_items', false),
      watchedPrecedenceOverMuted:
          optionBool('watched_precedence_over_muted', false),
      automaticallyTranslate:
          optionBool('automatically_translate', false),
      bookmarkAutoDeletePreference:
          optionInt('bookmark_auto_delete_preference'),
      emailLevel: optionInt('email_level'),
      emailMessagesLevel: optionInt('email_messages_level'),
      likeNotificationFrequency: optionInt('like_notification_frequency'),
      pushNotificationLevel: optionInt('push_notification_level'),
      notificationLevelWhenReplying:
          optionInt('notification_level_when_replying'),
      userOptionRaw: Map.unmodifiable(option),
      raw: Map.unmodifiable(Map<String, dynamic>.from(json)),
    );
  }
}
