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

  Map<String, dynamic> _unwrapCommunityUserPayload(dynamic data) {
    if (data is! Map) {
      throw const FormatException('Invalid community user response');
    }
    final root = Map<String, dynamic>.from(data);
    final user = root['user'];
    if (user is Map) return Map<String, dynamic>.from(user);
    return root;
  }

  Future<List<String>> _getCommunityBadgeTitleChoices(
    String encodedUser,
  ) async {
    final siteSettings = await PreloadedDataService().getSiteSettings();
    if (siteSettings?['enable_badges'] != true) return const [];

    try {
      final response = await _dio.get('/user-badges/$encodedUser.json');
      if (response.data is! Map) return const [];
      final badges = (response.data as Map)['badges'];
      if (badges is! List) return const [];
      return badges
          .whereType<Map>()
          .where((badge) => badge['allow_title'] == true)
          .map((badge) => badge['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList(growable: false);
    } on DioException catch (error) {
      // Badge title choices are additive account metadata. A site that hides or
      // disables this endpoint should not make the rest of native preferences
      // unusable; unknown transport/auth failures still surface normally.
      final status = error.response?.statusCode;
      if (status == 403 || status == 404) return const [];
      rethrow;
    }
  }

  /// Fetch the current account with the full UserSerializer payload used by
  /// Discourse's preferences routes. Keep the response raw at the service
  /// boundary so newer core/plugin user_option fields are not silently lost.
  ///
  /// A small `_fluxdo_*` metadata namespace carries client capability facts
  /// that the official preferences route obtains from preload/site settings or
  /// follow-up requests. It is never sent back by the update method.
  Future<Map<String, dynamic>> getCommunityUserPreferencesRaw() async {
    final username = await _requireParityUsername();
    final encodedUser = Uri.encodeComponent(username);
    final response = await _dio.get('/u/$encodedUser.json');
    final user = _unwrapCommunityUserPayload(response.data);

    final siteSettings = await PreloadedDataService().getSiteSettings();
    user['_fluxdo_user_selected_primary_groups'] =
        siteSettings?['user_selected_primary_groups'] == true;
    user['_fluxdo_available_badge_titles'] =
        await _getCommunityBadgeTitleChoices(encodedUser);
    return user;
  }

  /// Update the safe subset of fields exposed by the native community settings
  /// page. Current Discourse's User model flattens user_option values into this
  /// same PUT request (`/u/:username.json`), so do not nest them under
  /// `user_option` here.
  ///
  /// The allowlist is deliberate: callers cannot accidentally turn this generic
  /// parity API into a password/email/security mutation surface.
  Future<Map<String, dynamic>> updateCommunityUserPreferences(
    Map<String, dynamic> changes,
  ) async {
    const allowedFields = <String>{
      'name',
      'title',
      'primary_group_id',
      'flair_group_id',
      'bio_raw',
      'location',
      'website',
      'locale',
      'timezone',
      'email_digests',
      'mailing_list_mode',
      'external_links_in_new_tab',
      'enable_quoting',
      'dynamic_favicon',
      'automatically_unpin_topics',
      'notify_on_linked_posts',
      'include_tl0_in_digests',
      'allow_private_messages',
      'hide_profile',
      'hide_presence',
      'skip_new_user_tips',
      'sidebar_link_to_filtered_list',
      'sidebar_show_count_of_new_items',
      'watched_precedence_over_muted',
      'automatically_translate',
      'bookmark_auto_delete_preference',
      'email_level',
      'email_messages_level',
      'like_notification_frequency',
      'push_notification_level',
      'notification_level_when_replying',
    };

    final data = <String, dynamic>{};
    for (final entry in changes.entries) {
      if (!allowedFields.contains(entry.key)) {
        throw ArgumentError.value(
          entry.key,
          'changes',
          'Unsupported community preference field',
        );
      }
      // Empty strings are meaningful for Discourse account selectors: upstream
      // UserUpdater uses blank? to clear primary/flair group (and blank title is
      // likewise a valid reset). Null still means "caller did not supply it".
      if (entry.value != null) data[entry.key] = entry.value;
    }
    if (data.isEmpty) return getCommunityUserPreferencesRaw();

    final username = await _requireParityUsername();
    final encodedUser = Uri.encodeComponent(username);
    try {
      await _dio.put(
        '/u/$encodedUser.json',
        data: data,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      // Re-read the canonical serializer instead of assuming the update
      // response contains every user_option/capability field.
      return getCommunityUserPreferencesRaw();
    } on DioException catch (e) {
      _throwApiError(e);
    }
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

  /// Warning mailbox. Visibility is deliberately decided by the server rather
  /// than by inferring staff/admin state in the client.
  Future<TopicListResponse> getPrivateMessagesWarnings({int page = 0}) async {
    final username = await _requireParityUsername();
    final response = await _dio.get(
      '/topics/private-messages-warnings/$username.json',
      queryParameters: page > 0 ? {'page': page} : null,
    );
    return TopicListResponse.fromJson(response.data);
  }

  /// Fetch one PM tag mailbox from the server. Do not emulate this by loading
  /// every private message and filtering locally: Discourse performs both the
  /// current-user and `can_tag_pms?` permission checks on this route.
  Future<TopicListResponse> getPrivateMessagesByTag(
    String tagName, {
    int page = 0,
  }) async {
    final username = await _requireParityUsername();
    final encodedUser = Uri.encodeComponent(username);
    final encodedTag = Uri.encodeComponent(tagName);
    final response = await _dio.get(
      '/u/$encodedUser/messages/tags/$encodedTag.json',
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

  /// Topics created by members of [groupName]. Current Discourse exposes this
  /// through ListController#group_topics under `/topics/groups/:group_name`;
  /// the server enforces `ensure_can_see_group_and_members!`.
  Future<TopicListResponse> getGroupTopics(
    String groupName, {
    int page = 0,
  }) async {
    final encodedGroup = Uri.encodeComponent(groupName);
    final response = await _dio.get(
      '/topics/groups/$encodedGroup.json',
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

  /// Raw group activity payload. Current Discourse uses `before_post_id` cursor
  /// pagination and returns at most 20 GroupPostSerializer entries. Preserve the
  /// complete payload so site/plugin fields can be adapted by the UI later.
  Future<Map<String, dynamic>> getGroupActivityPosts(
    String groupName, {
    int? beforePostId,
  }) async {
    final encodedGroup = Uri.encodeComponent(groupName);
    final response = await _dio.get(
      '/groups/$encodedGroup/posts.json',
      queryParameters: beforePostId == null
          ? null
          : {'before_post_id': beforePostId},
    );
    if (response.data is! Map) {
      throw const FormatException('Invalid group posts response');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getGroupActivityMentions(
    String groupName, {
    int? beforePostId,
  }) async {
    final encodedGroup = Uri.encodeComponent(groupName);
    final response = await _dio.get(
      '/groups/$encodedGroup/mentions.json',
      queryParameters: beforePostId == null
          ? null
          : {'before_post_id': beforePostId},
    );
    if (response.data is! Map) {
      throw const FormatException('Invalid group mentions response');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }
}
