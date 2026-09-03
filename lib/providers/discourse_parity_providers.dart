import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/community_user_preferences.dart';
import '../models/topic.dart';
import '../models/user_action.dart';
import 'core_providers.dart';
import 'user_content_providers.dart';

/// Unread private messages use the same pagination state machine as the
/// existing Inbox/Sent/Archive views. Keeping this as a notifier (rather than
/// a one-shot FutureProvider) lets the current PM page reuse refresh/load-more,
/// bulk selection and navigation behavior unchanged.
class PmUnreadNotifier extends PrivateMessagesNotifier {
  @override
  Future<TopicListResponse> fetch(int page) =>
      ref.read(discourseServiceProvider).getPrivateMessagesUnread(page: page);
}

final pmUnreadProvider =
    AsyncNotifierProvider.autoDispose<PmUnreadNotifier, List<Topic>>(
      () => PmUnreadNotifier(),
    );

/// New private messages intentionally share the exact same pagination state
/// machine as Inbox/Unread/Sent/Archive.
class PmNewNotifier extends PrivateMessagesNotifier {
  @override
  Future<TopicListResponse> fetch(int page) =>
      ref.read(discourseServiceProvider).getPrivateMessagesNew(page: page);
}

final pmNewProvider =
    AsyncNotifierProvider.autoDispose<PmNewNotifier, List<Topic>>(
      () => PmNewNotifier(),
    );

/// Extra private-message mailboxes exposed by current Discourse but not covered
/// by the original Inbox/Sent/Archive page model.
enum ParityPmMailbox { unread, newMessages, warnings }

class ParityPmPageQuery {
  const ParityPmPageQuery(this.mailbox, {this.page = 0});

  final ParityPmMailbox mailbox;
  final int page;

  @override
  bool operator ==(Object other) =>
      other is ParityPmPageQuery &&
      other.mailbox == mailbox &&
      other.page == page;

  @override
  int get hashCode => Object.hash(mailbox, page);
}

final parityPmPageProvider = FutureProvider.autoDispose
    .family<TopicListResponse, ParityPmPageQuery>((ref, query) {
      final service = ref.read(discourseServiceProvider);
      return switch (query.mailbox) {
        ParityPmMailbox.unread =>
          service.getPrivateMessagesUnread(page: query.page),
        ParityPmMailbox.newMessages =>
          service.getPrivateMessagesNew(page: query.page),
        ParityPmMailbox.warnings =>
          service.getPrivateMessagesWarnings(page: query.page),
      };
    });

/// Whether the server exposes the warning mailbox to this account. Do not
/// infer this from moderator/admin flags: an explicit successful server
/// response is the capability signal.
final pmWarningsAvailableProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    await ref.read(discourseServiceProvider).getPrivateMessagesWarnings();
    return true;
  } on DioException catch (error) {
    final status = error.response?.statusCode;
    if (status == 403 || status == 404) return false;
    rethrow;
  }
});

class PmTagQuery {
  const PmTagQuery({required this.tagName, this.page = 0});

  final String tagName;
  final int page;

  @override
  bool operator ==(Object other) =>
      other is PmTagQuery && other.tagName == tagName && other.page == page;

  @override
  int get hashCode => Object.hash(tagName, page);
}

/// PM-tag results always come from Discourse's permission-checked server route;
/// this provider never fetches the entire mailbox to filter client-side.
final pmTagPageProvider = FutureProvider.autoDispose
    .family<TopicListResponse, PmTagQuery>((ref, query) {
      return ref
          .read(discourseServiceProvider)
          .getPrivateMessagesByTag(query.tagName, page: query.page);
    });

class GroupPrivateMessageQuery {
  const GroupPrivateMessageQuery({
    required this.groupName,
    this.page = 0,
    this.unreadOnly = false,
    this.newOnly = false,
    this.archived = false,
  });

  final String groupName;
  final int page;
  final bool unreadOnly;
  final bool newOnly;
  final bool archived;

  @override
  bool operator ==(Object other) =>
      other is GroupPrivateMessageQuery &&
      other.groupName == groupName &&
      other.page == page &&
      other.unreadOnly == unreadOnly &&
      other.newOnly == newOnly &&
      other.archived == archived;

