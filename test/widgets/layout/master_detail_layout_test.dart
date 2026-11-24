import 'package:common_ui/common_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/widgets/layout/draggable_divider.dart';
import 'package:fluxdo/widgets/layout/master_detail_layout.dart';

void main() {
  Future<void> pumpLayout(WidgetTester tester, {required double width}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MasterDetailLayout(
            master: ColoredBox(
              key: ValueKey('master-content'),
              color: Colors.blue,
            ),
            detail: ColoredBox(
              key: ValueKey('detail-content'),
              color: Colors.green,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('desktop layout prefers masterWidth over tiny ratio widths', (
    tester,
  ) async {
    await pumpLayout(tester, width: 1600);

    final masterSize = tester.getSize(
      find.byKey(const ValueKey('master-pane')),
    );
    final detailSize = tester.getSize(
      find.byKey(const ValueKey('detail-content')),
    );

    // 初始宽度 = max(比例 0.2*1600=320, masterWidth 380) = 380：
    // 列表栏可读宽度由内容决定，比例只负责大窗口放宽。
    expect(masterSize.width, closeTo(380, 0.1));
    expect(detailSize.width, greaterThanOrEqualTo(400));
  });

  testWidgets('desktop layout keeps the ratio upper bound near tablet size', (
    tester,
  ) async {
    await pumpLayout(tester, width: 1000);

    final masterSize = tester.getSize(
      find.byKey(const ValueKey('master-pane')),
    );
    final detailSize = tester.getSize(
      find.byKey(const ValueKey('detail-content')),
    );

    // preferred = max(200, 380) = 380，被 maxMasterRatio(0.3*1000=300) 压回
    expect(masterSize.width, closeTo(300, 0.1));
    expect(detailSize.width, greaterThanOrEqualTo(400));
  });

  testWidgets('narrow windows stay single pane', (tester) async {
    await pumpLayout(tester, width: 760);

    final masterSize = tester.getSize(
      find.byKey(const ValueKey('master-pane')),
    );
    expect(masterSize.width, closeTo(760, 0.1));
    expect(find.byKey(const ValueKey('detail-content')), findsNothing);
  });

  testWidgets('user resize sticks across window width changes', (tester) async {
    await pumpLayout(tester, width: 1600);

    // 初始：max(1600 * 0.2, masterWidth 380) = 380
    var masterSize = tester.getSize(find.byKey(const ValueKey('master-pane')));
    expect(masterSize.width, closeTo(380, 0.1));

    // 用户向右拖动 24 像素:380+24=404,吸附到 8px 网格 → 408
    await tester.timedDrag(
      find.byType(DraggableDivider),
      const Offset(24, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pump();

    masterSize = tester.getSize(find.byKey(const ValueKey('master-pane')));
    expect(masterSize.width, closeTo(408, 1));

    // 缩小窗口到 1400，用户设定的 408 仍在合法范围内，应当保持
    tester.view.physicalSize = const Size(1400, 800);
    await tester.pump();

    masterSize = tester.getSize(find.byKey(const ValueKey('master-pane')));
    expect(masterSize.width, closeTo(408, 1));
  });

  testWidgets('多 Tab 打开、切换、关闭不顶掉左侧信息流', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 800);
    addTearDown(tester.view.reset);

    Widget layout(List<String> tabs) => MaterialApp(
      home: Scaffold(
        body: MasterDetailLayout(
          pinMaster: true,
          preferredMasterRatio: 0.25,
          animatePanes: false,
          master: const SizedBox.expand(
            key: ValueKey('feed-master'),
            child: ColoredBox(color: Colors.blue),
          ),
          panes: [
            for (final tab in tabs)
              ColoredBox(key: ValueKey('tab-$tab'), color: Colors.green),
          ],
        ),
      ),
    );

    void expectFeedAndTab(String activeTab) {
      final feed = find.byKey(const ValueKey('feed-master'));
      final detail = find.byKey(ValueKey('tab-$activeTab'));
      expect(feed, findsOneWidget);
      expect(tester.getTopLeft(feed).dx, closeTo(0, 0.1));
      expect(tester.getSize(feed).width, closeTo(400, 0.1));
      expect(detail, findsOneWidget);
    }

    await tester.pumpWidget(layout(['a']));
    await tester.pumpAndSettle();
    expectFeedAndTab('a');

    // 第二个 Tab 只替换右栏的可见内容，旧 Tab 仍挂载。
    await tester.pumpWidget(layout(['a', 'b']));
    await tester.pumpAndSettle();
    expectFeedAndTab('b');
    expect(find.byKey(const ValueKey('tab-a')), findsNothing);
    expect(
      find.byKey(const ValueKey('tab-a'), skipOffstage: false),
      findsOneWidget,
    );

    // 切换时左栏尺寸、位置保持原样。
    await tester.pumpWidget(layout(['b', 'a']));
    await tester.pumpAndSettle();
    expectFeedAndTab('a');

    // 关闭一个 Tab 仍不影响左侧信息流。
    await tester.pumpWidget(layout(['b']));
    await tester.pumpAndSettle();
    expectFeedAndTab('b');
  });

  testWidgets('detail slot paints an opaque scaffold background', (
    tester,
  ) async {
    // detail 为 null 时显示默认空态——detail 槽必须自带铺底,否则桌面
    // acrylic/mica 半透明窗口下会透出底层,与左栏 Scaffold 形成色差断层。
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TranslationProvider(
        child: const MaterialApp(
          home: Scaffold(
            body: MasterDetailLayout(
              master: ColoredBox(
                key: ValueKey('master-content'),
                color: Colors.blue,
              ),
            ),
          ),
        ),
      ),
    );

    // 空态本体使用统一组件
    expect(find.byType(MasterDetailEmptyState), findsOneWidget);

    // 空态槽和胶片带底通过 PageBackdrop 铺底，未启用背景时填页面底色。
    final context = tester.element(find.byType(MasterDetailEmptyState));
    final expected = Theme.of(context).scaffoldBackgroundColor;
    final backdrop = find.ancestor(
      of: find.byType(MasterDetailEmptyState),
      matching: find.byType(PageBackdrop),
    );
    expect(backdrop, findsWidgets);
    final fill = find.descendant(
      of: backdrop,
      matching: find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == expected,
      ),
    );
    expect(fill, findsWidgets);
  });
}
