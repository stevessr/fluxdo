import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';

void main() {
  test('category/tag tracking preserves watching first post level 4', () {
    final level = DiscourseTrackingLevel.fromValue(4);

    expect(level, DiscourseTrackingLevel.watchingFirstPost);
    expect(level.value, 4);
    expect(level.topicLevel, isNull);
  });

  test('topic-compatible tracking levels map without changing values', () {
    expect(
      DiscourseTrackingLevel.fromValue(0).topicLevel,
      TopicNotificationLevel.muted,
    );
    expect(
      DiscourseTrackingLevel.fromValue(1).topicLevel,
      TopicNotificationLevel.regular,
    );
    expect(
      DiscourseTrackingLevel.fromValue(2).topicLevel,
      TopicNotificationLevel.tracking,
    );
    expect(
      DiscourseTrackingLevel.fromValue(3).topicLevel,
      TopicNotificationLevel.watching,
    );
  });
}
