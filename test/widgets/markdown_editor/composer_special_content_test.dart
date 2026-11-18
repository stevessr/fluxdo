import 'package:flutter/material.dart';
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

  test('AI Details 的占位选区必须落在正文而不是标题', () {
    final next = applyComposerSpecialContent(
      text: '',
      selection: const TextSelection.collapsed(offset: 0),
      kind: 'aiDetails',
    );
    expect(
      next.text,
      '[details="AI content" ai]\\nAI content\\n[/details]',
    );
    expect(next.selection.textInside(next.text), 'AI content');
    expect(next.selection.start, greaterThan(next.text.indexOf('ai]')));
  });

  test('扩展菜单用选中文字替换正文，且不覆盖两侧已有内容', () {
    final next = applyComposerSpecialContent(
      text: '之前 中间 之后',
      selection: const TextSelection(baseOffset: 3, extentOffset: 5),
      kind: 'mermaid',
    );
    expect(next.text, '之前 \n```mermaid\n中间\n```\n 之后');
    expect(next.selection.isCollapsed, isTrue);
    expect(next.selection.extentOffset, '之前 \n```mermaid\n中间\n```\n'.length);
  });

  test('没有有效选区时安全追加到末尾', () {
    final next = applyComposerSpecialContent(
      text: '原文',
      selection: const TextSelection.collapsed(offset: -1),
      kind: 'scroll',
    );
    expect(next.text, contains('原文\n<div data-theme-scrollable="true">'));
    expect(next.selection.textInside(next.text), '滚动内容');
  });

}
