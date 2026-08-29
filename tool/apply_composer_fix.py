from pathlib import Path
import json
import re


def replace_once(path: str, old: str, new: str, label: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, got {count}")
    p.write_text(text.replace(old, new, 1))


# 1) IME: let the keyboard placeholder follow Flutter's frame-synced
# viewInsets instead of the delayed native keyboard-height callback.
replace_once(
    "lib/widgets/markdown_editor/markdown_editor.dart",
    """              case ChatBottomPanelType.keyboard:
                return _KeyboardPlaceholder(
                  color: theme.colorScheme.surface,
                  nativeKeyboardHeight: _panelController.keyboardHeight,
                );""",
    """              case ChatBottomPanelType.keyboard:
                return _KeyboardPlaceholder(
                  color: theme.colorScheme.surface,
                );""",
    "keyboard placeholder call",
)
replace_once(
    "lib/widgets/markdown_editor/markdown_editor.dart",
    """/// 键盘占位组件：使用原生键盘高度，不使用 AnimatedSize，
/// 与表情面板共用同一高度源（nativeKeyboardHeight），确保切换时等高
class _KeyboardPlaceholder extends StatelessWidget {
  final Color color;
  final double nativeKeyboardHeight;

  const _KeyboardPlaceholder({
    required this.color,
    required this.nativeKeyboardHeight,
  });

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final height = max(nativeKeyboardHeight, safeBottom);
    return ColoredBox(
      color: color,
      child: SizedBox(width: double.infinity, height: height),
    );
  }
}""",
    """/// 键盘占位只订阅 Flutter 的 viewInsets。
///
/// IME 动画的 viewInsets 与 Flutter 帧同步；原生插件上报的 keyboardHeight
/// 会经过平台通道再触发 setState，快速动画时会落后于系统键盘，视觉上就像
/// 回复框“追着键盘”缓慢上升。这里只让这个极小占位组件逐帧跟随 Insets，
/// 避免整块 Composer 使用滞后的原生高度。
class _KeyboardPlaceholder extends StatelessWidget {
  final Color color;

  const _KeyboardPlaceholder({required this.color});

  @override
  Widget build(BuildContext context) {
    final insetBottom = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final height = insetBottom > 0 ? insetBottom : safeBottom;
    return ColoredBox(
      color: color,
      child: SizedBox(width: double.infinity, height: height),
    );
  }
}""",
    "keyboard placeholder implementation",
)

# 2) Preserve Discourse PM participant data, including allowed groups.
replace_once(
    "lib/models/topic.dart",
    """  final List<TopicUser> allowedUsers;
  final bool canRemoveAllowedUsers;""",
    """  final List<TopicUser> allowedUsers;
  final List<String> allowedGroups;
  final bool canRemoveAllowedUsers;""",
    "TopicDetail allowedGroups field",
)
replace_once(
    "lib/models/topic.dart",
    """    this.allowedUsers = const [],
    this.canRemoveAllowedUsers = false,""",
    """    this.allowedUsers = const [],
    this.allowedGroups = const [],
    this.canRemoveAllowedUsers = false,""",
    "TopicDetail allowedGroups constructor",
)
replace_once(
    "lib/models/topic.dart",
    """      allowedUsers: (details['allowed_users'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((user) => TopicUser.fromJson(Map<String, dynamic>.from(user)))
          .toList(growable: false),
      canRemoveAllowedUsers: details['can_remove_allowed_users'] == true,""",
    """      allowedUsers: (details['allowed_users'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((user) => TopicUser.fromJson(Map<String, dynamic>.from(user)))
          .toList(growable: false),
      allowedGroups: (details['allowed_groups'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((group) => group['name']?.toString().trim() ?? '')
          .where((name) => name.isNotEmpty)
          .toList(growable: false),
      canRemoveAllowedUsers: details['can_remove_allowed_users'] == true,""",
    "TopicDetail allowedGroups parsing",
)
replace_once(
    "lib/models/topic.dart",
    """    List<TopicUser>? allowedUsers,
    bool? canRemoveAllowedUsers,""",
    """    List<TopicUser>? allowedUsers,
    List<String>? allowedGroups,
    bool? canRemoveAllowedUsers,""",
    "TopicDetail allowedGroups copyWith args",
)
replace_once(
    "lib/models/topic.dart",
    """      allowedUsers: allowedUsers ?? this.allowedUsers,
      canRemoveAllowedUsers:""",
    """      allowedUsers: allowedUsers ?? this.allowedUsers,
      allowedGroups: allowedGroups ?? this.allowedGroups,
      canRemoveAllowedUsers:""",
    "TopicDetail allowedGroups copyWith value",
)

# 3) Pass already-loaded PM recipients into the composer: no extra API request.
replace_once(
    "lib/pages/topic_detail_page/actions/_user_actions.dart",
    """      topicTitle: detail?.title,
      preloadedDraftFuture: preloadedDraftFuture,
      isPrivateMessageTopic: detail?.isPrivateMessage ?? false,""",
    """      topicTitle: detail?.title,
      privateMessageRecipients: detail == null
          ? const <String>[]
          : <String>{
              ...detail.allowedUsers.map((user) => user.username),
              ...detail.allowedGroups,
            }.toList(growable: false),
      preloadedDraftFuture: preloadedDraftFuture,
      isPrivateMessageTopic: detail?.isPrivateMessage ?? false,""",
    "reply caller PM recipients",
)

reply = "lib/widgets/post/reply_sheet.dart"
replace_once(
    reply,
    "import '../../utils/dialog_utils.dart';\nimport '../../providers/shortcut_provider.dart';",
    "import '../../utils/dialog_utils.dart';\nimport '../../utils/url_helper.dart';\nimport '../../providers/shortcut_provider.dart';",
    "reply sheet UrlHelper import",
)
replace_once(
    reply,
    """  bool isPrivateMessageTopic = false,
  bool isPmWithNonHumanUser = false,""",
    """  bool isPrivateMessageTopic = false,
  List<String> privateMessageRecipients = const <String>[],
  bool isPmWithNonHumanUser = false,""",
    "showReplySheet recipients argument",
)
replace_once(
    reply,
    """        isPrivateMessageTopic: isPrivateMessageTopic,
        isPmWithNonHumanUser: isPmWithNonHumanUser,""",
    """        isPrivateMessageTopic: isPrivateMessageTopic,
        privateMessageRecipients: privateMessageRecipients,
        isPmWithNonHumanUser: isPmWithNonHumanUser,""",
    "showReplySheet recipients forwarding",
)
replace_once(
    reply,
    """  final bool isPrivateMessageTopic; // 当前话题是否为私信话题
  final bool isPmWithNonHumanUser; // 当前私信话题是否包含非真人用户""",
    """  final bool isPrivateMessageTopic; // 当前话题是否为私信话题
  final List<String> privateMessageRecipients; // 原私信用户/群组，供“作为新消息回复”继承
  final bool isPmWithNonHumanUser; // 当前私信话题是否包含非真人用户""",
    "ReplySheet recipients field",
)
replace_once(
    reply,
    """    this.isPrivateMessageTopic = false,
    this.isPmWithNonHumanUser = false,""",
    """    this.isPrivateMessageTopic = false,
    this.privateMessageRecipients = const <String>[],
    this.isPmWithNonHumanUser = false,""",
    "ReplySheet recipients constructor",
)
replace_once(
    reply,
    """  Post? _replyToPost;
  bool _composePrivateMessage = false;

  bool get _isPrivateMessage => _composePrivateMessage;""",
    """  Post? _replyToPost;
  bool _composePrivateMessage = false;
  String? _syntheticContinuationPrefix;

  bool get _isPrivateMessage => _composePrivateMessage;""",
    "ReplySheet continuation state",
)

helper = r"""  String? _buildContinuationPrefix() {
    final topicId = widget.topicId;
    final topicTitle = widget.topicTitle?.trim();
    if (topicId == null || topicTitle == null || topicTitle.isEmpty) {
      return null;
    }

    final postNumber = _replyToPost?.postNumber;
    final sourcePath = postNumber != null && postNumber > 0
        ? '/t/-/$topicId/$postNumber'
        : '/t/-/$topicId';
    final escapedTitle = topicTitle.replaceAll(']', r'\]');
    final sourceLink = '[$escapedTitle](${UrlHelper.resolveUrl(sourcePath)})';
    return context.l10n.post_continueDiscussion(sourceLink);
  }

  String _contentWithContinuation(String content) {
    final prefix = _buildContinuationPrefix();
    if (prefix == null || prefix.isEmpty) return content;
    return content.isEmpty ? prefix : '$prefix\n\n$content';
  }

  void _applySyntheticContinuation() {
    final prefix = _buildContinuationPrefix();
    if (prefix == null || prefix.isEmpty) return;
    final current = _contentController.text;
    final next = current.isEmpty ? prefix : '$prefix\n\n$current';
    _syntheticContinuationPrefix = prefix;
    _contentController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _removeSyntheticContinuation() {
    final prefix = _syntheticContinuationPrefix;
    if (prefix == null) return;
    final current = _contentController.text;
    final prefixed = '$prefix\n\n';
    final next = current == prefix
        ? ''
        : current.startsWith(prefixed)
        ? current.substring(prefixed.length)
        : current;
    _syntheticContinuationPrefix = null;
    if (next == current) return;
    _contentController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

"""
replace_once(
    reply,
    "  Future<void> _switchToTopicReply({Post? target}) async {",
    helper + "  Future<void> _switchToTopicReply({Post? target}) async {",
    "ReplySheet continuation helpers",
)
replace_once(
    reply,
    """    await _dropCurrentDraftForConversion();
    if (!mounted) return;

    setState(() {
      _composePrivateMessage = false;""",
    """    await _dropCurrentDraftForConversion();
    if (!mounted) return;
    _removeSyntheticContinuation();

    setState(() {
      _composePrivateMessage = false;""",
    "remove continuation when returning to reply",
)
replace_once(
    reply,
    """    await _dropCurrentDraftForConversion();
    if (!mounted) return;

    setState(() {
      _composePrivateMessage = true;
      _replyToPost = null;
      _recipients = <String>[];""",
    """    await _dropCurrentDraftForConversion();
    if (!mounted) return;
    _applySyntheticContinuation();

    setState(() {
      _composePrivateMessage = true;
      _replyToPost = null;
      _recipients = widget.privateMessageRecipients.toSet().toList();""",
    "PM conversion continuation and recipients",
)
replace_once(
    reply,
    "    final content = _contentController.text;\n    await _dropCurrentDraftForConversion();",
    "    final content = _contentWithContinuation(_contentController.text);\n    await _dropCurrentDraftForConversion();",
    "linked topic continuation",
)
replace_once(
    reply,
    """            widget.isPrivateMessageTopic
                ? context.l10n.pm_newTitle
                : context.l10n.createTopic_title,""",
    """            widget.isPrivateMessageTopic
                ? context.l10n.post_replyAsNewPrivateMessage
                : context.l10n.post_replyAsNewTopic,""",
    "Discourse action labels",
)

# 4) Stock Discourse wording for every locale shipped by this post module.
translations = {
    "lib/l10n/modules/post/post_en.arb": (
        "Reply as linked Topic",
        "Reply as new message to the same recipients",
        "Continuing the discussion from {postLink}:",
    ),
    "lib/l10n/modules/post/post_zh.arb": (
        "作为链接话题回复",
        "作为新消息回复给相同的收件人",
        "从{postLink}继续讨论：",
    ),
    "lib/l10n/modules/post/post_zh_TW.arb": (
        "回覆為關連的話題",
        "回覆作為新訊息給同一收件人",
        "繼續 {postLink} 的討論:",
    ),
    "lib/l10n/modules/post/post_zh_HK.arb": (
        "回覆為關連的話題",
        "回覆作為新訊息給同一收件人",
        "繼續 {postLink} 的討論:",
    ),
}
for path, (new_topic, new_pm, continuation) in translations.items():
    p = Path(path)
    text = p.read_text()
    if '"post_replyAsNewTopic"' in text:
        raise SystemExit(f"{path}: translation keys already exist")
    match = re.search(r'(?m)^  "post_replyToTopic": .*,$', text)
    if match is None:
        raise SystemExit(f"{path}: post_replyToTopic anchor not found")
    insertion = (
        match.group(0)
        + '\n  "post_replyAsNewTopic": '
        + json.dumps(new_topic, ensure_ascii=False)
        + ','
        + '\n  "post_replyAsNewPrivateMessage": '
        + json.dumps(new_pm, ensure_ascii=False)
        + ','
        + '\n  "post_continueDiscussion": '
        + json.dumps(continuation, ensure_ascii=False)
        + ','
        + '\n  "@post_continueDiscussion": {\n'
        + '    "placeholders": {\n'
        + '      "postLink": {\n'
        + '        "type": "String"\n'
        + '      }\n'
        + '    }\n'
        + '  },'
    )
    p.write_text(text[: match.start()] + insertion + text[match.end() :])

print("composer patch applied")
