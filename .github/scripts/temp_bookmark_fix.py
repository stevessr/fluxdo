from pathlib import Path
import re


def regex_once(path: str, pattern: str, replacement: str) -> None:
    p = Path(path)
    s = p.read_text()
    out, count = re.subn(pattern, replacement, s, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one regex match, found {count}")
    p.write_text(out)


# BookmarksPage: construct the ref-backed shortcut binding only on desktop.
path = "lib/pages/bookmarks_page.dart"
regex_once(
    path,
    r"  late final ShortcutScopeBinding _shortcutScopeBinding = ShortcutScopeBinding\(\n.*?\n  \);\n\n  @override\n  void initState\(\) \{\n    super\.initState\(\);\n    if \(PlatformUtils\.isDesktop\) \{\n      WidgetsBinding\.instance\.addPostFrameCallback\(\(_\) \{\n        if \(!mounted\) return;\n        _shortcutScopeBinding\.register\(context, \{",
    """  ShortcutScopeBinding? _shortcutScopeBinding;

  @override
  void initState() {
    super.initState();
    if (PlatformUtils.isDesktop) {
      _shortcutScopeBinding = ShortcutScopeBinding(
        ref: ref,
        scope: ShortcutScope.context,
        // 底栏 tab 形态挂在 IndexedStack 里:不活跃时注册失效,否则截胡
        // 其他 tab 的 ESC(共享根路由,路由过滤分不出活跃 tab)。
        enabled: () => widget.isActive,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _shortcutScopeBinding?.register(context, {""",
)
regex_once(
    path,
    r"    _shortcutScopeBinding\.dispose\(\);",
    """    _shortcutScopeBinding?.dispose();
    _shortcutScopeBinding = null;""",
)

# Canvas-only cards already precompute this label; expose it to accessibility.
path = "lib/widgets/topic/painted_topic_card.dart"
regex_once(
    path,
    r"    if \(layout\.band != null\) \{\n      card = ClipRRect\(borderRadius: cardRadius, child: card\);\n    \}\n    return Padding\(padding: const EdgeInsets\.only\(bottom: 8\), child: card\);",
    """    if (layout.band != null) {
      card = ClipRRect(borderRadius: cardRadius, child: card);
    }
    card = Semantics(
      label: layout.semanticsLabel,
      button: widget.onTap != null,
      child: card,
    );
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: card);""",
)

# Bookmarks list tests follow the PaintedTopicCard/layout contract.
path = "test/pages/bookmarks/bookmarks_list_content_test.dart"
regex_once(
    path,
    r"import 'package:fluxdo/widgets/bookmark/bookmarks_list_content\.dart';",
    """import 'package:fluxdo/widgets/bookmark/bookmarks_list_content.dart';
import 'package:fluxdo/widgets/topic/painted_topic_card.dart';""",
)
regex_once(
    path,
    r"Topic _topic\(\{required int id, required String title, String\? bookmarkName\}\) \{",
    """Finder _findPaintedTopic(String title) => find.byWidgetPredicate(
  (widget) =>
      widget is PaintedTopicCard &&
      widget.layout.semanticsLabel.split(',').first.trim() == title,
);

Topic _topic({required int id, required String title, String? bookmarkName}) {""",
)
p = Path(path)
s = p.read_text()
for title in ["Alpha", "Beta", "Gamma", "No Name 1", "No Name 2"]:
    s = s.replace(f"find.text('{title}')", f"_findPaintedTopic('{title}')")
p.write_text(s)

# Bookmarks page test helper finds the canvas card; workspace Text tests stay Text-based.
path = "test/pages/bookmarks/bookmarks_page_test.dart"
regex_once(
    path,
    r"import 'package:fluxdo/widgets/bookmark/bookmarks_workspace_tab_bar\.dart';",
    """import 'package:fluxdo/widgets/bookmark/bookmarks_workspace_tab_bar.dart';
import 'package:fluxdo/widgets/topic/painted_topic_card.dart';""",
)
regex_once(
    path,
    r"Finder _findBookmarkInList\(String title\) \{\n  return find\.descendant\(\n    of: find\.byType\(BookmarksListContent\),\n    matching: find\.text\(title\),\n  \);\n\}",
    """Finder _findBookmarkInList(String title) {
  return find.descendant(
    of: find.byType(BookmarksListContent),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is PaintedTopicCard &&
          widget.layout.semanticsLabel.split(',').first.trim() == title,
    ),
  );
}""",
)
