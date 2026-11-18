import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/markdown_editor/composer_special_content.dart';

void main() {
  test('AI 内容的三种插入格式与站点语法一致', () {
    expect(
      buildComposerSpecialSnippet('aiCode').markdown,
      '```javascript ai\n// AI content\n```',
    );
    expect(
      buildComposerSpecialSnippet('aiQuote').markdown,
      '> [!AI]\n> AI content',
    );
    expect(
      buildComposerSpecialSnippet('aiDetails').markdown,
      '[details="AI content" ai]\nAI content\n[/details]',
    );
  });

  test('滚动内容和 Mermaid 保留官方标记与语言标识', () {
    expect(
      buildComposerSpecialSnippet('scroll').markdown,
      '<div data-theme-scrollable="true">\n滚动内容\n</div>',
    );
    expect(
      buildComposerSpecialSnippet('mermaid').markdown,
      '```mermaid\nflowchart TD\n  A[开始] --> B[结束]\n```',
    );
  });

  test('选择文字时替换占位内容并保持结构', () {
    expect(
      buildComposerSpecialSnippet('aiCode', selectedText: 'const a = 1;')
          .markdown,
      '```javascript ai\nconst a = 1;\n```',
    );
    expect(
      buildComposerSpecialSnippet('aiQuote', selectedText: '第一行\n第二行')
          .markdown,
      '> [!AI]\n> 第一行\n> 第二行',
    );
    expect(
      buildComposerSpecialSnippet('scroll', selectedText: '自定义内容')
          .markdown,
      '<div data-theme-scrollable="true">\n自定义内容\n</div>',
    );
    expect(
      buildComposerSpecialSnippet('mermaid', selectedText: 'sequenceDiagram')
          .markdown,
      '```mermaid\nsequenceDiagram\n```',
    );
  });
}
