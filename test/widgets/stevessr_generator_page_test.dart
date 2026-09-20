import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/models/stevessr_render_params.dart';
import 'package:fluxdo/pages/stevessr_generator_page.dart';
import 'package:fluxdo/widgets/stevessr/stevessr_canvas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('生成器页面显示预览和基础控件', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          home: const StevessrGeneratorPage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('表情包生成器'), findsOneWidget);
    expect(find.text('气泡内容'), findsOneWidget);
    expect(find.byType(StevessrCanvas), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('选择非 StevesSR 角色时隐藏表情选择', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          home: const StevessrGeneratorPage(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byType(DropdownButtonFormField<StevessrExpression>),
      findsOneWidget,
    );
    final characterDropdown = find.byType(
      DropdownButtonFormField<StevessrCharacter>,
    );
    await tester.ensureVisible(characterDropdown);
    await tester.pump();
    await tester.tap(characterDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('博丽灵梦').last);
    await tester.pump();

    expect(
      find.byType(DropdownButtonFormField<StevessrExpression>),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('嵌入编辑器模式显示生成并插入按钮', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          home: StevessrGeneratorPage(onInsert: (_) async {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('生成并插入'), findsOneWidget);
    expect(find.byIcon(Icons.add_photo_alternate_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('画布支持所有气泡、表情和尾巴方向', (tester) async {
    final boundaryKey = GlobalKey();
    var params = StevessrRenderParams.defaults();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StevessrCanvas(
              params: params,
              logicalWidth: 320,
              repaintBoundaryKey: boundaryKey,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final expression in StevessrExpression.values) {
      for (final bubble in StevessrBubble.values) {
        for (final tail in StevessrTail.values) {
          params = params.copyWith(
            expression: expression,
            bubble: bubble,
            tail: tail,
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: StevessrCanvas(
                    params: params,
                    logicalWidth: 320,
                    repaintBoundaryKey: boundaryKey,
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.byType(StevessrCanvas), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('画布支持所有 touhou 角色并回退表情素材', (tester) async {
    final boundaryKey = GlobalKey();
    var params = StevessrRenderParams.defaults();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StevessrCanvas(
              params: params,
              logicalWidth: 320,
              repaintBoundaryKey: boundaryKey,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final character in StevessrCharacter.values) {
      params = params.copyWith(character: character);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: StevessrCanvas(
                params: params,
                logicalWidth: 320,
                repaintBoundaryKey: boundaryKey,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(StevessrCanvas), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    // original 角色（默认）回退到表情素材，画布仍正常渲染。
    final original = StevessrRenderParams.defaults();
    expect(original.character, StevessrCharacter.original);
  });
}
