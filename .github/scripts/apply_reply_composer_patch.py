from pathlib import Path

path = Path("lib/widgets/post/reply_sheet.dart")
s = path.read_text()


def replace_once(old: str, new: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(
            f"expected exactly one match, got {count}: {old[:120]!r}"
        )
    s = s.replace(old, new, 1)


replace_once(
    "import '../../pages/pending_posts_page.dart';\n",
    "import '../../pages/pending_posts_page.dart';\n"
    "import '../../pages/create_topic_page.dart';\n",
)

replace_once(
    "}\n\n/// 显示回复底部弹框\n",
    "}\n\n"
    "enum _ComposerAction {\n"
    "  replyToTopic,\n"
    "  replyToPost,\n"
    "  newTopic,\n"
    "  newPrivateMessage,\n"
    "}\n\n"
    "/// 显示回复底部弹框\n",
)

# State 内所有回复目标都必须跟随 composer 当前动作，而不是固定 widget 入参。
reply_to_post_refs = s.count("widget.replyToPost")
if reply_to_post_refs < 5:
    raise SystemExit(f"unexpected widget.replyToPost count: {reply_to_post_refs}")
s = s.replace("widget.replyToPost", "_replyToPost")

replace_once(
    "  final _editorKey = GlobalKey<MarkdownEditorState>();\n\n"
    "  bool _isSubmitting = false;\n",
    "  final _editorKey = GlobalKey<MarkdownEditorState>();\n"
    "  final _editReplyTargetController = TextEditingController();\n\n"
    "  bool _isSubmitting = false;\n",
)

replace_once(
    "  late List<String> _recipients = [\n"
    "    if (widget.targetUsername != null) widget.targetUsername!,\n"
    "  ];\n\n"
    "  bool get _isPrivateMessage =>\n"
    "      widget.targetUsername != null || widget.composePrivateMessage;\n",
    "  late List<String> _recipients = [\n"
    "    if (widget.targetUsername != null) widget.targetUsername!,\n"
    "  ];\n"
    "  Post? _replyToPost;\n"
    "  bool _composePrivateMessage = false;\n\n"
    "  bool get _isPrivateMessage => _composePrivateMessage;\n\n"
    "  bool get _canSwitchComposerAction =>\n"
    "      !_isEditMode && widget.topicId != null && !_isLoadingDraft;\n",
)

replace_once(
    "    super.initState();\n"
    "    EmojiHandler().init();\n\n"
    "    // 编辑模式：加载帖子原始内容\n",
    "    super.initState();\n"
    "    EmojiHandler().init();\n"
    "    _replyToPost = widget.replyToPost;\n"
    "    _composePrivateMessage =\n"
    "        widget.targetUsername != null || widget.composePrivateMessage;\n"
    "    if (_isEditMode) {\n"
    "      final replyTarget = widget.editPost!.replyToPostNumber;\n"
    "      _editReplyTargetController.text = replyTarget > 0 ? '$replyTarget' : '';\n"
    "    }\n\n"
    "    // 编辑模式：加载帖子原始内容\n",
)

replace_once(
    "  /// 加载帖子原始内容\n"
    "  Future<void> _loadPostRaw() async {\n",
    "  Future<void> _dropCurrentDraftForConversion() async {\n"
    "    final previous = _draftController;\n"
    "    _draftController = null;\n"
    "    if (previous == null) return;\n"
    "    previous.disable();\n"
    "    try {\n"
    "      await previous.deleteDraft();\n"
    "    } catch (_) {\n"
    "      // 动作切换不应被旧草稿清理失败阻塞；新模式会使用独立 draft key。\n"
    "    } finally {\n"
    "      previous.dispose();\n"
    "    }\n"
    "  }\n\n"
    "  Future<void> _switchToTopicReply({Post? target}) async {\n"
    "    if (_isEditMode || widget.topicId == null) return;\n"
    "    _richKey.currentState?.flushToController();\n"
    "    await _dropCurrentDraftForConversion();\n"
    "    if (!mounted) return;\n\n"
    "    setState(() {\n"
    "      _composePrivateMessage = false;\n"
    "      _replyToPost = target;\n"
    "      _recipients = [\n"
    "        if (widget.targetUsername != null) widget.targetUsername!,\n"
    "      ];\n"
    "      _draftController = DraftController(\n"
    "        draftKey: Draft.replyKey(\n"
    "          widget.topicId!,\n"
    "          replyToPostNumber: target?.postNumber,\n"
    "        ),\n"
    "      );\n"
    "      _titleController.clear();\n"
    "    });\n"
    "    _onContentChanged();\n"
    "    _contentFocusNode.requestFocus();\n"
    "  }\n\n"
    "  Future<void> _switchToPrivateMessage() async {\n"
    "    if (_isEditMode || widget.topicId == null) return;\n"
    "    _richKey.currentState?.flushToController();\n"
    "    await _dropCurrentDraftForConversion();\n"
    "    if (!mounted) return;\n\n"
    "    setState(() {\n"
    "      _composePrivateMessage = true;\n"
    "      _replyToPost = null;\n"
    "      _recipients = <String>[];\n"
    "      _draftController = DraftController(\n"
    "        draftKey: Draft.generateNewPrivateMessageKey(),\n"
    "      );\n"
    "      if (_titleController.text.trim().isEmpty &&\n"
    "          (widget.topicTitle?.trim().isNotEmpty ?? false)) {\n"
    "        _titleController.text = widget.topicTitle!.trim();\n"
    "      }\n"
    "    });\n"
    "    _onContentChanged();\n"
    "    _contentFocusNode.requestFocus();\n"
    "  }\n\n"
    "  Future<void> _convertToNewTopic() async {\n"
    "    if (_isEditMode) return;\n"
    "    _richKey.currentState?.flushToController();\n"
    "    final content = _contentController.text;\n"
    "    await _dropCurrentDraftForConversion();\n"
    "    if (!mounted) return;\n\n"
    "    _submitted = true;\n"
    "    final appNavigator = navigatorKey.currentState;\n"
    "    Navigator.of(context).pop();\n"
    "    await Future<void>.delayed(Duration.zero);\n"
    "    appNavigator?.push(\n"
    "      MaterialPageRoute(\n"
    "        builder: (_) => CreateTopicPage(\n"
    "          initialCategoryId: widget.categoryId,\n"
    "          initialContent: content,\n"
    "        ),\n"
    "      ),\n"
    "    );\n"
    "  }\n\n"
    "  /// 加载帖子原始内容\n"
    "  Future<void> _loadPostRaw() async {\n",
)

replace_once(
    "    _titleController.dispose();\n"
    "    _contentController.dispose();\n"
    "    _contentFocusNode.dispose();\n",
    "    _titleController.dispose();\n"
    "    _contentController.dispose();\n"
    "    _editReplyTargetController.dispose();\n"
    "    _contentFocusNode.dispose();\n",
)

replace_once(
    "  Future<void> _submit() async {\n",
    "  Future<Post> _updateEditedPostWithReplyTarget({\n"
    "    required String raw,\n"
    "    required int? replyToPostNumber,\n"
    "  }) async {\n"
    "    final response = await DiscourseService().dio.put(\n"
    "      '/posts/${widget.editPost!.id}.json',\n"
    "      data: <String, dynamic>{\n"
    "        'post[raw]': raw,\n"
    "        // Discourse PostsController checks key presence; blank normalizes to null.\n"
    "        'post[reply_to_post_number]': replyToPostNumber?.toString() ?? '',\n"
    "      },\n"
    "      options: Options(contentType: Headers.formUrlEncodedContentType),\n"
    "    );\n\n"
    "    final data = response.data;\n"
    "    if (data is Map && data['post'] is Map) {\n"
    "      return Post.fromJson(\n"
    "        Map<String, dynamic>.from(data['post'] as Map),\n"
    "      );\n"
    "    }\n"
    "    throw Exception(S.current.error_updatePostFailed);\n"
    "  }\n\n"
    "  Future<void> _submit() async {\n",
)

replace_once(
    "    if (content.isEmpty) {\n"
    "      _showError(S.current.post_contentRequired);\n"
    "      return;\n"
    "    }\n\n"
    "    // 最小字数校验\n",
    "    if (content.isEmpty) {\n"
    "      _showError(S.current.post_contentRequired);\n"
    "      return;\n"
    "    }\n\n"
    "    int? editedReplyTarget;\n"
    "    var editedReplyTargetChanged = false;\n"
    "    if (_isEditMode && widget.editPost!.postNumber > 1) {\n"
    "      final targetText = _editReplyTargetController.text.trim();\n"
    "      if (targetText.isNotEmpty) {\n"
    "        final parsed = int.tryParse(targetText);\n"
    "        final maxTarget = widget.editPost!.postNumber - 1;\n"
    "        if (parsed == null || parsed < 1 || parsed > maxTarget) {\n"
    "          _showError('${context.l10n.post_replyTo}: #1 - #$maxTarget');\n"
    "          return;\n"
    "        }\n"
    "        editedReplyTarget = parsed;\n"
    "      }\n"
    "      final currentTarget = widget.editPost!.replyToPostNumber > 0\n"
    "          ? widget.editPost!.replyToPostNumber\n"
    "          : null;\n"
    "      editedReplyTargetChanged = editedReplyTarget != currentTarget;\n"
    "    }\n\n"
    "    // 最小字数校验\n",
)

replace_once(
    "        final updatedPost = await DiscourseService().updatePost(\n"
    "          postId: widget.editPost!.id,\n"
    "          raw: content,\n"
    "        );\n",
    "        final updatedPost = editedReplyTargetChanged\n"
    "            ? await _updateEditedPostWithReplyTarget(\n"
    "                raw: content,\n"
    "                replyToPostNumber: editedReplyTarget,\n"
    "              )\n"
    "            : await DiscourseService().updatePost(\n"
    "                postId: widget.editPost!.id,\n"
    "                raw: content,\n"
    "              );\n",
)

replace_once(
    "  @override\n"
    "  Widget build(BuildContext context) {\n",
    "  String _currentComposerActionLabel(BuildContext context) {\n"
    "    if (_isPrivateMessage) {\n"
    "      return _recipients.isEmpty\n"
    "          ? context.l10n.pm_newTitle\n"
    "          : context.l10n.post_sendPmTitle(_recipients.join(', '));\n"
    "    }\n"
    "    final reply = _replyToPost;\n"
    "    if (reply != null) {\n"
    "      return context.l10n.post_replyToUser(reply.username);\n"
    "    }\n"
    "    return context.l10n.post_replyToTopic;\n"
    "  }\n\n"
    "  List<PopupMenuEntry<_ComposerAction>> _composerActionItems(\n"
    "    BuildContext context,\n"
    "  ) {\n"
    "    final entries = <PopupMenuEntry<_ComposerAction>>[\n"
    "      PopupMenuItem(\n"
    "        value: _ComposerAction.replyToTopic,\n"
    "        child: ListTile(\n"
    "          dense: true,\n"
    "          leading: const Icon(Icons.reply_all_rounded),\n"
    "          title: Text(context.l10n.post_replyToTopic),\n"
    "          contentPadding: EdgeInsets.zero,\n"
    "        ),\n"
    "      ),\n"
    "    ];\n\n"
    "    final originalTarget = widget.replyToPost;\n"
    "    if (originalTarget != null) {\n"
    "      entries.add(\n"
    "        PopupMenuItem(\n"
    "          value: _ComposerAction.replyToPost,\n"
    "          child: ListTile(\n"
    "            dense: true,\n"
    "            leading: const Icon(Icons.reply_rounded),\n"
    "            title: Text(\n"
    "              context.l10n.post_replyToUser(originalTarget.username),\n"
    "            ),\n"
    "            contentPadding: EdgeInsets.zero,\n"
    "          ),\n"
    "        ),\n"
    "      );\n"
    "    }\n\n"
    "    entries.add(\n"
    "      PopupMenuItem(\n"
    "        value: widget.isPrivateMessageTopic\n"
    "            ? _ComposerAction.newPrivateMessage\n"
    "            : _ComposerAction.newTopic,\n"
    "        child: ListTile(\n"
    "          dense: true,\n"
    "          leading: Icon(\n"
    "            widget.isPrivateMessageTopic\n"
    "                ? Icons.mail_outline_rounded\n"
    "                : Icons.add_box_outlined,\n"
    "          ),\n"
    "          title: Text(\n"
    "            widget.isPrivateMessageTopic\n"
    "                ? context.l10n.pm_newTitle\n"
    "                : context.l10n.createTopic_title,\n"
    "          ),\n"
    "          contentPadding: EdgeInsets.zero,\n"
    "        ),\n"
    "      ),\n"
    "    );\n"
    "    return entries;\n"
    "  }\n\n"
    "  Future<void> _handleComposerAction(_ComposerAction action) async {\n"
    "    switch (action) {\n"
    "      case _ComposerAction.replyToTopic:\n"
    "        await _switchToTopicReply();\n"
    "        return;\n"
    "      case _ComposerAction.replyToPost:\n"
    "        await _switchToTopicReply(target: widget.replyToPost);\n"
    "        return;\n"
    "      case _ComposerAction.newTopic:\n"
    "        await _convertToNewTopic();\n"
    "        return;\n"
    "      case _ComposerAction.newPrivateMessage:\n"
    "        await _switchToPrivateMessage();\n"
    "        return;\n"
    "    }\n"
    "  }\n\n"
    "  Widget _buildComposerActionSelector(ThemeData theme) {\n"
    "    final reply = _replyToPost;\n"
    "    final row = Row(\n"
    "      children: [\n"
    "        if (!_isPrivateMessage && reply != null) ...[\n"
    "          SmartAvatar(\n"
    "            imageUrl: reply.getAvatarUrl().isNotEmpty\n"
    "                ? reply.getAvatarUrl()\n"
    "                : null,\n"
    "            radius: 14,\n"
    "            fallbackText: reply.username,\n"
    "            backgroundColor: theme.colorScheme.primaryContainer,\n"
    "          ),\n"
    "          const SizedBox(width: 8),\n"
    "        ],\n"
    "        Expanded(\n"
    "          child: Text(\n"
    "            _currentComposerActionLabel(context),\n"
    "            style: theme.textTheme.titleSmall,\n"
    "            overflow: TextOverflow.ellipsis,\n"
    "          ),\n"
    "        ),\n"
    "        if (_canSwitchComposerAction) ...[\n"
    "          const SizedBox(width: 4),\n"
    "          Icon(\n"
    "            Icons.arrow_drop_down_rounded,\n"
    "            color: theme.colorScheme.onSurfaceVariant,\n"
    "          ),\n"
    "        ],\n"
    "      ],\n"
    "    );\n\n"
    "    if (!_canSwitchComposerAction) return row;\n"
    "    return PopupMenuButton<_ComposerAction>(\n"
    "      tooltip: _currentComposerActionLabel(context),\n"
    "      position: PopupMenuPosition.under,\n"
    "      onSelected: (action) async {\n"
    "        await _handleComposerAction(action);\n"
    "      },\n"
    "      itemBuilder: _composerActionItems,\n"
    "      child: row,\n"
    "    );\n"
    "  }\n\n"
    "  @override\n"
    "  Widget build(BuildContext context) {\n",
)

old_header = """                                // 标题信息
                                if (_isEditMode) ...[
                                  Icon(
                                    Symbols.edit_rounded,
                                    size: 18,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      context.l10n.post_editPostTitle(
                                        widget.editPost!.postNumber,
                                      ),
                                      style: theme.textTheme.titleSmall,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ] else if (_isPrivateMessage)
                                  Expanded(
                                    child: Text(
                                      _recipients.isEmpty
                                          ? context.l10n.pm_newTitle
                                          : context.l10n.post_sendPmTitle(
                                              _recipients.join(', '),
                                            ),
                                      style: theme.textTheme.titleSmall,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                else if (_replyToPost != null) ...[
                                  SmartAvatar(
                                    imageUrl:
                                        _replyToPost!
                                            .getAvatarUrl()
                                            .isNotEmpty
                                        ? _replyToPost!.getAvatarUrl()
                                        : null,
                                    radius: 14,
                                    fallbackText: _replyToPost!.username,
                                    backgroundColor:
                                        theme.colorScheme.primaryContainer,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      context.l10n.post_replyToUser(
                                        _replyToPost!.username,
                                      ),
                                      style: theme.textTheme.titleSmall,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ] else
                                  Text(
                                    context.l10n.post_replyToTopic,
                                    style: theme.textTheme.titleSmall,
                                  ),

                                if (!_isPrivateMessage &&
                                    !_isEditMode &&
                                    _replyToPost == null)
                                  const Spacer(),
"""
new_header = """                                // 标题信息：Discourse 风格动作选择器。
                                if (_isEditMode) ...[
                                  Icon(
                                    Symbols.edit_rounded,
                                    size: 18,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      context.l10n.post_editPostTitle(
                                        widget.editPost!.postNumber,
                                      ),
                                      style: theme.textTheme.titleSmall,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ] else
                                  Expanded(
                                    child: _buildComposerActionSelector(theme),
                                  ),
"""
replace_once(old_header, new_header)

replace_once(
    """                      // 新建私信：所有入口都可增删收件人，预设对象保留为首个 chip。
                      if (_canEditRecipients)
""",
    """                      // 编辑普通回复时允许调整其回复目标楼层。留空 = 回复话题。
                      if (_isEditMode && widget.editPost!.postNumber > 1)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                          child: TextField(
                            controller: _editReplyTargetController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              isDense: true,
                              labelText:
                                  '${context.l10n.post_replyTo} (#1 - #${widget.editPost!.postNumber - 1})',
                              hintText: context.l10n.post_replyToTopic,
                              prefixText: '#',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: context.l10n.post_replyToTopic,
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: _editReplyTargetController.clear,
                              ),
                            ),
                          ),
                        ),

                      // 新建私信：所有入口都可增删收件人，预设对象保留为首个 chip。
                      if (_canEditRecipients)
""",
)

path.write_text(s)
