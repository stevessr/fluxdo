import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/stevessr_render_params.dart';
import 'package:fluxdo/widgets/stevessr/stevessr_interactive_preview.dart';

void main() {
  test('常用小尺寸可以选择，矩形会按新画布范围归一化', () {
    final result = StevessrRenderParams.defaults().copyWith(
      width: 128,
      height: 256,
      bubbleRect: const StevessrRect(x: 10, y: 10, width: 48, height: 48),
      characterRect: const StevessrRect(x: 42, y: 70, width: 76, height: 100),
    );
    expect(result.width, 128);
    expect(result.height, 256);
    expect(result.bubbleRect.width, 48);
    expect(result.characterRect.height, 100);
  });

  testWidgets('拖拽角色和气泡会修改导出坐标，缩放画布只修改视图', (tester) async {
    var params = StevessrRenderParams.defaults().copyWith(
      width: 512,
      height: 512,
      bubbleRect: const StevessrRect(x: 30, y: 30, width: 220, height: 140),
      characterRect: const StevessrRect(
        x: 150,
        y: 220,
        width: 270,
        height: 270,
      ),
    );
    final initialCharacter = params.characterRect;
    final initialBubble = params.bubbleRect;
    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 440,
              height: 560,
              child: StatefulBuilder(
                builder: (context, update) => StevessrInteractivePreview(
                  params: params,
                  logicalWidth: 400,
                  repaintBoundaryKey: boundaryKey,
                  onCharacterRectChanged: (rect) => update(
                    () => params = params.copyWith(characterRect: rect),
                  ),
                  onBubbleRectChanged: (rect) =>
                      update(() => params = params.copyWith(bubbleRect: rect)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final overlay = find.byKey(const ValueKey('stevessr-element-overlay'));
    expect(overlay, findsOneWidget);
    // Drag the character by its interior rather than by its corner handle.
    await tester.dragFrom(
      tester.getCenter(overlay) - const Offset(28, 28),
      const Offset(32, 16),
    );
    await tester.pump();
    expect(params.characterRect.x, greaterThan(initialCharacter.x));
    expect(params.characterRect.y, greaterThan(initialCharacter.y));
    expect(params.bubbleRect, initialBubble);

    final beforeResize = params.characterRect;
    await tester.drag(
      find.byKey(const ValueKey('stevessr-element-resize')),
      const Offset(-32, -32),
    );
    await tester.pump();
    expect(params.characterRect.width, lessThan(beforeResize.width));
    expect(params.characterRect.height, lessThan(beforeResize.height));

    await tester.tap(find.text('气泡'));
    await tester.pump();
    final beforeBubble = params.bubbleRect;
    await tester.dragFrom(
      tester.getCenter(overlay) - const Offset(30, 20),
      const Offset(24, 12),
    );
    await tester.pump();
    expect(params.bubbleRect.x, greaterThan(beforeBubble.x));

    // The selection chrome is a sibling, not a descendant, of the export
    // RepaintBoundary and therefore cannot appear in generated images.
    expect(
      find.descendant(of: find.byKey(boundaryKey), matching: overlay),
      findsNothing,
    );

    await tester.tap(find.text('画布'));
    await tester.pump();
    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const ValueKey('stevessr-viewport')),
    );
    final transform = viewer.transformationController!;
    final previousCharacter = params.characterRect;
    final previousBubble = params.bubbleRect;
    final oldTranslation = transform.value.getTranslation();
    await tester.drag(
      find.byKey(const ValueKey('stevessr-viewport')),
      const Offset(30, 20),
    );
    await tester.pump();
    expect(transform.value.getTranslation().x, isNot(oldTranslation.x));
    expect(params.characterRect, previousCharacter);
    expect(params.bubbleRect, previousBubble);
  });
}
