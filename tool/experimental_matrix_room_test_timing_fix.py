from pathlib import Path

path = Path('test/pages/chat/matrix_room_page_test.dart')
text = path.read_text()
old = "    await tester.tap(find.text('1 条线程回复'));\n    await tester.pump();\n    expect(find.textContaining('Thread ·'), findsOneWidget);\n"
new = "    await tester.tap(find.text('1 条线程回复'));\n    await tester.pumpAndSettle();\n    expect(find.textContaining('Thread ·'), findsOneWidget);\n"
if text.count(old) != 1:
    raise SystemExit(f'route enter timing: expected one match, got {text.count(old)}')
text = text.replace(old, new, 1)

old = "    navigator.pop();\n    await tester.pump();\n    await tester.pump();\n\n    // Returning performs one immediate latest refresh and restarts the timer.\n"
new = "    navigator.pop();\n    await tester.pumpAndSettle();\n\n    // Returning performs one immediate latest refresh and restarts the timer.\n"
if text.count(old) != 1:
    raise SystemExit(f'route exit timing: expected one match, got {text.count(old)}')
text = text.replace(old, new, 1)
path.write_text(text)
print('Matrix room route test timing fix staged successfully')
