import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/markdown_editor/editor_tools.dart';
import 'package:fluxdo/widgets/markdown_editor/rich_composer/rich_editor_tools.dart';

void main() {
  test('源码快捷栏为旧偏好补入 StevesSR', () {
    final ids = resolveVisibleTools(const [
      'bold',
      'image',
    ]).map((tool) => tool.id).toList();

    expect(ids, contains('stevessr'));
    expect(ids.where((id) => id == 'stevessr'), hasLength(1));
  });

  test('富文本快捷栏为旧偏好补入 StevesSR', () {
    final ids = resolveVisibleRichTools(const [
      'bold',
      'image',
    ]).map((tool) => tool.id).toList();

    expect(ids, contains('stevessr'));
    expect(ids.where((id) => id == 'stevessr'), hasLength(1));
  });
}
