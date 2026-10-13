import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/board.dart';
import 'package:fluxdo/widgets/topic/add_to_board_sheet.dart';

void main() {
  test('available.json 精简看板不含 can_write 也能选择', () {
    // 上游 BasicBoardSerializer 只返回 id、unicode_name、slug、columns。
    final board = DiscourseBoard.fromJson({
      'id': 1,
      'unicode_name': '研发看板',
      'slug': 'dev',
      'columns': [],
    });
    expect(board.canWrite, false);
    expect(board.canManage, false);
    expect(availableTopicBoards([board]), [board]);
  });

  test('已归档看板不会出现在可选择列表', () {
    final active = DiscourseBoard.fromJson({
      'id': 1, 'unicode_name': 'Open', 'archived': false,
    });
    final archived = DiscourseBoard.fromJson({
      'id': 2, 'unicode_name': 'Old', 'archived': true,
    });
    expect(availableTopicBoards([active, archived]), [active]);
  });

  test('在不同列发现已有话题卡，且无需 topic 子对象', () {
    final board = DiscourseBoard.fromDetailResponse({
      'board': {'id': 1, 'unicode_name': 'Board'},
      'columns': [
        {
          'id': 12, 'title': 'Todo', 'cards': [
            {'id': 41, 'board_id': 1, 'column_id': 12,
              'card_type': 'topic', 'topic_id': 123},
          ],
        },
        {'id': 13, 'title': 'Doing', 'cards': []},
      ],
    });
    final existing = existingTopicBoardCard(board, 123);
    expect(existing?.id, 41);
    expect(existing?.columnId, 12);
    expect(existingTopicBoardCard(board, 999), isNull);
  });
}
