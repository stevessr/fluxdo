part of '../post_footer_section.dart';

extension _PostFooterMenuActions on _PostFooterSectionState {
  Future<void> _sharePost() async {
    // 与话题详情页的「分享回复」同口径:走 buildShareUrl 并遵守匿名分享偏好,
    // 否则同一个动作在两个入口生成的链接不一样(带不带 ?u=)
    final username = ref.read(currentUserProvider).value?.username ?? '';
    final url = ShareUtils.buildShareUrl(
      path: '/t/topic/${widget.topicId}/${widget.post.postNumber}',
      username: username,
      anonymousShare: ref.read(preferencesProvider).anonymousShare,
    );
    await SharePlus.instance.share(ShareParams(text: url));
  }

  void _showFlagDialog(BuildContext context) {
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false, // 举报表单(card):禁止下滑误关
      builder: (context) => PostFlagSheet(
        postId: widget.post.id,
        postUsername: widget.post.username,
        service: _service,
        onSuccess: () => ToastService.showSuccess(S.current.post_flagSubmitted),
      ),
    );
  }

  void _showPostJsonViewer(BuildContext context) {
    final zh =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';
    final rawJson = widget.post.rawJson;
    final jsonText = const JsonEncoder.withIndent('  ').convert(rawJson);

    AppBottomSheet.showDraggable<void>(
      context: context,
      title: zh ? '帖子键值' : 'Post fields',
      showCloseButton: true,
      showTitleDivider: true,
      initialSize: 0.78,
      minSize: 0.45,
      maxSize: 0.95,
      actions: [
        IconButton(
          tooltip: zh ? '复制原始 JSON' : 'Copy raw JSON',
          icon: const Icon(Icons.copy_all_rounded),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: jsonText));
            if (!mounted) return;
            ToastService.showSuccess(zh ? '原始 JSON 已复制' : 'Raw JSON copied');
          },
        ),
      ],
      bodyBuilder: (sheetContext, scrollController) {
        if (rawJson.isEmpty) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                Icons.data_object_rounded,
                size: 42,
                color: Theme.of(sheetContext).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                zh ? '当前帖子没有可用的原始键值数据' : 'No raw field data is available',
                textAlign: TextAlign.center,
              ),
            ],
          );
        }

        return _PostJsonTree(
          data: rawJson,
          scrollController: scrollController,
          zh: zh,
        );
      },
    );
  }

  void _showDeleteConfirmDialog(BuildContext context, ThemeData theme) {
    showAppDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.post_deleteReplyTitle),
        content: Text(context.l10n.post_deleteReplyConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deletePost();
            },
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            child: Text(context.l10n.common_delete),
          ),
        ],
      ),
    );
  }

  void _showMoreMenu(BuildContext context, ThemeData theme) {
    final currentUser = ref.read(currentUserProvider).value;
    final isGuest = currentUser == null;
    final isStaff =
        currentUser?.admin == true || currentUser?.moderator == true;
    final zh =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';

    showAppBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => AppSheetScaffold(
        showCloseButton: false,
        maxHeightFactor: 0.7,
        contentPadding: EdgeInsets.zero,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onShowPostDetail != null)
                ListTile(
                  leading: Icon(
                    widget.postDetailLabel != null
                        ? Symbols.open_in_new_rounded
                        : Symbols.article_rounded,
                    color: theme.colorScheme.onSurface,
                  ),
                  title: Text(
                    widget.postDetailLabel ?? context.l10n.post_detail,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onShowPostDetail!();
                  },
                ),
              if (widget.onReply != null)
                ListTile(
                  leading: Icon(
                    Symbols.reply_rounded,
                    color: theme.colorScheme.onSurface,
                  ),
                  title: Text(context.l10n.common_reply),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onReply!();
                  },
                ),
              if (widget.post.canEdit && widget.onEdit != null)
                ListTile(
                  leading: Icon(
                    Symbols.edit_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(
                    context.l10n.common_edit,
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onEdit!();
                  },
                ),
              if (!isGuest && widget.post.canWiki)
                ListTile(
                  leading: Icon(
                    widget.post.wiki
                        ? Symbols.edit_note_rounded
                        : Symbols.description_rounded,
                    color: theme.colorScheme.onSurface,
                  ),
                  title: Text(widget.post.wiki ? '取消 Wiki' : '设为 Wiki'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleWiki();
                  },
                ),
              if (isStaff) ...[
                ListTile(
                  leading: Icon(
                    widget.post.locked
                        ? Icons.lock_open_outlined
                        : Icons.lock_outline,
                    color: theme.colorScheme.onSurface,
                  ),
                  title: Text(
                    widget.post.locked
                        ? (zh ? '解锁帖子' : 'Unlock post')
                        : (zh ? '锁定帖子' : 'Lock post'),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _togglePostLocked();
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.info_outline,
                    color: theme.colorScheme.onSurface,
                  ),
                  title: Text(
                    widget.post.notice?.type == 'custom'
                        ? (zh ? '编辑 Staff 提示' : 'Edit staff notice')
                        : (zh ? '添加 Staff 提示' : 'Add staff notice'),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _editPostNotice();
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.refresh_rounded,
                    color: theme.colorScheme.onSurface,
                  ),
                  title: Text(zh ? '重新渲染帖子' : 'Rebake post'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _rebakePost();
                  },
                ),
                if (widget.post.postNumber != 1 || widget.post.postType == 4)
                  ListTile(
                    leading: Icon(
                      Icons.visibility_off_outlined,
                      color: theme.colorScheme.onSurface,
                    ),
                    title: Text(
                      widget.post.postType == 4
                          ? (zh ? '转为普通帖子' : 'Convert to regular post')
                          : (zh ? '转为 Whisper' : 'Convert to whisper'),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _togglePostType();
                    },
                  ),
                if (!widget.post.isDeleted && widget.post.postNumber > 1)
                  ListTile(
                    leading: Icon(
                      Icons.call_merge_rounded,
                      color: theme.colorScheme.onSurface,
                    ),
                    title: Text(zh ? '合并同作者帖子' : 'Merge author posts'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _mergePostWithOthers();
                    },
                  ),
                if (currentUser?.admin == true && widget.post.isDeleted)
                  ListTile(
                    leading: Icon(
                      Icons.delete_forever_outlined,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      widget.post.canPermanentlyDelete
                          ? (zh ? '可永久删除 · 查看条件' : 'Permanent delete available')
                          : (zh
                                ? '检查永久删除条件'
                                : 'Check permanent delete eligibility'),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showPermanentDeleteCheck();
                    },
                  ),
              ],
              // 菜单点击后才构建，用 read 避免给楼层常驻树增加监听。
              if (ref.read(preferencesProvider).aiTranslationEnabled &&
                  ref.read(aiTranslationSelectedModelProvider) != null)
                ListTile(
                  leading: Icon(
                    Symbols.translate_rounded,
                    color: theme.colorScheme.onSurface,
                  ),
                  title: Text(context.l10n.ai_translationMenuLabel),
                  onTap: () {
                    Navigator.pop(ctx);
                    showAiTranslationSheet(
                      context,
                      cookedHtml: widget.post.cooked,
                    );
                  },
                ),
              ListTile(
                leading: Icon(
                  Icons.data_object_rounded,
                  color: theme.colorScheme.onSurface,
                ),
                title: Text(zh ? '查看帖子键值' : 'View post fields'),
                subtitle: Text(
                  zh
                      ? '${widget.post.rawJson.length} 个顶层字段 · 可视化浏览'
                      : '${widget.post.rawJson.length} top-level fields · visual browser',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showPostJsonViewer(context);
                },
              ),
              ListTile(
                leading: Icon(
                  Symbols.share_rounded,
                  color: theme.colorScheme.onSurface,
                ),
                title: Text(context.l10n.common_shareLink),
                onTap: () {
                  Navigator.pop(ctx);
                  _sharePost();
                },
              ),
              if (widget.onShareAsImage != null)
                ListTile(
                  leading: Icon(
                    Symbols.image_rounded,
                    color: theme.colorScheme.onSurface,
                  ),
                  title: Text(context.l10n.post_generateShareImage),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onShareAsImage!();
                  },
                ),
              if (!isGuest)
                Builder(
                  builder: (context) {
                    final currentUser = ref.read(currentUserProvider).value;
                    final isOwnPost =
                        currentUser != null &&
                        currentUser.username == widget.post.username;
                    if (isOwnPost || widget.post.userId == null) {
                      return const SizedBox.shrink();
                    }
                    return ListTile(
                      leading: Icon(
                        Symbols.volunteer_activism_rounded,
                        color: theme.colorScheme.onSurface,
                      ),
                      title: Text(context.l10n.post_tipLdc),
                      onTap: () async {
                        Navigator.pop(ctx);
                        try {
                          final credentials = await ref.read(
                            ldcRewardCredentialsProvider.future,
                          );
                          if (!mounted) return;
                          if (credentials == null) {
                            ToastService.showError(
                              S.current.toast_rewardNotConfigured,
                            );
                            return;
                          }
                        } catch (error) {
                          debugPrint('[LdcReward] 读取凭证失败: $error');
                          ToastService.showError(
                            S.current.common_operationFailed(error.toString()),
                          );
                          return;
                        }
                        if (!mounted) return;
                        showLdcRewardSheet(
                          this.context,
                          RewardTargetInfo(
                            userId: widget.post.userId!,
                            username: widget.post.username,
                            name: widget.post.name,
                            avatarUrl: widget.post.getAvatarUrl(),
                            topicId: widget.topicId,
                            postId: widget.post.id,
                          ),
                        );
                      },
                    );
                  },
                ),
              if (!isGuest &&
                  (widget.post.canAcceptAnswer ||
                      widget.post.canUnacceptAnswer))
                ListTile(
                  leading: Icon(
                    _isAcceptedAnswer
                        ? Symbols.check_box_rounded
                        : Symbols.check_box_outline_blank_rounded,
                    color: _isAcceptedAnswer
                        ? Colors.green
                        : theme.colorScheme.onSurface,
                  ),
                  title: Text(
                    _isAcceptedAnswer
                        ? context.l10n.post_unacceptSolution
                        : context.l10n.post_acceptSolution,
                    style: TextStyle(
                      color: _isAcceptedAnswer
                          ? Colors.green
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  onTap: _isTogglingAnswer
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _toggleSolution();
                        },
                ),
              if (!isGuest)
                ListTile(
                  leading: Icon(
                    Symbols.bookmark_rounded,
                    fill: _isBookmarked ? 1 : 0,
                    color: _isBookmarked
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                  title: Text(
                    _isBookmarked
                        ? context.l10n.bookmark_editBookmark
                        : context.l10n.common_addBookmark,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (_isBookmarked) {
                      _editBookmark();
                    } else {
                      _addBookmark();
                    }
                  },
                ),
              if (widget.canAssignPost && widget.onAssignPost != null)
                ListTile(
                  leading: Icon(
                    Icons.assignment_ind_outlined,
                    color: theme.colorScheme.onSurface,
                  ),
                  title: const Text('指定帖子'),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onAssignPost!();
                  },
                ),
              if (!isGuest)
                ListTile(
                  leading: Icon(
                    Symbols.flag_rounded,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    context.l10n.common_report,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showFlagDialog(context);
                  },
                ),
              if (!isGuest && widget.post.canRecover)
                ListTile(
                  leading: Icon(
                    Symbols.restore_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(
                    context.l10n.common_restore,
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                  onTap: _isDeleting
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _recoverPost();
                        },
                ),
              if (!isGuest && widget.post.canDelete && !widget.post.isDeleted)
                ListTile(
                  leading: Icon(
                    Symbols.delete_rounded,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    context.l10n.common_delete,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: _isDeleting
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _showDeleteConfirmDialog(context, theme);
                        },
                ),
              // 仅 debug build:复制 cooked HTML(给渲染引擎调试用)
              if (kDebugMode) ...[
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(
                    Symbols.bug_report_rounded,
                    color: theme.colorScheme.tertiary,
                  ),
                  title: Text(
                    'Copy cooked HTML',
                    style: TextStyle(color: theme.colorScheme.tertiary),
                  ),
                  subtitle: Text(
                    'debug: ${widget.post.cooked.length} chars',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await Clipboard.setData(
                      ClipboardData(text: widget.post.cooked),
                    );
                    ToastService.showSuccess(
                      'cooked HTML 已复制 (${widget.post.cooked.length} chars)',
                    );
                  },
                ),
                // 复制签名(user_signature:advanced 模式为 HTML,否则为图片 URL)
                if (widget.post.effectiveSignature != null)
                  ListTile(
                    leading: Icon(
                      Symbols.bug_report_rounded,
                      color: theme.colorScheme.tertiary,
                    ),
                    title: Text(
                      'Copy signature',
                      style: TextStyle(color: theme.colorScheme.tertiary),
                    ),
                    subtitle: Text(
                      'debug: ${widget.post.effectiveSignature!.length} chars',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final signature = widget.post.effectiveSignature!;
                      await Clipboard.setData(ClipboardData(text: signature));
                      ToastService.showSuccess(
                        '签名已复制 (${signature.length} chars)',
                      );
                    },
                  ),
              ],
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                title: Text(
                  context.l10n.common_cancel,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostJsonTree extends StatelessWidget {
  const _PostJsonTree({
    required this.data,
    required this.scrollController,
    required this.zh,
  });

  final Map<String, dynamic> data;
  final ScrollController scrollController;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complexCount = data.values
        .where((value) => value is Map || value is List)
        .length;
    final scalarCount = data.length - complexCount;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PostJsonSummaryChip(
              icon: Icons.view_list_rounded,
              label: zh ? '${data.length} 个字段' : '${data.length} fields',
            ),
            _PostJsonSummaryChip(
              icon: Icons.account_tree_outlined,
              label: zh ? '$complexCount 个结构值' : '$complexCount structured',
            ),
            _PostJsonSummaryChip(
              icon: Icons.short_text_rounded,
              label: zh ? '$scalarCount 个普通值' : '$scalarCount scalar',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          zh ? '点击对象或数组可展开子键值；普通值可直接选择复制。' : 'Tap objects or arrays to expand them. Scalar values are selectable.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        ...data.entries.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PostJsonNode(
              name: entry.key,
              value: entry.value,
              depth: 0,
              zh: zh,
            ),
          ),
        ),
      ],
    );
  }
}

