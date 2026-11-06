import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';

void main() {
  group('Post raw JSON', () {
    test('保留未建模字段和嵌套键值', () {
      final post = Post.fromJson({
        'id': 42,
        'username': 'tester',
        'cooked': '<p>Hello</p>',
        'plugin_extra': {
          'enabled': true,
          'payload': [1, 'two', null],
        },
        'future_server_field': 'keep-me',
      });

      expect(post.rawJson['id'], 42);
      expect(post.rawJson['future_server_field'], 'keep-me');
      expect(
        post.rawJson['plugin_extra'],
        {
          'enabled': true,
          'payload': [1, 'two', null],
        },
      );
    });

    test('copyWith 保留服务端原始 JSON 快照', () {
      final post = Post.fromJson({
        'id': 43,
        'username': 'tester',
        'unknown_key': 'server-value',
      });

      final updated = post.copyWith(likeCount: 9);

      expect(updated.likeCount, 9);
      expect(updated.rawJson, same(post.rawJson));
      expect(updated.rawJson['unknown_key'], 'server-value');
    });

    test('原始 JSON 顶层快照不可修改', () {
      final post = Post.fromJson({
        'id': 44,
        'username': 'tester',
        'unknown_key': true,
      });

      expect(
        () => post.rawJson['another_key'] = false,
        throwsUnsupportedError,
      );
    });
  });
}
