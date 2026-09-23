import 'package:fluxdo/widgets/markdown_editor/composer_submission_snapshot.dart';

import '../markdown_editor/uploads/upload_task_labels.dart';

import 'package:fluxdo/widgets/markdown_editor/composer_draft_status.dart';

import '../../utils/platform_utils.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/draft_store_provider.dart';

import 'pm_recipient_field.dart';
import '../markdown_editor/composer_shortcuts.dart';
import '../markdown_editor/composer_switch_fade.dart';
import '../markdown_editor/composer_workbench.dart';
import '../markdown_editor/composer_header_actions.dart';
import '../common/character_counts_overlay.dart';
import '../markdown_editor/composer_view_mode_switcher.dart';
import '../markdown_editor/markdown_renderer.dart';
import '../markdown_editor/markdown_editor.dart';
import '../markdown_editor/rich_composer/rich_composer_editor.dart';
import '../../providers/preferences_provider.dart';
import '../../models/topic.dart';
import '../../models/draft.dart';
import '../../plugins/plugins.dart';
import '../../providers/category_provider.dart';
import '../../services/composer_min_length_resolver.dart';
import '../../models/pending_post.dart';
import '../../pages/pending_posts_page.dart';
import '../../pages/create_topic_page.dart';
import '../../services/local_notification_service.dart' show navigatorKey;
import '../../services/discourse/discourse_service.dart';
import '../../services/ai_post_review_service.dart';
import '../../services/presence_service.dart';
import '../../services/emoji_handler.dart';
import '../../services/draft_controller.dart';
import '../../services/dynamic_content_suspension_service.dart';
import '../../services/embedded_browser_controller_pool.dart';

import 'package:dio/dio.dart';

import '../../services/app_error_handler.dart';
import '../../services/network/exceptions/api_exception.dart';
import '../../services/toast_service.dart';
import '../common/smart_avatar.dart';
import '../../l10n/s.dart';
import '../../utils/dialog_utils.dart';
import '../../utils/url_helper.dart';
import '../../providers/shortcut_provider.dart';
import '../ai/ai_post_review_button.dart';

import 'package:m3e_ui/m3e_ui.dart';

enum _ComposerAction { replyToTopic, replyToPost, newTopic, newPrivateMessage }

/// Windows 平台视图从 Widget 树移除到 WebView2 Controller 真正析构存在
/// 明显时间差。若立即弹出编辑器，旧 SVG WebView 的析构会和输入框首帧、
/// 键盘焦点及草稿加载同时争抢平台/UI 消息泵。只在确有浏览器槽位时短暂
/// 等待，原生 SVG 或普通帖子不会增加打开延迟。
Future<void> _waitForEmbeddedBrowserTeardown() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
  await WidgetsBinding.instance.endOfFrame;
  final pool = EmbeddedBrowserControllerPool.instance;
  if (pool.activeCount == 0) return;
  final deadline = DateTime.now().add(const Duration(milliseconds: 900));
  while (pool.activeCount > 0 && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// 显示回复底部弹框
/// [topicId] 话题 ID (回复话题/帖子时必需)
/// [categoryId] 分类 ID（可选，用于用户搜索）
/// [replyToPost] 可选，被回复的帖子
/// [targetUsername] 可选，私信目标用户名（创建时作为预选收件人）
/// [draftKey] 可选，恢复已有草稿时传入原草稿 key（草稿列表入口使用）
/// [preloadedDraftFuture] 预加载的草稿 Future（在点击回复按钮时就发起请求）
/// [initialContent] 可选，预填内容（划词引用时使用）
/// [initialTitle] 可选，预填标题（私信模式时使用）
/// [onEnqueued] 可选，帖子被送审时回调(携带待审内容摘要);
/// 不传时降级为 toast 提示 + 「查看」跳转待审列表页
/// 返回创建的 Post 对象，取消或失败返回 null
Future<Post?> showReplySheet({
  required BuildContext context,
  int? topicId,
  int? categoryId,
  Post? replyToPost,
  String? targetUsername,

  /// 新建私信（可无预设收件人）：收件人由用户在编辑器内搜索增删
  bool composePrivateMessage = false,
  String? draftKey,
  Future<Draft?>? preloadedDraftFuture,
  String? initialContent,
  String? initialTitle,
  String? topicTitle,
  bool isPrivateMessageTopic = false,
  List<String> privateMessageRecipients = const <String>[],
  bool isPmWithNonHumanUser = false,
  ShortcutSurfaceConfig? shortcutSurface,
  ValueChanged<PendingPost>? onEnqueued,
}) async {
  final suspension = DynamicContentSuspensionService.instance.acquire(
    reason: 'reply_sheet',
  );
  try {
    await _waitForEmbeddedBrowserTeardown();
    if (!context.mounted) return null;
    return await showAppBottomSheet<Post?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      shortcutSurface: shortcutSurface,
      // 动态帖子位于弹层下方时，全屏实时模糊会被每个动画帧重新计算，
      // 与编辑器同步 cook 叠加后可同时打满 GPU 和 UI isolate。
      blur: false,
      builder: (context) => ReplySheet(
        topicId: topicId,
        categoryId: categoryId,
        replyToPost: replyToPost,
        targetUsername: targetUsername,
        composePrivateMessage: composePrivateMessage,
        draftKey: draftKey,
        preloadedDraftFuture: preloadedDraftFuture,
        initialContent: initialContent,
        initialTitle: initialTitle,
        topicTitle: topicTitle,
        isPrivateMessageTopic: isPrivateMessageTopic,
        privateMessageRecipients: privateMessageRecipients,
        isPmWithNonHumanUser: isPmWithNonHumanUser,
        onEnqueued: onEnqueued,
      ),
    );
  } finally {
    suspension.release();
  }
}

/// 显示编辑帖子底部弹框
/// [topicId] 话题 ID
/// [post] 要编辑的帖子
/// [categoryId] 分类 ID（可选，用于用户搜索）
/// 返回更新后的 Post 对象，取消或失败返回 null
Future<Post?> showEditSheet({
  required BuildContext context,
  required int topicId,
  required Post post,
  int? categoryId,
  bool isPrivateMessageTopic = false,
  bool isPmWithNonHumanUser = false,
  ShortcutSurfaceConfig? shortcutSurface,
}) async {
  final suspension = DynamicContentSuspensionService.instance.acquire(
    reason: 'edit_sheet',
  );
  try {
    await _waitForEmbeddedBrowserTeardown();
    if (!context.mounted) return null;
    return await showAppBottomSheet<Post?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      shortcutSurface: shortcutSurface,
      blur: false,
      builder: (context) => ReplySheet(
        topicId: topicId,
        categoryId: categoryId,
        editPost: post,
        isPrivateMessageTopic: isPrivateMessageTopic,
        isPmWithNonHumanUser: isPmWithNonHumanUser,
      ),
    );
  } finally {
    suspension.release();
  }
}

class ReplySheet extends ConsumerStatefulWidget {
  final int? topicId;
  final int? categoryId;
  final Post? replyToPost;
  final String? targetUsername;

