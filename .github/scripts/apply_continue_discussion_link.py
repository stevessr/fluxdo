from pathlib import Path
import json
import re

reply_path = Path("lib/widgets/post/reply_sheet.dart")
s = reply_path.read_text()


def replace_once(old: str, new: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"expected one match, got {count}: {old[:160]!r}")
    s = s.replace(old, new, 1)


replace_once(
    "import '../../utils/dialog_utils.dart';\n",
    "import '../../utils/dialog_utils.dart';\nimport '../../utils/url_helper.dart';\n",
)

replace_once(
    """  void _onRecipientsChanged(List<String> recipients) {
    setState(() => _recipients = recipients);
    _onContentChanged();
  }

  Future<void> _dropCurrentDraftForConversion() async {
""",
    """  void _onRecipientsChanged(List<String> recipients) {
    setState(() => _recipients = recipients);
    _onContentChanged();
  }

  String _escapeDiscourseLinkText(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  String? _continuedDiscussionText() {
    final topicId = widget.topicId;
    final title = widget.topicTitle?.trim();
    if (topicId == null || title == null || title.isEmpty) return null;

    // 对齐 Discourse ComposerActionState#continuedFromText：如果最初是
    // 回复某楼，优先回链该楼；否则链接到话题首帖。Discourse 原生支持
    // /t/:topic_id/:post_number 的无 slug 短路由。
    final postNumber = widget.replyToPost?.postNumber ?? 1;
    final url = UrlHelper.resolveUrl('/t/$topicId/$postNumber');
    final link = '[${_escapeDiscourseLinkText(title)}]($url)';
    return context.l10n.post_continueDiscussion(link);
  }

  String _withContinuedDiscussionPrefix(String content) {
    final prefix = _continuedDiscussionText();
    // Discourse composer.open 同样用 includes 防重复 prepend。
    if (prefix == null || prefix.isEmpty || content.contains(prefix)) {
      return content;
    }
    final normalized = prefix.trim();
    return content.isEmpty ? normalized : '$normalized\\n\\n$content';
  }

  Future<void> _replaceComposerContent(String content) async {
    final restoreRich =
        ref.read(preferencesProvider).useRichComposer && !_richFallback;
    if (restoreRich) {
      // RichComposer 初始导入是一次性的。先卸载让它在 dispose 时 flush
      // 当前文档，再改 controller，随后重挂以重新导入转换后的 Markdown。
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

  Future<void> _dropCurrentDraftForConversion() async {
""",
)

replace_once(
    """  Future<void> _switchToPrivateMessage() async {
    if (_isEditMode || widget.topicId == null) return;
    _richKey.currentState?.flushToController();
    await _dropCurrentDraftForConversion();
    if (!mounted) return;

    setState(() {
      _composePrivateMessage = true;
""",
    """  Future<void> _switchToPrivateMessage() async {
    if (_isEditMode || widget.topicId == null) return;
    _richKey.currentState?.flushToController();
    final convertedContent = _withContinuedDiscussionPrefix(
      _contentController.text,
    );
    await _dropCurrentDraftForConversion();
    if (!mounted) return;

    await _replaceComposerContent(convertedContent);
    if (!mounted) return;

    setState(() {
      _composePrivateMessage = true;
""",
)

replace_once(
    """  Future<void> _convertToNewTopic() async {
    if (_isEditMode) return;
    _richKey.currentState?.flushToController();
    final content = _contentController.text;
""",
    """  Future<void> _convertToNewTopic() async {
    if (_isEditMode) return;
    _richKey.currentState?.flushToController();
    final content = _withContinuedDiscussionPrefix(_contentController.text);
""",
)

reply_path.write_text(s)

translations = {
    "lib/l10n/modules/post/post_en.arb": "Continuing the discussion from {postLink}:",
    "lib/l10n/modules/post/post_zh.arb": "从{postLink}继续讨论：",
    "lib/l10n/modules/post/post_zh_TW.arb": "繼續 {postLink} 的討論:",
    "lib/l10n/modules/post/post_zh_HK.arb": "繼續 {postLink} 的討論：",
}

anchor_pattern = re.compile(r'(?m)^(  "post_replyToTopic": .+,\n)')
for filename, value in translations.items():
    path = Path(filename)
    text = path.read_text()
    if '"post_continueDiscussion"' in text:
        raise SystemExit(f"translation already exists: {filename}")
    matches = anchor_pattern.findall(text)
    if len(matches) != 1:
        raise SystemExit(
            f"expected one post_replyToTopic anchor, got {len(matches)}: {filename}"
        )
    payload = (
        f'  "post_continueDiscussion": {json.dumps(value, ensure_ascii=False)},\n'
        '  "@post_continueDiscussion": {\n'
        '    "placeholders": {\n'
        '      "postLink": {\n'
        '        "type": "String"\n'
        '      }\n'
        '    }\n'
        '  },\n'
    )
    text = anchor_pattern.sub(lambda match: match.group(1) + payload, text, count=1)
    path.write_text(text)
