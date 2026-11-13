import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/notification.dart';
import 'package:fluxdo/utils/notification_post_target.dart';

DiscourseNotification _reaction(Map<String, dynamic> data, {int? topicId}) {
  return DiscourseNotification.fromJson({
    'id': 100,
    'user_id': 7,
    'notification_type': 25,
    'read': false,
    'created_at': '2026-11-10T00:00:00.000Z',
    'topic_id': topicId,
    'data': data,
  });
}

void main() {
  test('服务端同一用户多篇帖子 reaction 聚合保留计数和原帖', () {
    final n = _reaction({
      'consolidated': true,
      'count': 4,
      'username': 'alice',
      'display_username': 'alice',
      'original_post_id': 12345,
    });

    expect(n.notificationType, NotificationType.reaction);
    expect(n.data.consolidated, isTrue);
    expect(n.data.count, 4);
    expect(n.username, 'alice');
    expect(reactionFallbackPostId(n), 12345);
  });

  test('两位用户同帖 reaction 用 username2 而非同用户合并语义', () {
    final n = _reaction({
      'count': 2,
      'display_username': 'bob',
      'username2': 'alice',
    }, topicId: 42);

    expect(n.data.consolidated, isFalse);
    expect(n.data.count, 2);
    expect(n.data.username2, 'alice');
    expect(n.topicId, 42);
  });

  test('兼容服务端传递字符串类型的 count/consolidated', () {
    final n = _reaction({
      'count': '3',
      'consolidated': 'true',
      'original_post_id': '21',
    });
    expect(n.data.count, 3);
    expect(n.data.consolidated, isTrue);
    expect(reactionFallbackPostId(n), 21);
  });
}