  /// 新建私信（无预设收件人）
  final bool composePrivateMessage;
  final String? draftKey; // 恢复已有草稿时传入的原草稿 key
  final Post? editPost; // 编辑模式：要编辑的帖子
  final Future<Draft?>? preloadedDraftFuture; // 预加载的草稿
  final String? initialContent; // 预填内容（划词引用时使用）
  final String? initialTitle; // 预填标题（私信模式时使用）
  final String? topicTitle; // 普通回帖审核时带上的话题标题
  final bool isPrivateMessageTopic; // 当前话题是否为私信话题
  final List<String> privateMessageRecipients; // 原私信用户/群组
  final bool isPmWithNonHumanUser; // 当前私信话题是否包含非真人用户
  final ValueChanged<PendingPost>? onEnqueued; // 帖子被送审时回调

  const ReplySheet({
    super.key,
    this.topicId,
    this.categoryId,
    this.replyToPost,
    this.targetUsername,
    this.composePrivateMessage = false,
    this.draftKey,
    this.editPost,
    this.preloadedDraftFuture,
    this.initialContent,
    this.initialTitle,
    this.topicTitle,
    this.isPrivateMessageTopic = false,
    this.privateMessageRecipients = const <String>[],
    this.isPmWithNonHumanUser = false,
    this.onEnqueued,
  });

  @override
  ConsumerState<ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends ConsumerState<ReplySheet> {
  /// 富文本导入失败(cook 不可用)时本次会话降级纯文本
  bool _richFallback = false;
  bool _allowClose = false;
  bool _richModeEnabled = false;

  void _closeWithCurrentContent(dynamic result) {
    if (!_submitted && !_discarded && !_flushRichContent()) return;
    setState(() => _allowClose = true);
    // 等待 PopScope 更新许可；dispose 随后保存刚刚同步的草稿。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  /// 富文本未就绪或导出失败时，绝不能消费 controller 中的旧镜像。
  bool _flushRichContent() {
    final rich = _richKey.currentState;
    final ready = rich != null
        ? rich.flushToController()
        : (_showPreview ||
              _richFallback ||
              !ref.read(preferencesProvider).useRichComposer);
    if (!ready) {
      ToastService.showError('正文尚未同步，已停止操作；请稍后重试，勿关闭编辑器');
    }
    return ready;
  }

  /// 预览渲染。与 MarkdownEditor 内部预览同款（MarkdownBody + 空态文案），
  /// 但对富文本/源码两种模式都生效。
  Widget _buildPreview(ThemeData theme) {
    final text = _contentController.text;
    return SingleChildScrollView(
      key: const ValueKey('reply-preview'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: text.trim().isEmpty
          ? Text(
              S.current.editor_noContent,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            )
          : MarkdownBody(data: text),
    );
  }

  /// 预览态独立于编辑模式，切换时保留原编辑器。
  bool _showPreview = false;

  /// 当前视图档位。
  ComposerViewMode get _viewMode {
    if (_showPreview) return ComposerViewMode.preview;
    return (ref.read(preferencesProvider).useRichComposer && !_richFallback)
        ? ComposerViewMode.rich
        : ComposerViewMode.source;
  }

  /// 三档齐全：预览对富文本/源码都可用（此前预览按钮挂在源码工具栏上，
  /// 富文本态下根本看不到，是个割裂）。
  void _setViewMode(ComposerViewMode next) {
    if (next == _viewMode) return;
    if (next == ComposerViewMode.preview) {
      _togglePreview();
      return;
    }
    final hadFocus = _contentFocusNode.hasFocus;
    if (!_flushRichContent()) return;
    _editorKey.currentState?.closeEmojiPanel();
    _richKey.currentState?.closeEmojiPanel();
    _contentFocusNode.unfocus();
    setState(() {
      _showPreview = false;
      _richFallback = next == ComposerViewMode.source;
    });
    if (hadFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _contentFocusNode.requestFocus();
      });
    }
  }

  Widget _buildReplyContext() {
    final theme = Theme.of(context);
    final target = _replyToPost;
    final title = widget.topicTitle?.trim();
    final (label, icon) = _isEditMode
        ? ('#${widget.editPost!.postNumber}', Symbols.edit_rounded)
        : _isPrivateMessage && _recipients.isNotEmpty
        ? (_recipients.map((name) => '@$name').join(', '), Symbols.mail_rounded)
        : target != null
        ? ('@${target.username} · #${target.postNumber}', Symbols.reply_rounded)
        : title != null && title.isNotEmpty
        ? (title, Symbols.reply_rounded)
        : (_viewMode.label, _viewMode.icon);
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            AppIcon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _previewHadFocus = false;

  void _togglePreview() {
    final leaving = _showPreview;
    if (!leaving) {
      _previewHadFocus = _contentFocusNode.hasFocus;
      if (!_flushRichContent()) return;
      _editorKey.currentState?.closeEmojiPanel();
      _richKey.currentState?.closeEmojiPanel();
      FocusScope.of(context).unfocus();
    }
    setState(() => _showPreview = !leaving);
    if (leaving && _previewHadFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _editorKey.currentState?.resumeEditing();
        _richKey.currentState?.resumeEditing();
      });
    }
  }

