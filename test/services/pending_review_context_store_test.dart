import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/pending_review_context_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const site = 'https://linux.do';
  const username = 'alice';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PendingReviewContextStore.resetMemoryCacheForTest();
  });

  test('应用内存缓存丢失后仍可从持久化恢复标签', () async {
    await PendingReviewContextStore.recordTopicTags(
      site: site,
      username: username,
      reviewableId: 100,
      tags: ['flutter', 'discourse'],
    );

    PendingReviewContextStore.resetMemoryCacheForTest();

    expect(
      await PendingReviewContextStore.readTopicTags(
        site: site,
        username: username,
        reviewableId: 100,
      ),
      ['flutter', 'discourse'],
    );
  });

  test('不同账号的 reviewable 上下文互不影响', () async {
    await PendingReviewContextStore.recordTopicTags(
      site: site,
      username: 'alice',
      reviewableId: 101,
      tags: ['alice-tag'],
    );
    await PendingReviewContextStore.recordTopicTags(
      site: site,
      username: 'bob',
      reviewableId: 101,
      tags: ['bob-tag'],
    );

    expect(
      await PendingReviewContextStore.readTopicTags(
        site: site,
        username: 'alice',
        reviewableId: 101,
      ),
      ['alice-tag'],
    );
    expect(
      await PendingReviewContextStore.readTopicTags(
        site: site,
        username: 'bob',
        reviewableId: 101,
      ),
      ['bob-tag'],
    );
  });

  test('retain 只清理当前账号已不在待审列表中的上下文', () async {
    await PendingReviewContextStore.recordTopicTags(
      site: site,
      username: username,
      reviewableId: 201,
      tags: ['keep'],
    );
    await PendingReviewContextStore.recordTopicTags(
      site: site,
      username: username,
      reviewableId: 202,
      tags: ['remove'],
    );
    await PendingReviewContextStore.recordTopicTags(
      site: site,
      username: 'bob',
      reviewableId: 202,
      tags: ['other-account'],
    );

    await PendingReviewContextStore.retainTopicTags(
      site: site,
      username: username,
      activeReviewableIds: {201},
    );

    expect(
      await PendingReviewContextStore.readTopicTags(
        site: site,
        username: username,
        reviewableId: 201,
      ),
      ['keep'],
    );
    expect(
      await PendingReviewContextStore.readTopicTags(
        site: site,
        username: username,
        reviewableId: 202,
      ),
      isNull,
    );
    expect(
      await PendingReviewContextStore.readTopicTags(
        site: site,
        username: 'bob',
        reviewableId: 202,
      ),
      ['other-account'],
    );
  });
}
