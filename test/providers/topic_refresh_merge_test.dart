import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/topic_list/topic_refresh_merge.dart';

void main() {
  group('mergeTopicListItemFromDetail', () {
    test('preserves read, bookmark, and list-only metadata', () {
      final createdAt = DateTime.utc(2026, 1, 1);
      final lastPostedAt = DateTime.utc(2026, 1, 2);
      final reminderAt = DateTime.utc(2026, 1, 3);
      final existing = Topic(
        id: 42,
        title: 'old',
        slug: 'old',
        postsCount: 3,
        replyCount: 2,
        views: 99,
        likeCount: 12,
        excerpt: 'keep me',
        createdAt: createdAt,
        lastPostedAt: lastPostedAt,
        lastPosterUsername: 'alice',
        categoryId: '1',
        pinned: true,
        tags: const [Tag(name: 'old-tag')],
        unseen: true,
        unread: 2,
        newPosts: 1,
        lastReadPostNumber: 1,
        highestPostNumber: 3,
        bookmarkedPostNumber: 2,
        bookmarkId: 7,
        bookmarkName: 'keep bookmark',
        bookmarkReminderAt: reminderAt,
        bookmarkableType: 'Post',
        bookmarkableUrl: '/t/42/2',
        hasAcceptedAnswer: true,
        canHaveAnswer: true,
      );
      final detail = TopicDetail(
        id: 42,
        title: 'new',
        slug: 'new',
        postsCount: 4,
        postStream: PostStream(posts: const [], stream: const []),
        categoryId: 2,
        closed: true,
        archived: false,
        tags: const [Tag(name: 'new-tag')],
        views: 120,
        likeCount: 14,
        visible: false,
        highestPostNumber: 4,
        pluginExtras: const {'has_accepted_answer': false},
      );

      final merged = mergeTopicListItemFromDetail(existing, detail);

      expect(merged.title, 'new');
      expect(merged.slug, 'new');
      expect(merged.postsCount, 4);
      expect(merged.replyCount, 3);
      expect(merged.categoryId, '2');
      expect(merged.closed, isTrue);
      expect(merged.visible, isFalse);
      expect(merged.views, 120);
      expect(merged.likeCount, 14);
      expect(merged.tags.single.name, 'new-tag');
      expect(merged.highestPostNumber, 4);

      expect(merged.unseen, isTrue);
      expect(merged.unread, 2);
      expect(merged.newPosts, 1);
      expect(merged.lastReadPostNumber, 1);
      expect(merged.excerpt, 'keep me');
      expect(merged.pinned, isTrue);
      expect(merged.lastPostedAt, lastPostedAt);
      expect(merged.lastPosterUsername, 'alice');
      expect(merged.bookmarkedPostNumber, 2);
      expect(merged.bookmarkId, 7);
      expect(merged.bookmarkName, 'keep bookmark');
      expect(merged.bookmarkReminderAt, reminderAt);
      expect(merged.bookmarkableType, 'Post');
      expect(merged.bookmarkableUrl, '/t/42/2');

      // Explicit false from the detail serializer can clear solved state.
      expect(merged.hasAcceptedAnswer, isFalse);
      // Missing plugin scalar must not erase list-side capability metadata.
      expect(merged.canHaveAnswer, isTrue);
    });

    test('updates solved capability and post-voting flags from detail', () {
      final existing = Topic(
        id: 7,
        title: 'topic',
        slug: 'topic',
        postsCount: 2,
        replyCount: 1,
        views: 10,
        likeCount: 1,
        categoryId: '1',
        highestPostNumber: 5,
        canHaveAnswer: true,
      );
      final detail = TopicDetail(
        id: 7,
        title: 'topic',
        slug: 'topic',
        postsCount: 3,
        postStream: PostStream(posts: const [], stream: const []),
        categoryId: 1,
        closed: false,
        archived: false,
        highestPostNumber: 3,
        isPostVoting: true,
        acceptedAnswers: const [
          AcceptedAnswer(postNumber: 2, username: 'solver'),
        ],
        pluginExtras: const {'can_have_answer': false},
      );

      final merged = mergeTopicListItemFromDetail(existing, detail);

      expect(merged.hasAcceptedAnswer, isTrue);
      expect(merged.canHaveAnswer, isFalse);
      expect(merged.isPostVoting, isTrue);
      // A stale detail response must not move the list cursor backwards.
      expect(merged.highestPostNumber, 5);
    });

    test('does not clear optional plugin flags when detail omits them', () {
      final existing = Topic(
        id: 9,
        title: 'topic',
        slug: 'topic',
        postsCount: 2,
        replyCount: 1,
        views: 1,
        likeCount: 0,
        categoryId: '1',
        hasAcceptedAnswer: true,
        isPostVoting: true,
      );
      final detail = TopicDetail(
        id: 9,
        title: 'topic',
        slug: 'topic',
        postsCount: 2,
        postStream: PostStream(posts: const [], stream: const []),
        categoryId: 1,
        closed: false,
        archived: false,
      );

      final merged = mergeTopicListItemFromDetail(existing, detail);

      expect(merged.hasAcceptedAnswer, isTrue);
      expect(merged.isPostVoting, isTrue);
    });
  });
}
