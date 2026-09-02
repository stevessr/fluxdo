import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/topic.dart';
import '../models/user_action.dart';
import 'core_providers.dart';
import 'user_content_providers.dart';

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

enum GroupActivityKind { posts, mentions }

class GroupActivityQuery {
  const GroupActivityQuery({
    required this.groupName,
    required this.kind,
    this.offset = 0,
  });

  final String groupName;
  final GroupActivityKind kind;
  final int offset;

  @override
  bool operator ==(Object other) =>
      other is GroupActivityQuery &&
      other.groupName == groupName &&
      other.kind == kind &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(groupName, kind, offset);
}

/// Keep the complete serializer payload so plugin fields added by a site are not
/// accidentally discarded before the group activity UI gets a chance to adapt.
final groupActivityProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, GroupActivityQuery>((ref, query) {
      final service = ref.read(discourseServiceProvider);
      return switch (query.kind) {
        GroupActivityKind.posts => service.getGroupActivityPosts(
          query.groupName,
          offset: query.offset,
        ),
        GroupActivityKind.mentions => service.getGroupActivityMentions(
          query.groupName,
          offset: query.offset,
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
