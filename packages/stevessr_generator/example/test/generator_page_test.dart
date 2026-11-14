import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stevessr_generator/stevessr_generator.dart';

void main() {
  testWidgets('generator page retains the host-visible Chinese labels', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(
      const MaterialApp(home: StevessrGeneratorPage()),
    );
    await tester.pump();

    expect(find.text('表情包生成器'), findsOneWidget);
    expect(find.text('默认'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('分享'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('host callbacks control insert and Linux share actions', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(
      MaterialApp(
        home: StevessrGeneratorPage(
          onInsert: (_) async {},
          onShare: (_) async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('生成并插入'), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });
}
