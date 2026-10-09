import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';

void main() {
  Post postWithActions(List<dynamic> actions) => Post.fromJson({
    'id': 501,
    'username': 'other_user',
    'cooked': '<p>test</p>',
    'actions_summary': actions,
  });

  const customFlag = FlagType(
    id: 42,
    nameKey: 'custom_flag',
    name: '自定义举报',
    description: '',
    isFlag: true,
  );

  group('帖子举报状态', () {
    test('从服务端 actions_summary 恢复已经举报过的核心类型', () {
      for (final id in [3, 4, 6, 7, 8]) {
        final post = postWithActions([
          {'id': 2, 'acted': true, 'count': 1},
          {'id': id, 'acted': true},
        ]);
        expect(post.actedFlagTypeId(const <FlagType>[]), id);
      }
    });

    test('识别论坛自定义举报类型，但不误认其它已执行的动作', () {
      final post = postWithActions([
        {'id': 2, 'acted': true},
        {'id': 42, 'acted': true},
        {'id': 99, 'acted': true},
      ]);
      expect(post.actedFlagTypeId(const <FlagType>[]), isNull);
      expect(post.actedFlagTypeId([customFlag]), 42);
    });

    test('未举报或仅有非举报操作时仍允许举报', () {
      final post = postWithActions([
        {'id': 2, 'acted': true},
        {'id': 3, 'can_act': true},
        {'id': 4, 'acted': false},
      ]);
      expect(post.actedFlagTypeId(const <FlagType>[]), isNull);
    });

    test('举报成功后立即更新状态，不破坏其它动作与原始 JSON', () {
      final post = postWithActions([
        {'id': 2, 'count': 7, 'acted': true},
        {'id': 3, 'can_act': true},
      ]);
      final updated = post.withReportedFlag(3);

      expect(updated.actedFlagTypeId(const <FlagType>[]), 3);
      expect(updated, isNot(post));
      expect(updated.actionsSummary, hasLength(2));
      expect(updated.actionsSummary![0], {
        'id': 2,
        'count': 7,
        'acted': true,
      });
      expect(updated.actionsSummary![1], {
        'id': 3,
        'can_act': false,
        'acted': true,
      });
      expect(post.actionsSummary![1], {'id': 3, 'can_act': true});
      expect(updated.rawJson, same(post.rawJson));
    });

    test('重复同步不会插入第二条举报记录', () {
      final post = postWithActions([]).withReportedFlag(42);
      final refreshed = post.withReportedFlag(42);

      expect(refreshed.actionsSummary, hasLength(1));
      expect(refreshed.actedFlagTypeId([customFlag]), 42);
    });
  });
}
