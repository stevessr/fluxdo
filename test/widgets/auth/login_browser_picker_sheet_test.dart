import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/system_browser_service.dart';
import 'package:fluxdo/widgets/auth/login_browser_picker_sheet.dart';

void main() {
  Future<LoginBrowser?> showPicker(
    WidgetTester tester,
    List<LoginBrowser> browsers,
  ) async {
    LoginBrowser? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showModalBottomSheet<LoginBrowser>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => LoginBrowserPickerSheet(browsers: browsers),
                );
              },
              child: const Text('打开浏览器选择器'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开浏览器选择器'));
    await tester.pumpAndSettle();
    return selected;
  }

  testWidgets('显示浏览器对应图标，系统打开方式在长列表底部仍可操作', (tester) async {
    final browsers = [
      LoginBrowser(
        id: 'com.android.chrome',
        name: 'Google Chrome',
        iconBytes: Uint8List.fromList([137, 80, 78, 71]),
      ),
      for (var i = 0; i < 30; i++)
        LoginBrowser(id: 'browser.$i', name: '测试浏览器 $i'),
      const LoginBrowser(
        id: SystemBrowserService.androidChooserId,
        name: '使用系统方式打开',
      ),
    ];
    LoginBrowser? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('打开'),
              onPressed: () async {
                selected = await showModalBottomSheet<LoginBrowser>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => LoginBrowserPickerSheet(browsers: browsers),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('Google Chrome'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    expect(find.text('使用系统方式打开'), findsOneWidget);
    await tester.tap(find.text('使用系统方式打开'));
    await tester.pumpAndSettle();
    expect(selected?.id, SystemBrowserService.androidChooserId);
  });

  testWidgets('未发现浏览器时仍提供系统打开方式', (tester) async {
    const browser = LoginBrowser(
      id: SystemBrowserService.androidChooserId,
      name: '使用系统方式打开',
    );
    await showPicker(tester, [browser]);
    expect(find.text('没有找到可直接选择的浏览器，可尝试系统打开方式。'), findsOneWidget);
    expect(find.text('使用系统方式打开'), findsOneWidget);
  });

  testWidgets('点击具体浏览器返回正确包名，关闭弹窗不创建选择', (tester) async {
    final selected = <LoginBrowser?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('打开'),
              onPressed: () async {
                selected.add(
                  await showModalBottomSheet<LoginBrowser>(
                    context: context,
                    showDragHandle: true,
                    builder: (_) => const LoginBrowserPickerSheet(
                      browsers: [
                        LoginBrowser(
                          id: 'com.android.chrome',
                          name: 'Google Chrome',
                        ),
                        LoginBrowser(
                          id: SystemBrowserService.androidChooserId,
                          name: '使用系统方式打开',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Chrome'));
    await tester.pumpAndSettle();
    expect(selected.single?.id, 'com.android.chrome');

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(selected, hasLength(2));
    expect(selected.last, isNull);
  });
}
