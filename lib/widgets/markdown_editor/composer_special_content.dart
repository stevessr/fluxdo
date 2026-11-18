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

/// 统一处理编辑器源码选区，预留块级换行并准确定位可替换的正文占位符。
TextEditingValue applyComposerSpecialContent({
  required String text,
  required TextSelection selection,
  required String kind,
}) {
  final range = selection.isValid && selection.end <= text.length
      ? selection
      : TextSelection.collapsed(offset: text.length);
  final start = range.start;
  final end = range.end;
  final selectedText = text.substring(start, end);
  final snippet = buildComposerSpecialSnippet(
    kind,
    selectedText: selectedText,
  );
  final prefix = start > 0 && text[start - 1] != '\n' ? '\n' : '';
  final suffix = end < text.length && text[end] != '\n' ? '\n' : '';
  final inserted = '$prefix${snippet.markdown}$suffix';
  final updated = text.replaceRange(start, end, inserted);

  // details 标题和正文有相同占位字样：必须匹配最后一次出现的位置。
  final editableIndex = selectedText.isEmpty
      ? snippet.markdown.lastIndexOf(snippet.editableContent)
      : -1;
  final updatedSelection = editableIndex >= 0
      ? TextSelection(
          baseOffset: start + prefix.length + editableIndex,
          extentOffset: start +
              prefix.length +
              editableIndex +
              snippet.editableContent.length,
        )
      : TextSelection.collapsed(offset: start + inserted.length);
  return TextEditingValue(text: updated, selection: updatedSelection);
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