  void _showQuickPanel() {
    if (_showPreview) _togglePreview();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editorKey.currentState?.showQuickPanel();
      _richKey.currentState?.showQuickPanel();
    });
  }

  Widget _buildHeaderActions(
    double availableWidth, {
    double? minimumTitleWidth,
  }) => ComposerHeaderActions(
    availableWidth: availableWidth,
    minimumTitleWidth: minimumTitleWidth,
    submitLabel: _isEditMode
        ? context.l10n.common_save
        : context.l10n.common_send,
    submitIcon: _isEditMode ? AppIcons.check : null,
    onSubmit: (_isSubmitting || _isLoadingRaw) ? null : _submit,
    submitting: _isSubmitting,
    previewing: _showPreview,
    onTogglePreview: !_isSubmitting && !_isLoadingRaw ? _togglePreview : null,
    draftStatus: _draftController?.statusNotifier,
    onRetryDraft: _isSubmitting ? null : _retryDraftSave,
    showDiscard: _draftController != null,
    onDiscard: _isSubmitting ? null : _discardDraft,
    reviewBuilder:
        _canReviewPost && ref.watch(preferencesProvider).aiPostReviewEnabled
        ? (builder) => AiPostReviewButton(
            titleBuilder: () => widget.topicTitle,
            contentBuilder: () {
              if (!_flushRichContent()) return '';
              return _contentController.text;
            },
            target: AiPostReviewTarget.reply,
            enabled: !_isSubmitting && !_isLoadingRaw,
            builder: (_, reviewing, trigger) => builder(reviewing, trigger),
          )
        : null,
  );

  /// 恢复 Discourse 的 composer 动作菜单；当前回复目标与最初的回链来源独立。
  Widget _buildComposerActionMenu() {
    final origin = widget.replyToPost;
    final actions = <_ComposerAction>[
      _ComposerAction.replyToTopic,
      if (origin != null && origin.postNumber > 1) _ComposerAction.replyToPost,
      if (!widget.isPrivateMessageTopic) _ComposerAction.newTopic,
      _ComposerAction.newPrivateMessage,
    ];
    final selected = _isPrivateMessage
        ? _ComposerAction.newPrivateMessage
        : _replyToPost == null
        ? _ComposerAction.replyToTopic
        : _ComposerAction.replyToPost;

    String label(_ComposerAction action) => switch (action) {
      _ComposerAction.replyToTopic => context.l10n.post_replyToTopic,
      _ComposerAction.replyToPost =>
        '${context.l10n.post_replyToUser(origin!.username)} · #${origin.postNumber}',
      _ComposerAction.newTopic => context.l10n.drafts_newTopic,
      _ComposerAction.newPrivateMessage => context.l10n.pm_newTitle,
    };
    IconData actionIcon(_ComposerAction action) => switch (action) {
      _ComposerAction.replyToTopic => Icons.reply_all_rounded,
      _ComposerAction.replyToPost => Icons.reply_rounded,
      _ComposerAction.newTopic => Icons.post_add_rounded,
      _ComposerAction.newPrivateMessage => Icons.mail_outline_rounded,
    };

    return PopupMenuButton<_ComposerAction>(
      key: const ValueKey('reply-composer-action-menu'),
      tooltip: context.l10n.post_replyTo,
      enabled:
          !_isSubmitting &&
          !_isLoadingDraft &&
          !_isLoadingRaw &&
          !_switchingComposerAction,
      icon: const Icon(Icons.swap_horiz_rounded),
      onSelected: (action) async {
        if (_switchingComposerAction || action == selected) return;
        setState(() => _switchingComposerAction = true);
        try {
          switch (action) {
            case _ComposerAction.replyToTopic:
              await _switchToTopicReply();
              break;
            case _ComposerAction.replyToPost:
              if (origin != null) await _switchToTopicReply(target: origin);
              break;
            case _ComposerAction.newTopic:
              await _convertToNewTopic();
              break;
            case _ComposerAction.newPrivateMessage:
              await _switchToPrivateMessage();
              break;
          }
        } finally {
          if (mounted) setState(() => _switchingComposerAction = false);
        }
      },
      itemBuilder: (_) => [
        for (final action in actions)
          PopupMenuItem<_ComposerAction>(
            key: ValueKey('reply-composer-action-${action.name}'),
            value: action,
            child: Row(
              children: [
                Icon(actionIcon(action), size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(label(action))),
                if (action == selected) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_rounded, size: 18),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildHeaderTitle(
    ThemeData theme, {
    TextStyle? style,
    bool wrapTarget = false,
  }) {
    final target = _replyToPost;
    final label = _isEditMode
        ? context.l10n.post_editPostTitle(widget.editPost!.postNumber)
        : _isPrivateMessage
        ? (_recipients.isEmpty
              ? context.l10n.pm_newTitle
              : context.l10n.post_sendPmTitle(_recipients.join(', ')))
        : target != null
        ? context.l10n.post_replyToUser(target.username)
        : context.l10n.post_replyToTopic;
    return Row(
      children: [
        if (!_isEditMode && !_isPrivateMessage && target != null) ...[
          SmartAvatar(
            imageUrl: target.getAvatarUrl().isNotEmpty
                ? target.getAvatarUrl()
                : null,
            radius: 14,
            fallbackText: target.username,
            backgroundColor: theme.colorScheme.primaryContainer,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Tooltip(
            message: label,
            child: Text(
              wrapTarget ? '@${target!.username}' : label,
              key: const ValueKey('reply-composer-title-text'),
              style: style,
              maxLines: wrapTarget ? null : 1,
              overflow: wrapTarget
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResponsiveHeader(ThemeData theme, double width) {
    final target = _replyToPost;
    final compactTarget =
        (width < 600 || !PlatformUtils.isDesktop) &&
        !_isEditMode &&
        !_isPrivateMessage &&
        target != null;
    final style = compactTarget
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)
        : null;
    double? titleWidth;
    if (compactTarget) {
      final painter = TextPainter(
        text: TextSpan(
          text: context.l10n.post_replyToUser(target.username),
          style: style,
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      titleWidth = painter.width.ceilToDouble() + 28 + 8;
      painter.dispose();
    }
    // 56 navigation + 32 title margins + 44 more + 8 gap + 48 submit + 16 trailing.
    // When even the compact action row cannot fit the recipient, give it its
    // own full-width row instead of truncating the identity or shrinking taps.
    final separateTarget =
        compactTarget &&
        titleWidth! > width - (_canSwitchComposerAction ? 252 : 204);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: kToolbarHeight,
          child: AppBar(
            key: const ValueKey('reply-composer-header'),
            primary: false,
            centerTitle: false,
            automaticallyImplyLeading: false,
            leading: CloseButton(
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: separateTarget
                ? Text(context.l10n.common_reply)
                : _buildHeaderTitle(theme, style: style),
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            actions: [
              if (_canSwitchComposerAction) _buildComposerActionMenu(),
              _buildHeaderActions(
                width - (_canSwitchComposerAction ? 48 : 0),
                minimumTitleWidth: separateTarget ? width : titleWidth,
              ),
            ],
          ),
        ),
        if (separateTarget)
          Padding(
            key: const ValueKey('reply-composer-recipient-row'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _buildHeaderTitle(theme, style: style, wrapTarget: true),
          ),
      ],
    );
  }

  var _richKey = GlobalKey<RichComposerEditorState>();

  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _contentFocusNode = FocusNode();
  var _editorKey = GlobalKey<MarkdownEditorState>();

  // 编辑帖子时允许调整“回复至”目标楼层。
  final _editReplyTargetController = TextEditingController();
  final Map<int, Post> _editReplyTargetPreviewCache = <int, Post>{};
  Post? _editReplyTargetPreview;
  bool _isLoadingEditReplyTargetPreview = false;
  int _editReplyTargetPreviewGeneration = 0;

  bool _isSubmitting = false;
  bool _submitted = false; // 提交成功标志，防止 dispose 重新保存草稿
  bool _discarded = false; // 用户明确舍弃，防止 dispose 重新保存草稿
  bool _showEmojiPanel = false;
  bool _isLoadingRaw = false; // 编辑模式：加载原始内容中
  bool _isLoadingDraft = false; // 加载草稿中
  bool _restoringDraft = false;
  bool _reloadingDraft = false;

  // 表情面板高度
  static const double _emojiPanelHeight = 280.0;

  // 草稿控制器（仅在回复话题或创建私信时使用，编辑模式不使用）
  DraftController? _draftController;

  // Presence 服务（正在输入状态）
  PresenceService? _presenceService;

  // 私信收件人（初始为目标用户，从草稿恢复时还原草稿中的完整收件人列表）
  late List<String> _recipients = [
    if (widget.targetUsername != null) widget.targetUsername!,
  ];
  Post? _replyToPost;
  bool _composePrivateMessage = false;
  String? _syntheticContinuationPrefix;

  bool get _isPrivateMessage => _composePrivateMessage;

  bool get _canSwitchComposerAction => !_isEditMode && widget.topicId != null;
  bool _switchingComposerAction = false;

  /// 所有新建私信入口都允许继续增删收件人；已有私信话题回复不走这里。
  bool get _canEditRecipients => _isPrivateMessage && !_isEditMode;

  /// 是否在私信话题中（创建新私信 或 回复已有私信话题）
  bool get _isInPrivateMessageContext =>
      _isPrivateMessage || widget.isPrivateMessageTopic;
  bool get _isEditMode => widget.editPost != null;

  /// 当前正文最小字数（含 warden 等站点插件按分类的改写）
  ///
  /// 计数器分母与提交校验共用，避免「计数器说够了、提交却被拦」。
  int? _minPostLength;

  /// 正文实时长度（驱动计数器）
  int _contentLength = 0;

  /// 编辑模式改的是已有楼层，是否首帖按被编辑帖子的楼层号判断；
  /// 回复永远不是首帖。
  bool get _isFirstPost => _isEditMode && widget.editPost!.postNumber == 1;

  bool get _canReviewPost =>
      !_isEditMode &&
      !_isPrivateMessage &&
      !_isInPrivateMessageContext &&
      widget.topicId != null;

  int get _editReplyTargetNumber =>
      int.tryParse(_editReplyTargetController.text.trim()) ?? 0;

  @override
  void initState() {
    super.initState();
    EmojiHandler().init();
    _replyToPost = widget.replyToPost;
    _composePrivateMessage =
        widget.targetUsername != null || widget.composePrivateMessage;

    if (_isEditMode) {
      final replyTarget = widget.editPost!.replyToPostNumber;
      _editReplyTargetController.text = replyTarget > 0 ? '$replyTarget' : '';
      if (replyTarget > 0) {
        _scheduleEditReplyTargetPreview(replyTarget, notify: false);
      }
    }

    // 编辑模式：加载帖子原始内容
    if (_isEditMode) {
      _loadPostRaw();
    } else {
      // 预填内容（划词引用）
      if (widget.initialContent != null && widget.initialContent!.isNotEmpty) {
        _contentController.text = widget.initialContent!;
        // 光标移到末尾
        _contentController.selection = TextSelection.fromPosition(
          TextPosition(offset: _contentController.text.length),
        );
      }
      // 预填标题（私信模式）
      if (widget.initialTitle != null && widget.initialTitle!.isNotEmpty) {
        _titleController.text = widget.initialTitle!;
      }
      // 非编辑模式：初始化草稿控制器并加载草稿
      _initDraftController();
    }

    // 初始化 Presence 服务（非私信场景、非编辑模式）
    if (!_isInPrivateMessageContext && !_isEditMode && widget.topicId != null) {
      _presenceService = PresenceService(DiscourseService());
      _presenceService!.enterReplyChannel(widget.topicId!);
    }

    // 添加内容变化监听以触发草稿自动保存
    _contentController.addListener(_onContentChanged);
    _titleController.addListener(_onContentChanged);
    // 字数计数器单独监听：编辑模式下 _onContentChanged 会直接 return，
    // 但计数器在编辑帖子时同样需要实时更新
    _contentController.addListener(_onContentLengthChanged);
    _loadMinPostLength();
    _draftLifecycle = AppLifecycleListener(
      onInactive: _flushDraftForLifecycle,
      onPause: _flushDraftForLifecycle,
      onResume: () => _flushDraftForLifecycle(refresh: true),
    );

    // 自动聚焦（非编辑模式时立即聚焦，编辑模式在加载完成后聚焦）
    if (!_isEditMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isLoadingDraft) {
          _contentFocusNode.requestFocus();
        }
      });
    }
  }

  void _setEditReplyTargetNumber(int target) {
    if (!_isEditMode || widget.editPost!.postNumber <= 1) return;
    final maxTarget = widget.editPost!.postNumber - 1;
    final normalized = target < 0
        ? 0
        : target > maxTarget
        ? maxTarget
        : target;
    if (_editReplyTargetNumber == normalized) return;
    _editReplyTargetController.text = normalized == 0 ? '' : '$normalized';
    _scheduleEditReplyTargetPreview(normalized);
  }

  void _onEditReplyTargetInputChanged(String text) {
    final target = text.isEmpty ? 0 : int.tryParse(text);
    if (target == null || target < 0 || target >= widget.editPost!.postNumber) {
      ++_editReplyTargetPreviewGeneration;
      setState(() {
        _editReplyTargetPreview = null;
        _isLoadingEditReplyTargetPreview = false;
      });
      return;
    }
    _scheduleEditReplyTargetPreview(target);
  }

  void _scheduleEditReplyTargetPreview(int target, {bool notify = true}) {
    final generation = ++_editReplyTargetPreviewGeneration;
    if (target <= 0 || widget.topicId == null) {
      _editReplyTargetPreview = null;
      _isLoadingEditReplyTargetPreview = false;
      if (notify && mounted) setState(() {});
      return;
    }

    final cached = _editReplyTargetPreviewCache[target];
    if (cached != null) {
      _editReplyTargetPreview = cached;
      _isLoadingEditReplyTargetPreview = false;
      if (notify && mounted) setState(() {});
      return;
    }

    _editReplyTargetPreview = null;
    _isLoadingEditReplyTargetPreview = true;
    if (notify && mounted) setState(() {});

    Future<void>.delayed(const Duration(milliseconds: 120), () async {
      if (!mounted || generation != _editReplyTargetPreviewGeneration) return;
      try {
        final post = await DiscourseService().getPostByNumber(
          widget.topicId!,
          target,
        );
        if (!mounted ||
            generation != _editReplyTargetPreviewGeneration ||
            _editReplyTargetNumber != target) {
          return;
        }
        _editReplyTargetPreviewCache[target] = post;
        setState(() {
          _editReplyTargetPreview = post;
          _isLoadingEditReplyTargetPreview = false;
        });
      } catch (_) {
        if (!mounted ||
            generation != _editReplyTargetPreviewGeneration ||
            _editReplyTargetNumber != target) {
          return;
        }
        setState(() {
          _editReplyTargetPreview = null;
          _isLoadingEditReplyTargetPreview = false;
        });
      }
    });
  }

  String _editReplyTargetPreviewText(Post post) {
    return post.cooked
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Widget _buildEditReplyTargetSelector(ThemeData theme) {
    final maxTarget = widget.editPost!.postNumber - 1;
    final selected = _editReplyTargetNumber;
    final preview = _editReplyTargetPreview;
    final isTopicReply = selected == 0;
    final previewText = preview == null
        ? ''
        : _editReplyTargetPreviewText(preview);
    final previewName = preview == null
        ? null
        : ((preview.name?.trim().isNotEmpty ?? false)
              ? preview.name!.trim()
              : preview.username);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.45,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 140),
              child: Row(
                key: ValueKey<int>(selected),
                children: [
                  if (isTopicReply)
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      child: Icon(
                        Icons.reply_all_rounded,
                        size: 18,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    )
                  else if (preview != null)
                    SmartAvatar(
                      imageUrl: preview.getAvatarUrl().isNotEmpty
                          ? preview.getAvatarUrl()
                          : null,
                      radius: 17,
                      fallbackText: preview.username,
                      backgroundColor: theme.colorScheme.primaryContainer,
                    )
                  else
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: _isLoadingEditReplyTargetPreview
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            )
                          : Icon(
                              Icons.reply_rounded,
                              size: 18,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isTopicReply
                              ? context.l10n.post_replyToTopic
                              : preview == null
                              ? '${context.l10n.post_replyTo} · #$selected'
                              : '@${preview.username} · #$selected',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (!isTopicReply && preview != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            previewText.isEmpty
                                ? previewName!
                                : '$previewName · $previewText',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // 大话题直接输入楼层号，避免上千个 slider 分段难以精确操作。
            if (maxTarget <= 100)
              Slider(
                min: 0,
                max: maxTarget.toDouble(),
                divisions: maxTarget,
                value: selected
                    .toDouble()
                    .clamp(0.0, maxTarget.toDouble())
                    .toDouble(),
                label: isTopicReply
                    ? context.l10n.post_replyToTopic
                    : '#$selected',
                onChanged: _isSubmitting
                    ? null
                    : (value) => _setEditReplyTargetNumber(value.round()),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('edit-reply-target-number'),
                    controller: _editReplyTargetController,
                    enabled: !_isSubmitting,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      isDense: true,
                      prefixText: '#',
                      labelText: context.l10n.post_replyTo,
                      hintText: '1–$maxTarget',
                    ),
                    onChanged: _onEditReplyTargetInputChanged,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => _setEditReplyTargetNumber(0),
                  child: Text(context.l10n.post_replyToTopic),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 初始化草稿控制器
  void _initDraftController() {
    String draftKey;
    var shouldLoadDraft = true;
    if (widget.draftKey != null) {
      // 草稿列表入口：沿用原草稿 key 恢复
      draftKey = widget.draftKey!;
    } else if (_isPrivateMessage) {
      // 对齐 Discourse（services/composer.js privateMessageDraftKey）：
      // 新私信用带时间戳的唯一 key，不自动带回其他私信的草稿，
      // 避免给 A 写一半的草稿被带进给 B 的私信窗口造成串发
      draftKey = Draft.generateNewPrivateMessageKey();
      shouldLoadDraft = false; // 全新 key 服务端必无草稿，跳过加载
    } else if (widget.topicId != null) {
      // 区分回复话题和回复帖子
      draftKey = Draft.replyKey(
        widget.topicId!,
        replyToPostNumber: _replyToPost?.postNumber,
      );
    } else {
      return;
    }

    _draftController = DraftController(
      draftKey: draftKey,
      localStore: ref.read(localDraftStoreProvider),
      onRemoteDraftChanged: (data) {
        if (mounted &&
            !_submitted &&
            !_discarded &&
            (!_isLoadingDraft || _reloadingDraft)) {
          _restoreDraft(
            Draft(draftKey: draftKey, data: data),
            appendInitialContent: false,
          );
        }
      },
      currentEditorData: () {
        if (!mounted || (_isLoadingDraft && !_reloadingDraft)) return null;
        if (!_flushRichContent()) return null;
        return _currentDraftData();
      },
    );
    if (shouldLoadDraft) {
      _loadExistingDraft();
    }
  }

  /// 加载现有草稿
  Future<void> _loadExistingDraft() async {
    setState(() => _isLoadingDraft = true);
    try {
      final draft = await _draftController?.loadDraft(
        preloadedDraftFuture: widget.preloadedDraftFuture,
      );
      if (!mounted) return;

      if (draft != null && draft.hasContent) {
        // 回复模式直接恢复，不需要确认
        _restoreDraft(draft);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingDraft = false);
        if (widget.initialContent?.isNotEmpty == true) _onContentChanged();
        _contentFocusNode.requestFocus();
      }
    }
  }

  /// 舍弃草稿
  Future<void> _discardDraft() async {
    final confirm = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.post_discardTitle),
        content: Text(context.l10n.post_discardConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.common_discard),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      _discarded = true;
      await _draftController?.deleteDraft();
      if (mounted) Navigator.of(context).pop();
    }
  }

  /// 恢复草稿内容
  void _restoreDraft(Draft draft, {bool appendInitialContent = true}) {
    _restoringDraft = true;
    _richKey.currentState?.prepareForDocumentReplacement();
    _richKey = GlobalKey<RichComposerEditorState>();
    _editorKey = GlobalKey<MarkdownEditorState>();
    try {
      final prefix = appendInitialContent ? widget.initialContent ?? '' : '';
      _contentController.text = '$prefix${draft.data.reply ?? ''}';
      if (_isPrivateMessage) {
        _titleController.text = draft.data.title ?? '';
        setState(
          () => _recipients = List.of(draft.data.recipients ?? const []),
        );
      }
    } finally {
      _restoringDraft = false;
    }
    setState(() {});
  }

  /// 内容变化时触发草稿保存
  /// 同步正文长度到计数器
  void _onContentLengthChanged() {
    final length = _contentController.text.length;
    if (length == _contentLength) return;
    setState(() => _contentLength = length);
  }

  /// 解析当前上下文的最小正文字数（含插件按分类的改写）
  Future<void> _loadMinPostLength() async {
    final categoryId = widget.categoryId;
    final category = categoryId == null
        ? null
        : ref.read(categoryMapProvider).value?[categoryId];
    final min = await ComposerMinLengthResolver.resolve(
      category: category,
      isFirstPost: _isFirstPost,
      isPrivateMessage: _isInPrivateMessageContext,
      isPmWithNonHumanUser: widget.isPmWithNonHumanUser,
    );
    if (!mounted) return;
    setState(() => _minPostLength = min);
  }

  void _onContentChanged() {
    if (_isEditMode ||
        _draftController == null ||
        _isLoadingDraft ||
        _restoringDraft) {
      return;
    }

    _draftController!.scheduleSave(_currentDraftData());
  }

  DraftData _currentDraftData() => DraftData(
    reply: _contentController.text,
    title: _isPrivateMessage ? _titleController.text : null,
    action: _isPrivateMessage ? 'privateMessage' : 'reply',
    replyToPostNumber: _replyToPost?.postNumber,
    recipients: _isPrivateMessage ? _recipients : null,
    archetypeId: _isPrivateMessage ? 'private_message' : 'regular',
  );

  AppLifecycleListener? _draftLifecycle;
  void _flushDraftForLifecycle({bool refresh = false}) {
    if (!mounted ||
        _isSubmitting ||
        _isLoadingDraft ||
        _submitted ||
        _discarded) {
      return;
    }
    if (!_flushRichContent()) return;
    if (refresh) {
      _draftController?.scheduleSave(_currentDraftData());
      _draftController?.retryPending();
    } else {
      _draftController?.saveNow(_currentDraftData());
    }
  }

  Future<void> _reloadRemoteDraft() async {
    setState(() {
      _reloadingDraft = true;
      _isLoadingDraft = true;
    });
    try {
      if (await _draftController?.reloadFromRemote() != true && mounted) {
        ToastService.showError(S.current.composer_draftReloadFailed);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDraft = false;
          _reloadingDraft = false;
        });
      }
    }
  }

  bool _retryingDraft = false;
  Future<void> _retryDraftSave() async {
    if (_isSubmitting || _retryingDraft || _draftController == null) return;
    _retryingDraft = true;
    try {
      if (!_flushRichContent()) return;
      final force = _draftController!.hasConflict;
      if (force &&
          !await confirmComposerDraftOverwrite(
            context,
            onReload: _reloadRemoteDraft,
          )) {
        return;
      }
      if (!mounted) return;
      await _draftController!.saveNow(_currentDraftData(), forceSave: force);
    } finally {
      _retryingDraft = false;
    }
  }

  /// 收件人本身也是私信草稿的一部分；只改名单不继续输入也要及时保存。
  void _onRecipientsChanged(List<String> recipients) {
    setState(() => _recipients = recipients);
    _onContentChanged();
  }

  Future<void> _dropCurrentDraftForConversion() async {
    final previous = _draftController;
    _draftController = null;
    if (previous == null) return;
    previous.disable();
    try {
      await previous.deleteDraft();
    } catch (_) {
      // 动作切换不应被旧草稿清理失败阻塞；新模式会使用独立 draft key。
    } finally {
      previous.dispose();
    }
  }

  Future<void> _replaceComposerContent(String content) async {
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
        .replaceAll(']', r'\]');
  }

  String? _buildContinuationPrefix() {
    final topicId = widget.topicId;
    final topicTitle = widget.topicTitle?.trim();
    if (topicId == null || topicTitle == null || topicTitle.isEmpty) {
      return null;
    }

    // Discourse ComposerActionState 保留打开 composer 时的 post snapshot；
    // 即使用户先切到“回复话题”再转为新话题/私信，继续讨论链接仍应
    // 指向最初回复的楼层，而不是被可变的当前 action 清空。
    final postNumber = widget.replyToPost?.postNumber;
    final sourcePath = postNumber != null && postNumber > 0
        ? '/t/-/$topicId/$postNumber'
        : '/t/-/$topicId';
    final escapedTitle = _escapeContinuationLinkText(topicTitle);
    final sourceLink = '[$escapedTitle](${UrlHelper.resolveUrl(sourcePath)})';
    return context.l10n.post_continueDiscussion(sourceLink);
  }

  String _contentWithContinuation(String content) {
    final prefix = _buildContinuationPrefix();
    // 对齐 Discourse composer.open：已含同一 prependText 时不重复插入。
    if (prefix == null || prefix.isEmpty || content.contains(prefix)) {
      return content;
    }
    return content.isEmpty ? prefix : '$prefix\n\n$content';
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
    final next = current.isEmpty ? prefix : '$prefix\n\n$current';
    _syntheticContinuationPrefix = prefix;
    await _replaceComposerContent(next);
  }

  Future<void> _removeSyntheticContinuation() async {
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
    await _replaceComposerContent(next);
  }

  Future<void> _switchToTopicReply({Post? target}) async {
    if (_isEditMode || widget.topicId == null) return;
    _richKey.currentState?.flushToController();
    await _dropCurrentDraftForConversion();
    if (!mounted) return;
    await _removeSyntheticContinuation();
    if (!mounted) return;

    setState(() {
      _composePrivateMessage = false;
      _replyToPost = target;
      _recipients = [if (widget.targetUsername != null) widget.targetUsername!];
      _draftController = DraftController(
        draftKey: Draft.replyKey(
          widget.topicId!,
          replyToPostNumber: target?.postNumber,
        ),
        localStore: ref.read(localDraftStoreProvider),
      );
      _titleController.clear();
    });
    _onContentChanged();
    _contentFocusNode.requestFocus();
  }

  Future<void> _switchToPrivateMessage() async {
    if (_isEditMode || widget.topicId == null) return;
    _richKey.currentState?.flushToController();
    await _dropCurrentDraftForConversion();
    if (!mounted) return;
    await _applySyntheticContinuation();
    if (!mounted) return;

    setState(() {
      _composePrivateMessage = true;
      _replyToPost = null;
      _recipients = widget.privateMessageRecipients.toSet().toList();
      _draftController = DraftController(
        draftKey: Draft.generateNewPrivateMessageKey(),
        localStore: ref.read(localDraftStoreProvider),
      );
      if (_titleController.text.trim().isEmpty &&
          (widget.topicTitle?.trim().isNotEmpty ?? false)) {
        _titleController.text = widget.topicTitle!.trim();
      }
    });
    _onContentChanged();
    _contentFocusNode.requestFocus();
  }

  Future<void> _convertToNewTopic() async {
    if (_isEditMode) return;
    _richKey.currentState?.flushToController();
    final content = _contentWithContinuation(_contentController.text);
    await _dropCurrentDraftForConversion();
    if (!mounted) return;

    _submitted = true;
    final appNavigator = navigatorKey.currentState;
    Navigator.of(context).pop();
    await Future<void>.delayed(Duration.zero);
    appNavigator?.push(
      MaterialPageRoute(
        builder: (_) => CreateTopicPage(
          initialCategoryId: widget.categoryId,
          initialContent: content,
        ),
      ),
    );
  }

  /// 加载帖子原始内容
  Future<void> _loadPostRaw() async {
    setState(() => _isLoadingRaw = true);
    try {
      final raw = await DiscourseService().getPostRaw(widget.editPost!.id);
      if (mounted && raw != null) {
        _contentController.text = raw;
        // 加载完成后聚焦并将光标移到末尾
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _contentFocusNode.requestFocus();
          _contentController.selection = TextSelection.fromPosition(
            TextPosition(offset: _contentController.text.length),
          );
        });
      }
    } catch (e) {
      if (mounted) {
        _showError(
          S.current.post_loadContentFailed(
            e.toString().replaceAll('Exception: ', ''),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingRaw = false);
    }
  }

  @override
  void dispose() {
    final rich = _richKey.currentState;
    final currentContentSafe = rich != null
        ? rich.flushToController()
        : (_allowClose || _showPreview || _richFallback || !_richModeEnabled);
    _draftLifecycle?.dispose();
    // 移除监听器
    _contentController.removeListener(_onContentChanged);
    _titleController.removeListener(_onContentChanged);
    _contentController.removeListener(_onContentLengthChanged);

    // 关闭时处理草稿：已提交则跳过，有内容则保存，无内容则删除
    if (currentContentSafe &&
        _draftController != null &&
        !_submitted &&
        !_discarded &&
        !_isLoadingDraft) {
      final hasContent =
          _contentController.text.trim().isNotEmpty ||
          (_isPrivateMessage && _titleController.text.trim().isNotEmpty);
      if (hasContent) {
        final data = DraftData(
          reply: _contentController.text,
          title: _isPrivateMessage ? _titleController.text : null,
          action: _isPrivateMessage ? 'privateMessage' : 'reply',
          replyToPostNumber: _replyToPost?.postNumber,
          recipients: _isPrivateMessage ? _recipients : null,
          archetypeId: _isPrivateMessage ? 'private_message' : 'regular',
        );
        // 异步保存，不阻塞 dispose
        _draftController!.saveNow(data);
      } else {
        // 内容为空，删除草稿
        _draftController!.deleteDraft();
      }
    }
    _draftController?.dispose();

    // 释放 Presence 服务（会自动离开频道）
    _presenceService?.dispose();

    _editReplyTargetPreviewGeneration++;
    _titleController.dispose();
    _contentController.dispose();
    _editReplyTargetController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  void _showError(String message) {
    showAppDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.common_hint),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.common_confirm),
          ),
        ],
      ),
    );
  }

  Future<Post> _updateEditedPostWithReplyTarget({
    required String raw,
    required int? replyToPostNumber,
  }) async {
    final response = await DiscourseService().dio.put(
      '/posts/${widget.editPost!.id}.json',
      data: <String, dynamic>{
        'post[raw]': raw,
        // Discourse PostsController 检查 key 是否存在；空值会规范化为 null。
        'post[reply_to_post_number]': replyToPostNumber?.toString() ?? '',
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );

    final data = response.data;
    if (data is Map && data['post'] is Map) {
      return Post.fromJson(Map<String, dynamic>.from(data['post'] as Map));
    }
    throw Exception(S.current.error_updatePostFailed);
  }

  List<Object?> _submissionValues() => [
    _contentController.text,
    _titleController.text,
    ..._recipients,
  ];

  bool _submissionPending = false;

  Future<void> _submit() async {
    if (_submissionPending || _isSubmitting) return;
    _submissionPending = true;
    try {
      await _submitChecked();
    } finally {
      _submissionPending = false;
    }
  }

  Future<void> _submitChecked() async {
    if ((_editorKey.currentState?.hasPendingUploads ?? false) ||
        (_richKey.currentState?.hasPendingUploads ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(UploadTaskLabels.of(context).pendingSubmit)),
      );
      return;
    }

    // 富文本模式:镜像 debounce 窗口内提交也不丢内容,先强制序列化
    if (!_flushRichContent()) return;
    final approved = ComposerSubmissionSnapshot(_submissionValues());
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      _showError(S.current.post_contentRequired);
      return;
    }

    int? editedReplyTarget;
    var editedReplyTargetChanged = false;
    if (_isEditMode && widget.editPost!.postNumber > 1) {
      final targetText = _editReplyTargetController.text.trim();
      if (targetText.isNotEmpty) {
        final parsed = int.tryParse(targetText);
        final maxTarget = widget.editPost!.postNumber - 1;
        if (parsed == null || parsed < 1 || parsed > maxTarget) {
          _showError('${context.l10n.post_replyTo}: #1 - #$maxTarget');
          return;
        }
        editedReplyTarget = parsed;
      }
      final currentTarget = widget.editPost!.replyToPostNumber > 0
          ? widget.editPost!.replyToPostNumber
          : null;
      editedReplyTargetChanged = editedReplyTarget != currentTarget;
    }

    // 最小字数校验：与计数器共用同一份解析结果（含 warden 按分类改写），
    // 否则在搞七捻三（16）这类分类下会出现计数器与校验不一致
    final minLength =
        _minPostLength ??
        await ComposerMinLengthResolver.resolve(
          category: widget.categoryId == null
              ? null
              : ref.read(categoryMapProvider).value?[widget.categoryId],
          isFirstPost: _isFirstPost,
          isPrivateMessage: _isInPrivateMessageContext,
          isPmWithNonHumanUser: widget.isPmWithNonHumanUser,
        );
    if (content.length < minLength) {
      ToastService.showInfo(S.current.createTopic_minContentLength(minLength));
      return;
    }

    if (_isPrivateMessage && _titleController.text.trim().isEmpty) {
      _showError(S.current.post_titleRequired);
      return;
    }

    // 新建私信必须至少保留一个收件人。
    if (_isPrivateMessage && _recipients.isEmpty) {
      _showError(S.current.pm_noRecipient);
      return;
    }

    // 站点插件发送前钩子（对齐 Discourse `composerBeforeSave`）：
    // 如 linux.do 回复扣积分需要先弹确认框，用户取消则不发送。
    // 放在校验之后、置 _isSubmitting 之前，避免取消后按钮卡在 loading。
    // 前面的最小字数校验有 await，用 context 前先确认本弹框还在。
    if (!mounted) return;
    final pluginAllowed = await PluginRegistry.runBeforeReplySubmit(
      ReplySubmitContext(
        context: context,
        topic: TopicPluginContext(
          topicId: widget.topicId,
          topicJson: TopicPluginData.of(widget.topicId),
        ),
        isEditing: _isEditMode,
        isPrivateMessage: _isPrivateMessage,
      ),
    );
    if (!pluginAllowed || !mounted) return;

    if (_draftController?.hasConflict == true &&
        !await confirmComposerDraftOverwrite(
          context,
          onReload: _reloadRemoteDraft,
        )) {
      return;
    }
    if (!mounted) return;
    if (!mounted) return;
    if (!approved.verify(
      synchronize: _flushRichContent,
      read: _submissionValues,
    )) {
      return;
    }
    setState(() => _isSubmitting = true);
    // 对齐 Discourse 前端 composer.set("disableDrafts", true):
    // 发送途中关掉自动保存,避免与 PostCreator 推进的 draft_sequence 撞 409
    _draftController?.disable();

    try {
      if (_isEditMode) {
        // 编辑模式：更新帖子；回复目标变化时使用带目标字段的请求。
        final updatedPost = editedReplyTargetChanged
            ? await _updateEditedPostWithReplyTarget(
                raw: content,
                replyToPostNumber: editedReplyTarget,
              )
            : await DiscourseService().updatePost(
                postId: widget.editPost!.id,
                raw: content,
              );
        if (!mounted) return;
        Navigator.of(context).pop(updatedPost);
      } else if (_isPrivateMessage) {
        await DiscourseService().createPrivateMessage(
          targetUsernames: _recipients,
          title: _titleController.text.trim(),
          raw: content,
          draftKey: _draftController?.draftKey,
          onDraftSequence: (seq) => _draftController?.syncSequence(seq),
        );
        // 发送成功后删除草稿
        await _draftController?.deleteDraft();
        _submitted = true;
        if (!mounted) return;
        Navigator.of(context).pop(null); // 私信模式不返回 Post
      } else {
        // 回复模式：返回创建的 Post 对象
        final newPost = await DiscourseService().createReply(
          topicId: widget.topicId!,
          raw: content,
          replyToPostNumber: _replyToPost?.postNumber,
          draftKey: _draftController?.draftKey,
          onDraftSequence: (seq) => _draftController?.syncSequence(seq),
        );
        // 发送成功后删除草稿
        await _draftController?.deleteDraft();
        _submitted = true;
        if (!mounted) return;
        Navigator.of(context).pop(newPost);
      }
    } on PostEnqueuedException catch (e) {
      // 审核场景：删除草稿，提示用户，关闭编辑器
      await _draftController?.deleteDraft();
      _submitted = true;
      if (!mounted) return;
      final pending = e.pendingPost;
      if (pending != null &&
          widget.editPost == null &&
          widget.topicId != null) {
        // enqueued 响应的 pending_post 只有 {id, raw, created_at},回复目标
        // 服务端 payload 存了但本人可见接口都不吐;趁 composer 还知道上下文
        // 记入注册表,「撤回并重新编辑」才能恢复"回复某楼"而非退化为直接回复话题
        PendingReplyTargetRegistry.record(pending.id, _replyToPost?.postNumber);
      }
      if (widget.onEnqueued != null && pending != null) {
        // 宿主接管展示(如主题页底部待审块),轻提示即可
        widget.onEnqueued!(pending);
        ToastService.showInfo(S.current.post_pendingReview);
      } else {
        // 无宿主接管:toast 带「查看」入口跳待审列表页
        ToastService.show(
          S.current.post_pendingReview,
          type: ToastType.info,
          actionLabel: S.current.review_viewAction,
          onAction: () {
            navigatorKey.currentState?.push(
              MaterialPageRoute(builder: (_) => const PendingPostsPage()),
            );
          },
        );
      }
      Navigator.of(context).pop();
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理:发送失败,恢复草稿保存
      _draftController?.enable();
    } catch (e, s) {
      _draftController?.enable();
      AppErrorHandler.handleUnexpected(e, s);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildCharCountOverlay() => CharacterCountsOverlay(
    length: _contentLength,
    minimumLength: _minPostLength,
  );

  @override
  Widget build(BuildContext context) {
    _richModeEnabled = ref.watch(preferencesProvider).useRichComposer;
    final theme = Theme.of(context);

    // 使用 FractionallySizedBox 固定 0.95 高度
    // SafeArea(bottom: false)：顶部安全区域由 SafeArea 处理，
    // 底部安全区域由 ChatBottomPanelContainer 内部管理，避免双重底部间距
    // CallbackShortcuts 包整个弹层:Cmd/Ctrl+Enter 提交(对齐 Discourse
    // composer),焦点在标题输入框时同样生效;守卫与发送按钮一致。
    final sheet = SafeArea(
      bottom: false,
      child: FractionallySizedBox(
        heightFactor: 0.95,
        alignment: Alignment.bottomCenter,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          // PopScope 用于处理表情面板开启时的返回逻辑
          body: PopScope(
            canPop: _allowClose && !_showEmojiPanel,
            onPopInvokedWithResult: (bool didPop, dynamic result) async {
              if (didPop) return;
              if (!_showEmojiPanel) {
                _closeWithCurrentContent(result);
                return;
              }
              if (_showEmojiPanel) {
                _editorKey.currentState?.closeEmojiPanel();
                _richKey.currentState?.closeEmojiPanel();
                setState(() => _showEmojiPanel = false);
              }
            },
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    children: [
                      // 1. 顶部 Header (固定)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 拖拽手柄
                          Container(
                            width: 32,
                            height: 4,
                            margin: const EdgeInsets.only(top: 12, bottom: 8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.outlineVariant,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),

                          LayoutBuilder(
                            builder: (context, bounds) =>
                                _buildResponsiveHeader(theme, bounds.maxWidth),
                          ),

                          Divider(
                            height: 1,
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ],
                      ),

                      if (_isEditMode && widget.editPost!.postNumber > 1)
                        _buildEditReplyTargetSelector(theme),

                      // 新建私信：所有入口都可增删收件人，预设对象保留为首个 chip。
                      if (_canEditRecipients)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: PmRecipientField(
                            recipients: _recipients,
                            autofocus: widget.targetUsername == null,
                            onChanged: _onRecipientsChanged,
                          ),
                        ),
                      // 私信标题输入框（仅私信模式）
                      if (_isPrivateMessage) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: _titleController,
                            decoration: InputDecoration(
                              hintText: context.l10n.common_title,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            textInputAction: TextInputAction.next,
                            onTap: () {
                              if (_showEmojiPanel) {
                                _editorKey.currentState?.closeEmojiPanel();
                                _richKey.currentState?.closeEmojiPanel();
                                setState(() => _showEmojiPanel = false);
                              }
                            },
                          ),
                        ),
                        Divider(
                          height: 1,
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.2,
                          ),
                        ),
                      ],

                      // 2. 编辑器区域(feature flag:富文本 / markdown;
                      // ComposerSwitchFade 无并存直切+淡入 —— 防双模
                      // 并存 IME 交接竞态,说明见 create_topic_page)
                      Expanded(
                        child: ComposerPreviewPane(
                          previewing: _showPreview,
                          previewFooter: ComposerPreviewFooter(
                            metadata: _buildReplyContext(),
                            rich:
                                ref
                                    .watch(preferencesProvider)
                                    .useRichComposer &&
                                !_richFallback,
                          ),
                          preview: _buildPreview(theme),
                          editor: ComposerSwitchFade(
                            child:
                                (ref.watch(
                                      preferencesProvider.select(
                                        (p) => p.useRichComposer,
                                      ),
                                    ) &&
                                    !_richFallback)
                                // 富文本的初始导入是一次性的(不监听 controller
                                // 后续变化)——编辑原帖 raw / 草稿加载完成前挂载
                                // 会用空 controller 建空文档,之后镜像回写覆盖
                                // 真内容(毁帖)。内容源就绪后才挂;占位留空,
                                // 加载视觉由草稿遮罩/RichComposer 自身统一提供
                                // (双 spinner 叠影)。
                                ? ((_isLoadingRaw ||
                                          (_isLoadingDraft && !_reloadingDraft))
                                      ? const SizedBox.shrink()
                                      : RichComposerEditor(
                                          key: _richKey,
                                          metaBar: PlatformUtils.isDesktop
                                              ? null
                                              : _buildReplyContext(),
                                          onSwitchToSource: () => _setViewMode(
                                            ComposerViewMode.source,
                                          ),
                                          controller: _contentController,
                                          enableStevessr: true,
                                          focusNode: _contentFocusNode,
                                          hintText:
                                              context.l10n.editor_hintText,
                                          bodyOverlay: _buildCharCountOverlay(),
                                          emojiPanelHeight: _emojiPanelHeight,
                                          onEmojiPanelChanged: (show) {
                                            setState(
                                              () => _showEmojiPanel = show,
                                            );
                                          },
                                          mentionDataSource: (term) =>
                                              DiscourseService().searchUsers(
                                                term: term,
                                                topicId: widget.topicId,
                                                categoryId: widget.categoryId,
                                                includeGroups:
                                                    !_isInPrivateMessageContext,
                                              ),
                                          onFallbackToPlain: () {
                                            if (mounted) {
                                              setState(
                                                () => _richFallback = true,
                                              );
                                            }
                                          },
                                          // 模式切换由编辑台承载。
                                        ))
                                : MarkdownEditor(
                                    key: _editorKey,
                                    metaBar: PlatformUtils.isDesktop
                                        ? null
                                        : _buildReplyContext(),
                                    onSwitchToRich:
                                        ref
                                            .watch(preferencesProvider)
                                            .useRichComposer
                                        ? () => _setViewMode(
                                            ComposerViewMode.rich,
                                          )
                                        : null,
                                    controller: _contentController,
                                    focusNode: _contentFocusNode,
                                    hintText: context.l10n.editor_hintText,
                                    expands: true,
                                    // 预览已由头部切换器统一承载(对富文本也生效)
                                    showPreviewButton: false,
                                    bodyOverlay: _buildCharCountOverlay(),
                                    emojiPanelHeight: _emojiPanelHeight,
                                    onEmojiPanelChanged: (show) {
                                      setState(() => _showEmojiPanel = show);
                                    },
                                    mentionDataSource: (term) =>
                                        DiscourseService().searchUsers(
                                          term: term,
                                          topicId: widget.topicId,
                                          categoryId: widget.categoryId,
                                          includeGroups:
                                              !_isInPrivateMessageContext, // 私信不允许提及群组
                                        ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 草稿加载遮罩
                if (_isLoadingDraft)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(alpha: 0.7),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                      child: const Center(child: LoadingSpinner()),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return CallbackShortcuts(
      bindings: {
        for (final activator in composerQuickPanelActivators())
          activator: _showQuickPanel,
        for (final activator in composerSubmitActivators())
          activator: () {
            if (!_isSubmitting && !_isLoadingRaw) _submit();
          },
      },
      child: sheet,
    );
  }
}
