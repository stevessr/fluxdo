from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    s = p.read_text()
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one marker, found {count}: {old[:100]!r}")
    p.write_text(s.replace(old, new, 1))


# BookmarksPage: construct the ref-backed shortcut binding only on desktop.
path = "lib/pages/bookmarks_page.dart"
replace_once(
    path,
    """  late final ShortcutScopeBinding _shortcutScopeBinding = ShortcutScopeBinding(
    ref: ref,
    scope: ShortcutScope.context,
    // 底栏 tab 形态挂在 IndexedStack 里:不活跃时注册失效,否则截胡
    // 其他 tab 的 ESC(共享根路由,路由过滤分不出活跃 tab)。
    enabled: () => widget.isActive,
  );
""",
    """  ShortcutScopeBinding? _shortcutScopeBinding;
""",
)
replace_once(
    path,
    """    if (PlatformUtils.isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _shortcutScopeBinding.register(context, {
""",
    """    if (PlatformUtils.isDesktop) {
      _shortcutScopeBinding = ShortcutScopeBinding(
        ref: ref,
        scope: ShortcutScope.context,
        // 底栏 tab 形态挂在 IndexedStack 里:不活跃时注册失效,否则截胡
        // 其他 tab 的 ESC(共享根路由,路由过滤分不出活跃 tab)。
        enabled: () => widget.isActive,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _shortcutScopeBinding?.register(context, {
""",
)
replace_once(
    path,
    """    _shortcutScopeBinding.dispose();
""",
    """    _shortcutScopeBinding?.dispose();
    _shortcutScopeBinding = null;
""",
)

# Canvas-only cards already precompute this label; expose it to accessibility.
path = "lib/widgets/topic/painted_topic_card.dart"
replace_once(
    path,
    """    if (layout.band != null) {
      card = ClipRRect(borderRadius: cardRadius, child: card);
    }
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: card);
""",
    """    if (layout.band != null) {
      card = ClipRRect(borderRadius: cardRadius, child: card);
    }
    card = Semantics(
      label: layout.semanticsLabel,
      button: widget.onTap != null,
      child: card,
    );
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: card);
""",
)

# Bookmarks list tests follow the PaintedTopicCard/layout contract.
path = "test/pages/bookmarks/bookmarks_list_content_test.dart"
replace_once(
    path,
    "import 'package:fluxdo/widgets/bookmark/bookmarks_list_content.dart';\n",
    "import 'package:fluxdo/widgets/bookmark/bookmarks_list_content.dart';\nimport 'package:fluxdo/widgets/topic/painted_topic_card.dart';\n",
)
replace_once(
    path,
    "Topic _topic({required int id, required String title, String? bookmarkName}) {\n",
    """Finder _findPaintedTopic(String title) => find.byWidgetPredicate(
  (widget) =>
      widget is PaintedTopicCard &&
      widget.layout.semanticsLabel.split(',').first.trim() == title,
);

Topic _topic({required int id, required String title, String? bookmarkName}) {
""",
)
p = Path(path)
s = p.read_text()
for title in ["Alpha", "Beta", "Gamma", "No Name 1", "No Name 2"]:
    s = s.replace(f"find.text('{title}')", f"_findPaintedTopic('{title}')")
p.write_text(s)

# Bookmarks page test helper finds the canvas card; workspace Text tests stay Text-based.
path = "test/pages/bookmarks/bookmarks_page_test.dart"
replace_once(
    path,
    "import 'package:fluxdo/widgets/bookmark/bookmarks_workspace_tab_bar.dart';\n",
    "import 'package:fluxdo/widgets/bookmark/bookmarks_workspace_tab_bar.dart';\nimport 'package:fluxdo/widgets/topic/painted_topic_card.dart';\n",
)
replace_once(
    path,
    """Finder _findBookmarkInList(String title) {
  return find.descendant(
    of: find.byType(BookmarksListContent),
    matching: find.text(title),
  );
}
""",
    """Finder _findBookmarkInList(String title) {
  return find.descendant(
    of: find.byType(BookmarksListContent),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is PaintedTopicCard &&
          widget.layout.semanticsLabel.split(',').first.trim() == title,
    ),
  );
}
""",
)
