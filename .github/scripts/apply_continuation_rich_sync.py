from pathlib import Path

path = Path("lib/widgets/post/reply_sheet.dart")
s = path.read_text()


def replace_once(old: str, new: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"expected one match, got {count}: {old[:180]!r}")
    s = s.replace(old, new, 1)


replace_once(
    """  String? _buildContinuationPrefix() {
""",
    """  Future<void> _replaceComposerContent(String content) async {
    final restoreRich =
        ref.read(preferencesProvider).useRichComposer && !_richFallback;
    if (restoreRich) {
      // RichComposer 只在挂载时从 controller 导入。转换动作若仅修改
      // controller，仍在屏幕上的 WYSIWYG 文档会在下一次 flush 时把回链
      // 覆盖掉。因此先卸载并等待其 dispose flush，再写入并重新挂载。
      _richKey.currentState?.flushToController();
      setState(() => _richFallback = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }

    _contentController.value = TextEditingValue(
      text: content,
      selection: TextSelection.collapsed(offset: content.length),
    );

    if (restoreRich && mounted) {
      setState(() => _richFallback = false);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  String _escapeContinuationLinkText(String value) {
    // 对齐 Discourse escapeExpression，再保留当前 Markdown 链接文本对 ]
    // 的转义，避免标题本身含方括号时截断链接。
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;')
        .replaceAll(']', r'\\]');
  }

  String? _buildContinuationPrefix() {
""",
)

replace_once(
    """    final postNumber = _replyToPost?.postNumber;
    final sourcePath = postNumber != null && postNumber > 0
        ? '/t/-/$topicId/$postNumber'
        : '/t/-/$topicId';
    final escapedTitle = topicTitle.replaceAll(']', r'\\]');
""",
    """    // Discourse ComposerActionState 保留打开 composer 时的 post snapshot；
    // 即使用户先切到“回复话题”再转为新话题/私信，继续讨论链接仍应
    // 指向最初回复的楼层，而不是被可变的当前 action 清空。
    final postNumber = widget.replyToPost?.postNumber;
    final sourcePath = postNumber != null && postNumber > 0
        ? '/t/-/$topicId/$postNumber'
        : '/t/-/$topicId';
    final escapedTitle = _escapeContinuationLinkText(topicTitle);
""",
)

replace_once(
    """  String _contentWithContinuation(String content) {
    final prefix = _buildContinuationPrefix();
    if (prefix == null || prefix.isEmpty) return content;
    return content.isEmpty ? prefix : '$prefix\\n\\n$content';
  }

  void _applySyntheticContinuation() {
    final prefix = _buildContinuationPrefix();
    if (prefix == null || prefix.isEmpty) return;
    final current = _contentController.text;
    final next = current.isEmpty ? prefix : '$prefix\\n\\n$current';
    _syntheticContinuationPrefix = prefix;
    _contentController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _removeSyntheticContinuation() {
""",
    """  String _contentWithContinuation(String content) {
    final prefix = _buildContinuationPrefix();
    // 对齐 Discourse composer.open：已含同一 prependText 时不重复插入。
    if (prefix == null || prefix.isEmpty || content.contains(prefix)) {
      return content;
    }
    return content.isEmpty ? prefix : '$prefix\\n\\n$content';
  }

  Future<void> _applySyntheticContinuation() async {
    final prefix = _buildContinuationPrefix();
    if (prefix == null || prefix.isEmpty) return;
    final current = _contentController.text;
    if (current.contains(prefix)) {
      // 不是本次 action 切换插入的内容，切回回复时也不应擅自删除。
      _syntheticContinuationPrefix = null;
      return;
    }
    final next = current.isEmpty ? prefix : '$prefix\\n\\n$current';
    _syntheticContinuationPrefix = prefix;
    await _replaceComposerContent(next);
  }

  Future<void> _removeSyntheticContinuation() async {
""",
)

replace_once(
    """    if (next == current) return;
    _contentController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }
""",
    """    if (next == current) return;
    await _replaceComposerContent(next);
  }
""",
)

replace_once(
    """    if (!mounted) return;
    _removeSyntheticContinuation();

    setState(() {
""",
    """    if (!mounted) return;
    await _removeSyntheticContinuation();
    if (!mounted) return;

    setState(() {
""",
)

replace_once(
    """    if (!mounted) return;
    _applySyntheticContinuation();

    setState(() {
""",
    """    if (!mounted) return;
    await _applySyntheticContinuation();
    if (!mounted) return;

    setState(() {
""",
)

path.write_text(s)
