import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/models/sticker.dart';
import 'package:fluxdo/widgets/markdown_editor/picker_search_header.dart';
import 'package:fluxdo/widgets/markdown_editor/sticker_preview.dart';
import 'package:fluxdo/widgets/markdown_editor/sticker_search_view.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('sticker name matching excludes filename extension', () {
    expect(StickerSearchView.plainName('猫猫叹气.gif'), '猫猫叹气');
  });

  testWidgets('inline sticker search displays matches and sends selection', (
    tester,
  ) async {
    const item = StickerItem(
      id: 'item',
      name: '猫猫叹气.gif',
      url: 'https://sticker-search.invalid/item.gif',
      width: 200,
      height: 100,
      groupId: 'group',
    );
    StickerItem? selected;
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            body: StickerSearchView(
              search: (query) => item.name.contains(query)
                  ? const [StickerSearchSection('猫猫', [item])]
                  : const [],
              onSelected: (value) => selected = value,
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.byType(PickerSearchInlineHeader), findsOneWidget);
    await tester.enterText(find.byType(TextField), '叹气');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(StickerGridCell), findsOneWidget);
    await tester.tap(find.byType(StickerGridCell));
    await tester.pump();
    expect(selected, same(item));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
