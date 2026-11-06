import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/stevessr_render_params.dart';
import 'package:fluxdo/services/stevessr_text_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('保留显式换行并在气泡内适配字号', (tester) async {
    final result = StevessrTextLayout.fit(
      text: '第一行\n第二行',
      box: const StevessrRect(x: 0, y: 0, width: 400, height: 240),
      padding: 24,
      minFont: 20,
      maxFont: 72,
      lineHeight: 1.15,
      font: StevessrFont.sans,
      fontWeight: 600,
    );

    expect(result.lines, ['第一行', '第二行']);
    expect(result.overflow, isFalse);
    expect(result.fontSize, inInclusiveRange(20, 72));
    expect(result.totalHeight, greaterThan(0));
    await tester.pump();
  });

  testWidgets('长文本会逐步降低字号，仍放不下时标记溢出', (tester) async {
    final result = StevessrTextLayout.fit(
      text: List<String>.filled(80, '超长文字').join(),
      box: const StevessrRect(x: 0, y: 0, width: 120, height: 80),
      padding: 12,
      minFont: 20,
      maxFont: 72,
      lineHeight: 1.15,
      font: StevessrFont.sans,
      fontWeight: 400,
    );

    expect(result.fontSize, 20);
    expect(result.overflow, isTrue);
    expect(result.lines.length, greaterThan(1));
    await tester.pump();
  });

  testWidgets('换行不会拆开 ZWJ emoji 序列', (tester) async {
    final lines = StevessrTextLayout.wrapText(
      '👩‍💻',
      maxWidth: 1000,
      fontSize: 32,
      font: StevessrFont.sans,
      fontWeight: 400,
    );

    expect(lines, ['👩‍💻']);
    await tester.pump();
  });

  testWidgets('空段落会保留为空行', (tester) async {
    final lines = StevessrTextLayout.wrapText(
      '上\n\n下',
      maxWidth: 1000,
      fontSize: 32,
      font: StevessrFont.sans,
      fontWeight: 400,
    );

    expect(lines, ['上', '', '下']);
    await tester.pump();
  });
}
