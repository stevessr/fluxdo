import 'package:fluxdo/utils/discourse_url_parser.dart';
import 'package:test/test.dart';

void main() {
  test('解析 discourse-boards 看板与卡片链接', () {
    final board = DiscourseUrlParser.parseBoard('/boards/topic/1');
    expect(board?.boardId, 1);
    expect(board?.slug, 'topic');
    expect(board?.cardId, isNull);

    final card = DiscourseUrlParser.parseBoard(
      'https://linux.do/boards/topic/1/cards/6',
    );
    expect(card?.boardId, 1);
    expect(card?.slug, 'topic');
    expect(card?.cardId, 6);

    expect(
      DiscourseUrlParser.parseBoard('/boards/api/boards/1.json'),
      isNull,
    );
  });
}
