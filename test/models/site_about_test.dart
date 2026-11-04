import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/site_about.dart';

void main() {
  test('parses /about.json and preserves the server staff order', () {
    final data = SiteAboutData.fromJson({
      'users': [
        {
          'id': 9,
          'username': 'moderator',
          'name': 'Moderator',
          'avatar_template': '/user_avatar/linux.do/moderator/{size}/1.png',
          'title': 'Site moderator',
        },
        {
          'id': 1,
          'username': 'admin',
          'name': 'Admin',
          'avatar_template': '/user_avatar/linux.do/admin/{size}/2.png',
        },
      ],
      'about': {
        'title': 'LINUX DO',
        'description': 'Where possible begins.',
        'extended_site_description':
            '<p>First line<br>Second line</p><p>Next paragraph</p>',
        'banner_image': 'https://example.com/banner.png',
        'site_creation_date': '2024-01-17T07:40:09.982Z',
        'contact_email': 'admin@example.com',
        'admin_ids': [1],
        'moderator_ids': [1, 9],
        'stats': {
          'users_count': 154919,
          'topics_last_day': 1451,
          'active_users_last_day': 48000,
          'topics_7_days': 11745,
          'topics_30_days': 45582,
        },
      },
    });

    expect(data.title, 'LINUX DO');
    expect(data.description, 'Where possible begins.');
    expect(data.extendedDescription, 'First line\nSecond line\nNext paragraph');
    expect(data.createdAt?.year, 2024);
    expect(data.admins.map((user) => user.username), ['admin']);
    expect(data.moderators.map((user) => user.username), [
      'admin',
      'moderator',
    ]);
    expect(data.users.first.avatarPath(size: 96),
        '/user_avatar/linux.do/moderator/96/1.png');
    expect(data.stat('users', 'count'), 154919);
    expect(data.stat('topics', 'last_day'), 1451);
    expect(data.stat('topics', '7_days'), 11745);
    expect(data.stat('topics', '30_days'), 45582);
    expect(data.stat('active_users', 'count'), isNull);
  });

  test('handles partially populated or restricted about responses', () {
    final empty = SiteAboutData.fromJson({'about': <String, dynamic>{}});
    expect(empty.users, isEmpty);
    expect(empty.admins, isEmpty);
    expect(empty.moderators, isEmpty);
    expect(empty.createdAt, isNull);
    expect(empty.stat('users', 'count'), isNull);

    final partial = SiteAboutData.fromJson({
      'users': [
        {'id': 4, 'username': 'known'},
      ],
      'about': {
        'admin_ids': [4, 5],
        'moderator_ids': [6],
        'stats': {'posts_count': 0},
      },
    });
    expect(partial.admins.single.username, 'known');
    expect(partial.moderators, isEmpty);
    expect(partial.stat('posts', 'count'), 0);
  });

  test('renders safe paragraph text instead of HTML or scripts', () {
    expect(
      siteAboutHtmlToText(
        '<div>Hello &amp; welcome<br>Back</div>'
        '<script>alert("wrong")</script><p>Last line</p>',
      ),
      'Hello & welcome\nBack\nLast line',
    );
  });
}
