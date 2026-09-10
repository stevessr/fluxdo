import 'dart:math' as math;

import '../../models/topic.dart';

/// Merge a freshly fetched topic detail into an existing topic-list item.
///
/// Topic detail and topic-list serializers intentionally expose different
/// fields. Rebuilding a list item from detail alone drops list-only metadata
/// (bookmarks, excerpt, pinned state, etc.) and, more importantly, must never
/// mark a topic read just because a MessageBus event caused a background
/// refresh. Keep list/read state unless the detail response is authoritative
/// for that field.
Topic mergeTopicListItemFromDetail(Topic existing, TopicDetail detail) {
  final detailHighest = detail.highestPostNumber > 0
      ? detail.highestPostNumber
      : detail.postsCount;
  final highestPostNumber = math.max(existing.highestPostNumber, detailHighest);

  final latestPost = detail.postStream.posts.isNotEmpty
      ? detail.postStream.posts.last
      : null;
  final detailContainsLatestPost =
      latestPost != null && latestPost.postNumber == detailHighest;

  // TopicDetail uses false as the fallback for optional plugin booleans. Only
  // let false clear a list-side true value when the serializer actually sent
  // the scalar. A non-empty acceptedAnswers list is independently authoritative.
  final rawSolved = detail.pluginExtras['has_accepted_answer'];
  final hasAcceptedAnswer =
      detail.hasAcceptedAnswer ||
      (rawSolved is bool ? rawSolved : existing.hasAcceptedAnswer);
  final rawPostVoting = detail.pluginExtras['is_post_voting'];
  final isPostVoting = rawPostVoting is bool
      ? rawPostVoting
      : (detail.isPostVoting || existing.isPostVoting);

  return Topic(
    id: detail.id,
    title: detail.title,
    slug: detail.slug,
    postsCount: detail.postsCount,
    replyCount: detail.postsCount > 0 ? detail.postsCount - 1 : 0,
    views: detail.views,
    likeCount: detail.likeCount,
    excerpt: existing.excerpt,
    createdAt: detail.createdAt ?? existing.createdAt,
    lastPostedAt: detailContainsLatestPost
        ? latestPost.createdAt
        : existing.lastPostedAt,
    lastPosterUsername: detailContainsLatestPost
        ? latestPost.username
        : existing.lastPosterUsername,
    categoryId: detail.categoryId.toString(),
    pinned: existing.pinned,
    visible: detail.visible,
    closed: detail.closed,
    archived: detail.archived,
    tags: detail.tags ?? existing.tags,
    posters: existing.posters,
    unseen: existing.unseen,
    unread: existing.unread,
    newPosts: existing.newPosts,
    lastReadPostNumber: existing.lastReadPostNumber,
    highestPostNumber: highestPostNumber,
    bookmarkedPostNumber: existing.bookmarkedPostNumber,
    bookmarkId: existing.bookmarkId,
    bookmarkName: existing.bookmarkName,
    bookmarkReminderAt: existing.bookmarkReminderAt,
    bookmarkableType: existing.bookmarkableType,
    bookmarkableUrl: existing.bookmarkableUrl,
    hasAcceptedAnswer: hasAcceptedAnswer,
    canHaveAnswer:
        (detail.pluginExtras['can_have_answer'] as bool?) ??
        existing.canHaveAnswer,
    isPostVoting: isPostVoting,
  );
}
