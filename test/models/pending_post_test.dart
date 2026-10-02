import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/pending_post.dart';

void main() {
  group('PendingPost', () {
    test('兼容字符串和对象两种标签格式', () {
      final pending = PendingPost.fromJson({
        'id': 42,
        'raw_text': 'body',
        'title': 'title',
        'category_id': 7,
        'tags': [
          'plain-tag',
          {'id': 2, 'name': 'object-tag', 'count': 5},
        ],
      });

      expect(pending.tags, ['plain-tag', 'object-tag']);
    });

    test('官方 pending serializer 不含 tags 时保持 null', () {
      final pending = PendingPost.fromJson({
        'id': 43,
        'raw_text': 'body',
        'title': 'title',
        'category_id': 7,
      });

      expect(pending.tags, isNull);
    });
  });

  group('PendingTopicTagsRegistry', () {
    const reviewableId = 9001;

    tearDown(() {
      PendingTopicTagsRegistry.remove(reviewableId);
    });

    test('按 reviewable id 保存并返回标签副本', () {
      PendingTopicTagsRegistry.record(reviewableId, ['flutter', 'discourse']);

      final first = PendingTopicTagsRegistry.lookup(reviewableId);
      expect(first, ['flutter', 'discourse']);

      first!.add('mutated');
      expect(
        PendingTopicTagsRegistry.lookup(reviewableId),
        ['flutter', 'discourse'],
      );
    });

    test('remove 后不再返回标签', () {
      PendingTopicTagsRegistry.record(reviewableId, ['tag']);
      PendingTopicTagsRegistry.remove(reviewableId);

      expect(PendingTopicTagsRegistry.contains(reviewableId), isFalse);
      expect(PendingTopicTagsRegistry.lookup(reviewableId), isNull);
    });
  });
}
