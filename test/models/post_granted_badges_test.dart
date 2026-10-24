import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';

void main() {
  const appleBadge = <String, dynamic>{
    'id': 164,
    'name': 'Only Apple can do',
    'description': "It's something Only Apple can do.",
    'icon': 'fab-apple',
    'image_url': null,
    'slug': '-',
    'badge_type_id': 2,
    'show_in_post_header': true,
    'enabled': true,
  };

  test('parses Linux.do grouped badges_granted from a single post', () {
    final post = Post.fromJson({
      'id': 23990723,
      'username': 'ccy',
      'post_number': 4,
      'badges_granted': [
        {
          'badges': [appleBadge],
          'badge_types': [
            {'id': 2, 'name': 'Silver', 'sort_order': 8},
          ],
          'basic_user_badge': {
            'id': 2382186,
            'badge_id': 164,
          },
        },
      ],
    });

    expect(post.badgesGranted, hasLength(1));
    final badge = post.badgesGranted!.single;
    expect(badge.id, 164);
    expect(badge.name, 'Only Apple can do');
    expect(badge.description, "It's something Only Apple can do.");
    expect(badge.icon, 'fab-apple');
    expect(badge.badgeTypeId, 2);
    expect(badge.slug, '-');
    expect(badge.showInPostHeader, isTrue);
  });

  test('supports flat and wrapped badges, filters hidden and invalid ids', () {
    final post = Post.fromJson({
      'id': 1,
      'username': 'tester',
      'badges_granted': [
        appleBadge,
        {'badge': appleBadge},
        {
          'badges': [
            {...appleBadge, 'id': 165, 'show_in_post_header': false},
            {...appleBadge, 'id': 166, 'enabled': false},
            {...appleBadge, 'id': 167, 'icon': 'seedling'},
          ],
        },
        {'badge_types': [], 'basic_user_badge': {'badge_id': 44}},
        null,
      ],
    });

    expect(post.badgesGranted!.map((badge) => badge.id).toList(), [
      164,
      167,
    ]);
  });

  test('missing badges_granted and empty nested groups remain empty', () {
    expect(Post.fromJson({'id': 1}).badgesGranted, isEmpty);
    expect(
      Post.fromJson({
        'id': 2,
        'badges_granted': [
          {'badges': [], 'badge_types': []},
        ],
      }).badgesGranted,
      isEmpty,
    );
  });

  test('topic-level injection does not overwrite post-specific badges', () {
    final richPost = Post.fromJson({
      'id': 23990723,
      'username': 'ccy',
      'user_id': 5451,
      'badges_granted': [
        {'badges': [appleBadge]},
      ],
    });
    final emptyPost = Post.fromJson({
      'id': 23990724,
      'username': 'ccy',
      'user_id': 5451,
    });
    final posts = [richPost, emptyPost];
    PostStream.injectBadges(
      posts,
      {
        'user_badges': {
          'badges': [
            {
              'id': 999,
              'name': 'Top-level badge',
              'slug': 'top-level',
              'icon': 'star',
              'badge_type_id': 1,
            },
            {
              'id': 1000,
              'name': 'Not shown',
              'slug': 'hidden',
              'icon': 'star',
              'show_in_post_header': false,
            },
          ],
          'users': [
            {
              'id': 5451,
              'badge_ids': [999, 1000],
            },
          ],
        },
      },
      [
        {'id': 23990723, 'user_id': 5451},
        {'id': 23990724, 'user_id': 5451},
      ],
    );

    expect(posts[0].badgesGranted!.single.id, 164);
    expect(posts[1].badgesGranted!.single.id, 999);
  });
}
