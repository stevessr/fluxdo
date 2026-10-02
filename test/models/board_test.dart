import 'package:fluxdo/models/board.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析 Boards 详情中的 topic、floater 和负责人', () {
    final board = DiscourseBoard.fromDetailResponse({
      'board': {
        'id': 1,
        'name': 'iOS App',
        'unicode_name': 'iOS App',
        'slug': 'topic',
        'can_write': true,
        'columns': [
          {'id': 1, 'title': '待确认', 'position': 0, 'color': 'C97CF4'},
          {'id': 4, 'title': '已解决', 'position': 4, 'color': '94C748'},
        ],
      },
      'columns': [
        {
          'id': 1,
          'title': '待确认',
          'position': 0,
          'color': 'C97CF4',
          'cards': [
            {
              'id': 6,
              'board_id': 1,
              'column_id': 1,
              'card_type': 'topic',
              'position': 0,
              'topic_id': 2974921,
              'topic': {
                'id': 2974921,
                'title': '测试话题',
                'unicode_title': '测试话题',
                'slug': 'topic',
                'category_id': 126,
                'tags': ['ios', 'bug'],
                'posts_count': 2,
                'highest_post_number': 2,
                'bumped_at': '2026-10-01T10:48:33.958Z',
                'last_poster': {'username': 'neo'},
                'all_assigned_users': [
                  {
                    'username': 'alice',
                    'avatar_template':
                        '/user_avatar/linux.do/alice/{size}/2.png',
                  },
                ],
              },
            },
            {
              'id': 7,
              'board_id': 1,
              'column_id': 1,
              'card_type': 'floater',
              'position': 1,
              'title': 'App 闪退',
              'assigned_to': {
                'type': 'User',
                'username': 'bob',
                'avatar_template': '/user_avatar/linux.do/bob/{size}/3.png',
              },
              'tags': [
                {'id': 3, 'name': 'crash', 'slug': 'crash'},
              ],
            },
          ],
        },
        {
          'id': 4,
          'title': '已解决',
          'position': 4,
          'color': '94C748',
          'cards': [],
        },
      ],
    });

    expect(board.id, 1);
    expect(board.columns, hasLength(2));
    expect(board.columns.last.isResolvedLike, isTrue);

    final topicCard = board.columns.first.cards.first;
    expect(topicCard.isTopic, isTrue);
    expect(topicCard.displayTitle, '测试话题');
    expect(topicCard.topic?.lastPosterUsername, 'neo');
    expect(topicCard.topic?.tags.map((tag) => tag.name), ['ios', 'bug']);
    expect(topicCard.assignedUsers.single.username, 'alice');

    final floater = board.columns.first.cards[1];
    expect(floater.isTopic, isFalse);
    expect(floater.displayTitle, 'App 闪退');
    expect(floater.displayTags.single.name, 'crash');
    expect(floater.assignedUsers.single.username, 'bob');
  });
}
