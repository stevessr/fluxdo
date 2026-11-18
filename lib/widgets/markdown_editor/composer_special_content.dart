import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import 'composer_action_menu.dart';

/// 编辑器共用的扩展内容模板，保持源码与富文本模式生成一致。
typedef ComposerSpecialSnippet = ({String markdown, String editableContent});

ComposerSpecialSnippet buildComposerSpecialSnippet(
  String kind, {
  String selectedText = '',
}) {
  final hasSelection = selectedText.isNotEmpty;
  switch (kind) {
    case 'aiCode':
      final body = hasSelection ? selectedText : '// AI content';
      return (
        markdown: '```javascript ai\n$body\n```',
        editableContent: body,
      );
    case 'aiQuote':
      final body = hasSelection ? selectedText : 'AI content';
      return (
        markdown: '> [!AI]\n> ${body.replaceAll('\n', '\n> ')}',
        editableContent: body.split('\n').first,
      );
    case 'aiDetails':
      final body = hasSelection ? selectedText : 'AI content';
      return (
        markdown: '[details="AI content" ai]\n$body\n[/details]',
        editableContent: body,
      );
    case 'scroll':
      final body = hasSelection ? selectedText : '滚动内容';
      return (
        markdown: '<div data-theme-scrollable="true">\n$body\n</div>',
        editableContent: body,
      );
    case 'mermaid':
      final body = hasSelection
          ? selectedText
          : 'flowchart TD\n  A[开始] --> B[结束]';
      return (
        markdown: '```mermaid\n$body\n```',
        editableContent: body,
      );
    default:
      throw ArgumentError.value(kind, 'kind', '未知扩展内容类型');
  }
}

/// 单个入口的两级菜单：AI 内容细分为 Code、Quote、Details。
Future<String?> showComposerSpecialContentMenu(BuildContext context) async {
  final s = S.current;
  final category = await showComposerActionMenu<String>(
    context: context,
    items: [
      PopupMenuItem(
        value: 'ai',
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(s.composer_aiContent)),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'scroll',
        child: Row(
          children: [
            const Icon(Icons.unfold_more_rounded, size: 20),
            const SizedBox(width: 12),
            Text(s.composer_scrollContent),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'mermaid',
        child: Row(
          children: [
            const Icon(Icons.account_tree_outlined, size: 20),
            const SizedBox(width: 12),
            Text(s.composer_mermaidChart),
          ],
        ),
      ),
    ],
  );
  if (category != 'ai' || !context.mounted) return category;
  return showComposerActionMenu<String>(
    context: context,
    items: [
      PopupMenuItem(
        value: 'aiCode',
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.code_rounded),
          title: Text(s.composer_aiCode),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        value: 'aiQuote',
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.format_quote_rounded),
          title: Text(s.composer_aiQuote),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        value: 'aiDetails',
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.expand_more_rounded),
          title: Text(s.composer_aiDetails),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ],
  );
}
