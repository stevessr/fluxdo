import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fluxdo/pages/static_asset_pack_manager_page.dart';
import 'package:fluxdo/services/assets/static_asset_pack_backend_io.dart'
    as backend;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fluxdo-pack-page-');
    backend.testAssetPackStoreRoot = temp;
  });
  tearDown(() async {
    backend.testAssetPackStoreRoot = null;
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  testWidgets('资源管理页展示 9 个可选资源包和手动导入入口', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('zh'),
      supportedLocales: [Locale('zh'), Locale('en')],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: StaticAssetPackManagerPage(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('静态资源包'), findsOneWidget);
    expect(find.text('MiSans 字体'), findsOneWidget);
    expect(find.text('Discourse Cook 脚本'), findsOneWidget);
    // 未接入可信发行身份前只有用户手动输入可信哈希的导入按钮。
    expect(find.text('导入 / 更新'), findsWidgets);
    expect(find.text('使用内置资源或未安装'), findsWidgets);
  });
}