class _PostJsonSummaryChip extends StatelessWidget {
  const _PostJsonSummaryChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PostJsonNode extends StatelessWidget {
  const _PostJsonNode({
    required this.name,
    required this.value,
    required this.depth,
    required this.zh,
  });

  final String name;
  final dynamic value;
  final int depth;
  final bool zh;

  bool get _isMap => value is Map;
  bool get _isList => value is List;

  String _typeLabel() {
    if (_isMap) {
      final count = (value as Map).length;
      return zh ? '对象 · $count 个键' : 'Object · $count keys';
    }
    if (_isList) {
      final count = (value as List).length;
      return zh ? '数组 · $count 项' : 'Array · $count items';
    }
    if (value == null) return 'null';
    if (value is bool) return 'bool';
    if (value is num) return 'number';
    return 'string';
  }

  IconData _typeIcon() {
    if (_isMap) return Icons.account_tree_outlined;
    if (_isList) return Icons.data_array_rounded;
    if (value == null) return Icons.block_rounded;
    if (value is bool) return Icons.toggle_on_outlined;
    if (value is num) return Icons.numbers_rounded;
    return Icons.text_fields_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = depth == 0 ? 0.0 : 12.0;

    if (_isMap || _isList) {
      final entries = _isMap
          ? (value as Map).entries
                .map((entry) => MapEntry(entry.key.toString(), entry.value))
                .toList(growable: false)
          : (value as List)
                .asMap()
                .entries
                .map((entry) => MapEntry('[${entry.key}]', entry.value))
                .toList(growable: false);

      return Padding(
        padding: EdgeInsets.only(left: indent),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: depth == 0
                ? theme.colorScheme.surfaceContainerLow
                : theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: ExpansionTile(
            leading: Icon(
              _typeIcon(),
              size: 20,
              color: theme.colorScheme.primary,
            ),
            title: SelectableText(
              name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              _typeLabel(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            children: entries
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _PostJsonNode(
                      name: entry.key,
                      value: entry.value,
                      depth: depth + 1,
                      zh: zh,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      );
    }

    final displayValue = value == null ? 'null' : value.toString();
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: depth == 0
              ? theme.colorScheme.surfaceContainerLow
              : theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    _typeIcon(),
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _typeLabel(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.45,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  displayValue,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: value is String ? 'monospace' : null,
                    height: 1.4,
                    color: value == null
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