  @override
  int get hashCode =>
      Object.hash(groupName, page, unreadOnly, newOnly, archived);
}

final groupPrivateMessagesProvider = FutureProvider.autoDispose
    .family<TopicListResponse, GroupPrivateMessageQuery>((ref, query) {
      return ref
          .read(discourseServiceProvider)
          .getGroupPrivateMessages(
            query.groupName,
            page: query.page,
            unreadOnly: query.unreadOnly,
            newOnly: query.newOnly,
            archived: query.archived,
          );
    });

class GroupTopicsQuery {
  const GroupTopicsQuery({required this.groupName, this.page = 0});

  final String groupName;
  final int page;

  @override
  bool operator ==(Object other) =>
      other is GroupTopicsQuery &&
      other.groupName == groupName &&
      other.page == page;

  @override
  int get hashCode => Object.hash(groupName, page);
}

final groupTopicsProvider = FutureProvider.autoDispose
    .family<TopicListResponse, GroupTopicsQuery>((ref, query) {
      return ref
          .read(discourseServiceProvider)
          .getGroupTopics(query.groupName, page: query.page);
    });

enum GroupActivityKind { posts, mentions }

class GroupActivityQuery {
  const GroupActivityQuery({
    required this.groupName,
    required this.kind,
    this.beforePostId,
  });

  final String groupName;
  final GroupActivityKind kind;
  final int? beforePostId;

  @override
  bool operator ==(Object other) =>
      other is GroupActivityQuery &&
      other.groupName == groupName &&
      other.kind == kind &&
      other.beforePostId == beforePostId;

  @override
  int get hashCode => Object.hash(groupName, kind, beforePostId);
}

/// Keep the complete serializer payload so plugin fields added by a site are not
/// accidentally discarded before the group activity UI gets a chance to adapt.
final groupActivityProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, GroupActivityQuery>((ref, query) {
      final service = ref.read(discourseServiceProvider);
      return switch (query.kind) {
        GroupActivityKind.posts => service.getGroupActivityPosts(
          query.groupName,
          beforePostId: query.beforePostId,
        ),
        GroupActivityKind.mentions => service.getGroupActivityMentions(
          query.groupName,
          beforePostId: query.beforePostId,
        ),
      };
    });

enum ParityUserActivityKind { replies, likesGiven }

class ParityUserActivityQuery {
  const ParityUserActivityQuery({
    required this.username,
    required this.kind,
    this.offset = 0,
  });

  final String username;
  final ParityUserActivityKind kind;
  final int offset;

  @override
  bool operator ==(Object other) =>
      other is ParityUserActivityQuery &&
      other.username == username &&
      other.kind == kind &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(username, kind, offset);
}

final parityUserActivityProvider = FutureProvider.autoDispose
    .family<UserActionResponse, ParityUserActivityQuery>((ref, query) {
      final filter = switch (query.kind) {
        ParityUserActivityKind.replies => UserActionType.reply.toString(),
        ParityUserActivityKind.likesGiven => UserActionType.like.toString(),
      };
      return ref.read(discourseServiceProvider).getUserActions(
            query.username,
            filter: filter,
            offset: query.offset,
          );
    });

/// The bookmark cache already stores Discourse reminder metadata. Expose the
/// upstream "bookmarks with reminders" view as a derived provider instead of
/// creating a second network/cache implementation.
final bookmarksWithRemindersProvider =
    Provider.autoDispose<AsyncValue<List<Topic>>>((ref) {
      return ref.watch(bookmarksProvider).whenData(
            (topics) => topics
                .where((topic) => topic.bookmarkReminderAt != null)
                .toList(growable: false),
          );
    });

/// Native Discourse account preferences. This intentionally bypasses the app's
/// local preference registry: values here are server-side and synchronize with
/// the web UI and other clients.
final communityUserPreferencesProvider =
    FutureProvider.autoDispose<CommunityUserPreferences>((ref) async {
      final raw = await ref
          .read(discourseServiceProvider)
          .getCommunityUserPreferencesRaw();
      return CommunityUserPreferences.fromUserJson(raw);
    });
