import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluxdo/providers/selected_topic_provider.dart';

void main() {
  test('从列表选中的首层会立即绑定稳定 instanceId', () {
    final notifier = SelectedTopicNotifier()..select(topicId: 1);
    final instanceId = notifier.state.instanceId;

    expect(instanceId, isNotNull);

    notifier.push(topicId: 2);

    expect(notifier.state.stack.first.instanceId, instanceId);
  });

  test('同一话题的不同面板实例分别保存浏览位置', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const first = (topicId: 1, instanceId: 'first');
    const second = (topicId: 1, instanceId: 'second');

    container.read(detailScrollPositionProvider(first).notifier).state = 120;

    expect(container.read(detailScrollPositionProvider(first)), 120);
    expect(container.read(detailScrollPositionProvider(second)), isNull);
  });

  group('SelectedTopicNotifier.updateTopTopic', () {
    test('更新栈顶话题时保留此前的平行视界历史', () {
      final notifier = SelectedTopicNotifier()
        ..select(topicId: 1, initialTitle: '第一层')
        ..pushProfile('alice')
        ..push(topicId: 2, initialTitle: '旧标题');

      notifier.updateTopTopic(
        topicId: 2,
        initialTitle: '新标题',
        scrollToPostNumber: 42,
        instanceId: 'instance-2',
      );

      expect(notifier.state.stack, hasLength(3));
      expect(notifier.state.stack[0].topicId, 1);
      expect(notifier.state.stack[1].username, 'alice');
      expect(notifier.state.topEntry?.topicId, 2);
      expect(notifier.state.topEntry?.initialTitle, '新标题');
      expect(notifier.state.topEntry?.scrollToPostNumber, 42);
      expect(notifier.state.topEntry?.instanceId, 'instance-2');
    });

    test('栈顶不是目标话题时不修改状态', () {
      final notifier = SelectedTopicNotifier()
        ..select(topicId: 1)
        ..pushProfile('alice');
      final before = notifier.state;

      notifier.updateTopTopic(topicId: 1, scrollToPostNumber: 9);

      expect(notifier.state, same(before));
    });
  });

  test('切换左栏时仅保留当前栈顶详情', () {
    final notifier = SelectedTopicNotifier()
      ..select(topicId: 1)
      ..pushProfile('alice')
      ..push(topicId: 2);

    notifier.collapseToTop();

    expect(notifier.state.stack, hasLength(1));
    expect(notifier.state.topicId, 2);
    expect(notifier.state.isStacked, isFalse);
  });

  test('追觅平行视界与首页、搜索栈相互隔离', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(selectedSeekingProvider.notifier).select(topicId: 99);

    expect(container.read(selectedSeekingProvider).topicId, 99);
    expect(container.read(selectedTopicProvider).hasSelection, isFalse);
    expect(container.read(selectedSearchProvider).hasSelection, isFalse);
  });

  testWidgets('EmbeddedStackScope 将资料页话题入口压入当前面板栈', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: EmbeddedStackScope(
            stackProvider: selectedMessageProvider,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => EmbeddedStackScope.maybePushTopic(
                  context,
                  topicId: 42,
                  initialTitle: '资料页话题',
                  scrollToPostNumber: 7,
                ),
                child: const Text('打开话题'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开话题'));

    final state = container.read(selectedMessageProvider);
    expect(state.stack, hasLength(1));
    expect(state.topicId, 42);
    expect(state.initialTitle, '资料页话题');
    expect(state.scrollToPostNumber, 7);
    expect(container.read(selectedTopicProvider).hasSelection, isFalse);
  });
  test('PICO 标签激活保留全部层与实例 ID，关闭指定层不串位', () {
    final notifier = SelectedTopicNotifier()
      ..select(topicId: 1, instanceId: 'first')
      ..pushProfile('alice')
      ..push(topicId: 2, instanceId: 'second');

    notifier.activateTab(0);
    expect(notifier.state.stack, hasLength(3));
    expect(notifier.state.topEntry?.instanceId, 'first');
    expect(notifier.state.stack[1].instanceId, 'second');

    notifier.closeTab(0); // 关闭背景资料标签
    expect(notifier.state.stack, hasLength(2));
    expect(notifier.state.topEntry?.instanceId, 'first');

    notifier.closeTab(1); // 关闭活动标签
    expect(notifier.state.topEntry?.instanceId, 'second');

    final unchanged = notifier.state;
    notifier.activateTab(-1);
    notifier.closeTab(99);
    expect(notifier.state, same(unchanged));
  });

  test('独立 Tab 打开、复用、关闭并保留稳定实例', () {
    final notifier = SelectedTopicNotifier()
      ..select(topicId: 1, instanceId: 'first')
      ..enableTabMode()
      ..openTopicTab(topicId: 2, instanceId: 'second');

    expect(notifier.state.tabMode, isTrue);
    expect(notifier.state.stack, hasLength(2));

    notifier.openTopicTab(topicId: 1);
    expect(notifier.state.stack, hasLength(2));
    expect(notifier.state.topEntry?.instanceId, 'first');

    notifier.closeTab(1);
    expect(notifier.state.topicId, 2);
    expect(notifier.state.tabMode, isTrue);

    notifier.select(topicId: 3);
    expect(notifier.state.tabMode, isFalse);
    expect(notifier.state.stack, hasLength(1));
  });

  test('切回信息流不会销毁 Tab，重新激活后恢复详情', () {
    final notifier = SelectedTopicNotifier()
      ..openTopicTab(topicId: 1, instanceId: 'first')
      ..openTopicTab(topicId: 2, instanceId: 'second');

    notifier.showFeed();
    expect(notifier.state.showingFeed, isTrue);
    expect(notifier.state.stack, hasLength(2));
    expect(notifier.state.topEntry?.instanceId, 'second');

    notifier.activateTab(0);
    expect(notifier.state.showingFeed, isFalse);
    expect(notifier.state.topEntry?.instanceId, 'first');
    expect(notifier.state.stack, hasLength(2));
  });

  test('从列表点击当前最后一个 Tab 会重新显示详情', () {
    final notifier = SelectedTopicNotifier()
      ..openTopicTab(topicId: 42)
      ..showFeed();

    expect(notifier.state.showingFeed, isTrue);
    notifier.activateTab(0);
    expect(notifier.state.showingFeed, isFalse);
    expect(notifier.state.topicId, 42);
  });

  test('信息流可见时关闭背景 Tab 不会切回详情', () {
    final notifier = SelectedTopicNotifier()
      ..openTopicTab(topicId: 1)
      ..openTopicTab(topicId: 2)
      ..showFeed()
      ..closeTab(0);

    expect(notifier.state.showingFeed, isTrue);
    expect(notifier.state.stack, hasLength(1));
    expect(notifier.state.topicId, 2);
  });

  test('关闭最后一个 Tab 后回到信息流并保留 Tab 模式', () {
    final notifier = SelectedTopicNotifier()
      ..openTopicTab(topicId: 1)
      ..closeTab(0);

    expect(notifier.state.tabMode, isFalse);
    expect(notifier.state.showingFeed, isFalse);
    expect(notifier.state.stack, isEmpty);
  });

  test('私信与公开话题共享一套标签，并复用相同话题实例', () {
    final notifier = SelectedTopicNotifier()
      ..openTopicTab(topicId: 10, initialTitle: '公开', instanceId: 'public')
      ..openTopicTab(
        topicId: 20,
        initialTitle: '私信',
        instanceId: 'private',
        isPrivateMessage: true,
      );

    expect(notifier.state.stack, hasLength(2));
    expect(notifier.state.stack.last.isPrivateMessage, isTrue);

    notifier.openTopicTab(topicId: 20, isPrivateMessage: true);
    expect(notifier.state.stack, hasLength(2));
    expect(notifier.state.instanceId, 'private');

    notifier.activateTab(0);
    expect(notifier.state.stack.last.instanceId, 'public');
    expect(notifier.state.stack.first.isPrivateMessage, isTrue);
  });

  test('从普通话题入口再次打开私信可升级标记，实例不重建', () {
    final notifier = SelectedTopicNotifier()
      ..openTopicTab(topicId: 3, instanceId: 'old')
      ..openTopicTab(topicId: 3, isPrivateMessage: true);
    expect(notifier.state.stack, hasLength(1));
    expect(notifier.state.topEntry!.isPrivateMessage, isTrue);
    expect(notifier.state.instanceId, 'old');
  });

  test('Tab 模式的内部链接不会顶掉相邻标签，也不会重复打开同一话题', () {
    final notifier = SelectedTopicNotifier()
      ..openTopicTab(topicId: 1, instanceId: 'public')
      ..openTopicTab(
        topicId: 2,
        instanceId: 'private',
        isPrivateMessage: true,
      );

    notifier.push(topicId: 3, initialTitle: '链接目标');
    expect(notifier.state.stack.map((e) => e.topicId), [1, 2, 3]);

    notifier.pushTruncating(topicId: 2);
    expect(notifier.state.stack.map((e) => e.topicId), [1, 3, 2]);
    expect(notifier.state.stack.last.instanceId, 'private');
    expect(notifier.state.stack.last.isPrivateMessage, isTrue);
  });

  test('再次打开现有 Tab 不会丢失回复意图或定位信息', () {
    final notifier = SelectedTopicNotifier()
      ..select(
        topicId: 4,
        instanceId: 'resume',
        autoOpenReply: true,
        autoReplyToPostNumber: 2,
      )
      ..enableTabMode();

    notifier.openTopicTab(topicId: 4, initialTitle: '新标题');
    expect(notifier.state.stack, hasLength(1));
    expect(notifier.state.instanceId, 'resume');
    expect(notifier.state.topEntry!.initialTitle, '新标题');
    expect(notifier.state.topEntry!.autoOpenReply, isTrue);
    expect(notifier.state.topEntry!.autoReplyToPostNumber, 2);
  });

  test('长按关闭其他标签保留目标，关闭所有返回列表', () {
    final notifier = SelectedTopicNotifier()
      ..openTopicTab(topicId: 10, instanceId: 'first')
      ..openTopicTab(
        topicId: 20,
        instanceId: 'second',
        isPrivateMessage: true,
      )
      ..openTopicTab(topicId: 30, instanceId: 'third');

    notifier.closeOtherTabs(1);
    expect(notifier.state.stack, hasLength(1));
    expect(notifier.state.instanceId, 'second');
    expect(notifier.state.topEntry!.isPrivateMessage, isTrue);
    expect(notifier.state.tabMode, isTrue);

    final before = notifier.state;
    notifier.closeOtherTabs(-1);
    expect(notifier.state, same(before));

    notifier.closeAllTabs();
    expect(notifier.state.stack, isEmpty);
    expect(notifier.state.tabMode, isFalse);
  });

  test('Tab 模式压栈和返回不会被静默关闭', () {
    final notifier = SelectedTopicNotifier()
      ..openTopicTab(topicId: 1)
      ..push(topicId: 2)
      ..pop();

    expect(notifier.state.tabMode, isTrue);
    expect(notifier.state.topicId, 1);
  });

  test('通知重复打开同一话题只激活一个 Tab 并更新楼层', () {
    final notifier = SelectedTopicNotifier()
      ..openTopicTab(topicId: 10, instanceId: 'original', scrollToPostNumber: 3)
      ..openTopicTab(topicId: 20, instanceId: 'second');

    notifier.openTopicTab(
      topicId: 10,
      scrollToPostNumber: 12,
      highlightBoostUsername: 'alice',
      replaceNavigationTarget: true,
    );

    expect(notifier.state.tabMode, isTrue);
    expect(notifier.state.stack, hasLength(2));
    expect(notifier.state.topEntry?.instanceId, 'original');
    expect(notifier.state.topEntry?.scrollToPostNumber, 12);
    expect(notifier.state.topEntry?.highlightBoostUsername, 'alice');

    notifier.openTopicTab(
      topicId: 10,
      scrollToPostNumber: 15,
      initialRevisionPostNumber: 15,
      initialRevisionNumber: 2,
      replaceNavigationTarget: true,
    );
    expect(notifier.state.stack, hasLength(2));
    expect(notifier.state.topEntry?.instanceId, isNot('original'));
    expect(notifier.state.topEntry?.scrollToPostNumber, 15);
    expect(notifier.state.topEntry?.highlightBoostUsername, isNull);
    expect(notifier.state.topEntry?.initialRevisionPostNumber, 15);
    expect(notifier.state.topEntry?.initialRevisionNumber, 2);
  });

  test('通知打开私信 Tab 不覆盖公开话题且保留来源', () {
    final notifier = SelectedTopicNotifier()
      ..openTopicTab(topicId: 77, instanceId: 'pm', isPrivateMessage: true)
      ..openTopicTab(topicId: 88, instanceId: 'public');

    notifier.openTopicTab(
      topicId: 77,
      isPrivateMessage: true,
      scrollToPostNumber: 8,
      replaceNavigationTarget: true,
    );
    expect(notifier.state.stack, hasLength(2));
    expect(notifier.state.topEntry?.isPrivateMessage, isTrue);
    expect(notifier.state.topEntry?.instanceId, 'pm');
    expect(notifier.state.topEntry?.scrollToPostNumber, 8);
  });
}
