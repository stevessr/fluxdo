import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluxdo/widgets/common/error_view.dart';
import 'package:fluxdo/widgets/common/progressive_top_blur.dart';
import 'package:m3e_ui/m3e_ui.dart';
import 'package:fluxdo/providers/preferences_provider.dart';
import 'package:fluxdo/widgets/markdown_editor/composer_shortcuts.dart';
import 'package:fluxdo/widgets/markdown_editor/composer_switch_fade.dart';
import 'package:fluxdo/widgets/markdown_editor/markdown_editor.dart';
import 'package:fluxdo/widgets/markdown_editor/poll_builder_dialog.dart';
import 'package:fluxdo/widgets/markdown_editor/rich_composer/rich_composer_editor.dart';
import 'package:fluxdo/models/category.dart';
import 'package:fluxdo/models/draft.dart';
import 'package:fluxdo/models/shortcut_binding.dart';

import 'package:fluxdo/providers/discourse_providers.dart';
import 'package:fluxdo/services/toast_service.dart';
import 'package:dio/dio.dart';
import 'package:fluxdo/services/ai_post_review_service.dart';
import 'package:fluxdo/services/app_error_handler.dart';
import 'package:fluxdo/services/network/exceptions/api_exception.dart';
import 'package:fluxdo/widgets/ai/ai_post_review_button.dart';
import 'package:fluxdo/widgets/markdown_editor/markdown_renderer.dart';
import 'package:fluxdo/services/draft_controller.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';
import 'package:fluxdo/providers/shortcut_provider.dart';
import 'package:fluxdo/widgets/topic/topic_editor_helpers.dart';
import 'package:fluxdo/services/local_notification_service.dart'
    show navigatorKey;
import '../l10n/s.dart';
import '../utils/dialog_utils.dart';
import '../utils/discourse_url_parser.dart';
import 'pending_posts_page.dart';

enum _TopicComposeType { regular, poll, postVoting }

class CreateTopicPage extends ConsumerStatefulWidget {
  final int? initialCategoryId;
  final List<String>? initialTags;

  /// 预填标题/内容(待审内容撤回重编辑等场景);
  /// 传入任一时跳过草稿恢复弹窗,避免覆盖预填
  final String? initialTitle;
  final String? initialContent;
  final String draftKey;

  const CreateTopicPage({
    super.key,
    this.initialCategoryId,
    this.initialTags,
    this.initialTitle,
    this.initialContent,
    this.draftKey = Draft.newTopicKey,
  });

  @override
  ConsumerState<CreateTopicPage> createState() => _CreateTopicPageState();
}

class _CreateTopicPageState extends ConsumerState<CreateTopicPage> {
  /// 富文本导入失败时本次会话降级纯文本
  bool _richFallback = false;
  final _richKey = GlobalKey<RichComposerEditorState>();

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _contentFocusNode = FocusNode();
  final _editorKey = GlobalKey<MarkdownEditorState>();
  late final ShortcutSurfaceBinding _shortcutSurfaceBinding =
      ShortcutSurfaceBinding(
        ref: ref,
        id: ShortcutSurfaceIds.createTopic,
        triggerAction: ShortcutAction.createTopic,
        kind: ShortcutSurfaceKind.route,
        repeatBehavior: ShortcutSurfaceRepeatBehavior.reveal,
        passthroughActions: ShortcutSurfaceActionSets.globalRoutePassthrough,
      );
  ModalRoute<dynamic>? _route;

  Category? _selectedCategory;
  List<String> _selectedTags = [];
  bool _isSubmitting = false;
  bool _submitted = false; // 提交成功标志，防止 dispose 重新保存草稿
  bool _discarded = false; // 用户明确舍弃，防止 dispose 重新保存草稿
  bool _showPreview = false;
  String? _templateContent;
  bool _isLoadingDraft = false;
  bool _showEmojiPanel = false;

  /// 创建话题的客户端一级类型。Discourse 服务端的 poll 仍然存储在
  /// 首帖 raw 中，但 composer 不再把它当“正文里可选插入的组件”：
  /// poll 类型由本页持有一个主 [PollSpec]，正文编辑器只编辑投票说明。
  _TopicComposeType _topicType = _TopicComposeType.regular;
  PollSpec? _pollSpec;

  Timer? _featuredLinkDebounce;
  int _titleChangeGeneration = 0;
  bool _isResolvingFeaturedLink = false;
  bool _updatingFeaturedLinkTitle = false;
  String? _featuredLink;

  final PageController _pageController = PageController();
  int _contentLength = 0;

  // 草稿控制器
  late final DraftController _draftController;

  bool get _isPollTopic => _topicType == _TopicComposeType.poll;
  bool get _createAsPostVoting =>
      _topicType == _TopicComposeType.postVoting;

  /// 官方 poll 插件通过 current_user.can_create_poll 做最终权限判断，
  /// poll_enabled 是 client:true 的插件总开关。两者都满足才展示投票类型。
  bool get _canCreatePoll {
    final preloaded = PreloadedDataService();
    return preloaded.siteSettingsSync?['poll_enabled'] == true &&
        preloaded.currentUserSync?['can_create_poll'] == true;
  }

  bool get _isChinese =>
      Localizations.localeOf(context).languageCode.toLowerCase().startsWith('zh');

  @override
  void initState() {
    super.initState();
    _contentController.addListener(_updateContentLength);

    // 初始化草稿控制器
    _draftController = DraftController(draftKey: widget.draftKey);

    // 添加草稿自动保存监听
    _titleController.addListener(_onTitleChanged);
    _titleController.addListener(_onDraftContentChanged);
    _contentController.addListener(_onDraftContentChanged);

    // 预填标题/内容(待审内容撤回重编辑等场景):直接落 controller,
    // 并跳过草稿恢复弹窗,避免旧草稿覆盖预填内容
    final hasInitialPrefill = (widget.initialTitle?.isNotEmpty ?? false) ||
        (widget.initialContent?.isNotEmpty ?? false);
    if (hasInitialPrefill) {
      if (widget.initialTitle != null) {
        _titleController.text = widget.initialTitle!;
      }
      if (widget.initialContent != null) {
        _loadComposerRaw(widget.initialContent!);
      }
    } else {
      // 加载现有草稿
      _loadExistingDraft();
    }

    // 从当前筛选条件自动填入分类和标签
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyCurrentFilter());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == null || identical(route, _route)) return;
    _route = route;
    _shortcutSurfaceBinding.registerDeferred(
      context,
      onClose: () => Navigator.of(context).maybePop(),
      onFocus: _revealSelf,
    );
  }

  void _revealSelf() {
    final route = _route;
    final navigator = route?.navigator;
    if (route == null || navigator == null || route.isCurrent) return;
    navigator.popUntil((candidate) => identical(candidate, route));
  }

  /// 加载现有草稿
  Future<void> _loadExistingDraft() async {
    setState(() => _isLoadingDraft = true);
    try {
      final draft = await _draftController.loadDraft();
      if (!mounted) return;

      if (draft != null && draft.hasContent) {
        // 弹出恢复草稿对话框
        final restore = await _showRestoreDraftDialog();
        if (restore == true && mounted) {
          _restoreDraft(draft);
        } else if (restore == false && mounted) {
          // 用户选择丢弃，删除草稿
          await _draftController.deleteDraft();
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingDraft = false);
      }
    }
  }

  /// 显示恢复草稿对话框
  Future<bool?> _showRestoreDraftDialog() async {
    return showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.createTopic_restoreDraft),
        content: Text(context.l10n.createTopic_restoreDraftContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.common_discard),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.common_restore),
          ),
        ],
      ),
    );
  }

  /// 从 raw 中识别“首个且位于正文开头”的主投票。这样 poll 类型草稿
  /// 仍完全兼容 Discourse 原生 draft data，不需要私有扩展字段；普通正文
  /// 中间插入的附加投票不会被误判成话题类型。
  (PollSpec, String)? _splitPrimaryPoll(String raw) {
    final match = RegExp(
      r'^\s*(\[poll(?:\s[^\]]*)?\][\s\S]*?\[/poll\])(?:\s*\n\s*\n)?([\s\S]*)$',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match == null) return null;
    final spec = PollSpec.tryParse(match.group(1)!);
    if (spec == null) return null;
    return (spec, match.group(2)?.trimLeft() ?? '');
  }

  /// 将服务端/草稿 raw 映射回 composer 模型。投票帖把主 poll 从正文
  /// controller 拆出来，正文编辑器只保留说明文字。
  void _loadComposerRaw(String raw) {
    final parsed = _splitPrimaryPoll(raw);
    if (parsed != null) {
      _topicType = _TopicComposeType.poll;
      _pollSpec = parsed.$1;
      _contentController.text = parsed.$2;
      _templateContent = null;
      return;
    }
    _topicType = _TopicComposeType.regular;
    _pollSpec = null;
    _contentController.text = raw;
  }

  /// 恢复草稿内容
  void _restoreDraft(Draft draft) {
    if (draft.data.title != null) {
      _titleController.text = draft.data.title!;
    }
    if (draft.data.reply != null) {
      _loadComposerRaw(draft.data.reply!);
    }
    if (draft.data.tags != null && draft.data.tags!.isNotEmpty) {
      setState(() => _selectedTags = List.from(draft.data.tags!));
    } else {
      // _loadComposerRaw 会改变一级帖子类型；即使没有标签也要刷新类型 UI。
      setState(() {});
    }
    // 分类需要在 categories 加载后设置，通过 _applyCurrentFilter 中处理
    if (draft.data.categoryId != null) {
      // 监听 categories 加载完成后设置分类
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreCategoryFromDraft(draft.data.categoryId!);
      });
    }
  }

  /// 从草稿恢复分类
  void _restoreCategoryFromDraft(int categoryId) {
    ref.listenManual(categoriesProvider, (previous, next) {
      next.whenData((categories) {
        if (!mounted) return;
        final category = categories
            .where((c) => c.id == categoryId)
            .firstOrNull;
        if (category != null && category.canCreateTopic) {
          setState(() => _selectedCategory = category);
        }
      });
    }, fireImmediately: true);
  }

  /// 将当前 composer 模型序列化成真正提交给 Discourse 的首帖 raw。
  /// poll 类型固定“主投票在前、说明正文在后”，不把投票块塞进正文编辑器。
  String _serializedContent() {
    if (!_isPollTopic || _pollSpec == null) return _contentController.text;
    final poll = _pollSpec!.toBBCode(existingPollCount: 0);
    final body = _contentController.text.trim();
    if (body.isEmpty) return poll;
    return '$poll\n\n${_contentController.text.trimLeft()}';
  }

  DraftData _currentDraftData() => DraftData(
    title: _titleController.text,
    reply: _serializedContent(),
    categoryId: _selectedCategory?.id,
    tags: _selectedTags.isNotEmpty ? _selectedTags : null,
    action: 'createTopic',
    archetypeId: 'regular',
  );

  /// 草稿内容变化时触发保存
  void _onDraftContentChanged() {
    _draftController.scheduleSave(_currentDraftData());
  }

  /// 舍弃草稿
  Future<void> _discardDraft() async {
    final confirm = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.createTopic_discardPost),
        content: Text(context.l10n.createTopic_discardPostContent),
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
      await _draftController.deleteDraft();
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _applyCurrentFilter() async {
    // 优先使用传入的分类，否则使用站点默认分类
    int? targetCategoryId = widget.initialCategoryId;
    targetCategoryId ??= await PreloadedDataService()
        .getDefaultComposerCategoryId();

    // 应用传入的标签
    if (widget.initialTags != null &&
        widget.initialTags!.isNotEmpty &&
        _selectedTags.isEmpty) {
      setState(() => _selectedTags = List.from(widget.initialTags!));
    }

    if (targetCategoryId != null && mounted) {
      // 监听 categories 加载完成
      ref.listenManual(categoriesProvider, (previous, next) {
        next.whenData((categories) {
          if (!mounted) return;
          final category = categories
              .where((c) => c.id == targetCategoryId)
              .firstOrNull;
          if (category != null &&
              category.canCreateTopic &&
              _selectedCategory == null) {
            _onCategorySelected(category);
          }
        });
      }, fireImmediately: true);
    }
  }

  @override
  void dispose() {
    _shortcutSurfaceBinding.disposeDeferred();
    _featuredLinkDebounce?.cancel();
    // 移除草稿监听器
    _titleController.removeListener(_onTitleChanged);
    _titleController.removeListener(_onDraftContentChanged);
    _contentController.removeListener(_onDraftContentChanged);

    // 关闭时处理草稿：已提交则跳过，有标题/正文/主投票则保存。
    if (!_submitted && !_discarded) {
      if (_titleController.text.trim().isNotEmpty ||
          _contentController.text.trim().isNotEmpty ||
          (_isPollTopic && _pollSpec != null)) {
        _draftController.saveNow(_currentDraftData());
      } else {
        // 内容为空，删除草稿
        _draftController.deleteDraft();
      }
    }
    _draftController.dispose();

    _pageController.dispose();
    _contentController.removeListener(_updateContentLength);
    _titleController.dispose();
    _contentController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  void _updateContentLength() {
    setState(() => _contentLength = _contentController.text.length);
  }

  bool get _featuredLinkEnabled =>
      PreloadedDataService().siteSettingsSync?['topic_featured_link_enabled'] !=
      false;

  /// 对齐 Discourse composer：标题只包含一个 URL 时，异步取 onebox 标题，
  /// 并把原 URL 放入正文作为首个链接。
  void _onTitleChanged() {
    _featuredLinkDebounce?.cancel();
    final generation = ++_titleChangeGeneration;

    // 替换为 onebox 标题时不要把刚解析出的 featured_link 清掉。
    if (_updatingFeaturedLinkTitle) return;

    final candidate = DiscourseUrlParser.parseTitleUrl(_titleController.text);
    if (!_featuredLinkEnabled || candidate == null) {
      if (_isResolvingFeaturedLink || _featuredLink != null) {
        setState(() {
          _isResolvingFeaturedLink = false;
          _featuredLink = null;
        });
      }
      return;
    }

    // 同一个 URL 已经解析过时，不重复请求。
    if (_featuredLink == candidate.url) {
      if (_isResolvingFeaturedLink) {
        setState(() => _isResolvingFeaturedLink = false);
      }
      return;
    }

    setState(() {
      _isResolvingFeaturedLink = true;
      _featuredLink = null;
    });
    _featuredLinkDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_resolveFeaturedLink(candidate, generation));
    });
  }

  Future<void> _resolveFeaturedLink(
    TitleUrlInfo candidate,
    int generation,
  ) async {
    if (!_featuredLinkEnabled) {
      if (mounted && generation == _titleChangeGeneration) {
        setState(() {
          _isResolvingFeaturedLink = false;
          _featuredLink = null;
        });
      }
      return;
    }
    if (!_isCurrentTitleUrl(candidate, generation)) {
      return;
    }

    String? resolvedTitle;
    try {
      final boxes = await ref
          .read(discourseServiceProvider)
          .fetchInlineOneboxes([
            candidate.url,
          ], categoryId: _selectedCategory?.id)
          .timeout(const Duration(seconds: 5));
      resolvedTitle = boxes[candidate.url]?.title.trim();
    } catch (_) {
      // fetchInlineOneboxes 已将 onebox 失败降级为空结果；这里保留 URL。
    }

    if (!mounted || !_isCurrentTitleUrl(candidate, generation)) return;

    _appendFeaturedLinkToContent(candidate.url);
    setState(() {
      _featuredLink = candidate.url;
      _isResolvingFeaturedLink = false;
    });

    if (resolvedTitle != null && resolvedTitle.isNotEmpty) {
      _replaceTitleWithOneboxTitle(resolvedTitle);
    }
  }

  bool _isCurrentTitleUrl(TitleUrlInfo candidate, int generation) {
    return mounted &&
        generation == _titleChangeGeneration &&
        _featuredLinkEnabled &&
        _titleController.text.trim() == candidate.url;
  }

  void _appendFeaturedLinkToContent(String url) {
    final current = _contentController.text;
    if (!current.contains(url)) {
      final trimmed = current.trimRight();
      _contentController.text = trimmed.isEmpty ? url : '$trimmed\n\n$url';
    }

    final richEditor = _richKey.currentState;
    if (richEditor != null) {
      unawaited(richEditor.syncFromController());
    }
  }

  void _replaceTitleWithOneboxTitle(String title) {
    final resolvedTitle = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (resolvedTitle.isEmpty ||
        resolvedTitle == _titleController.text.trim()) {
      return;
    }

    _updatingFeaturedLinkTitle = true;
    try {
      _titleController.value = _titleController.value.copyWith(
        text: resolvedTitle,
        selection: TextSelection.collapsed(offset: resolvedTitle.length),
        composing: TextRange.empty,
      );
    } finally {
      _updatingFeaturedLinkTitle = false;
    }
  }

  void _onCategorySelected(Category category) {
    setState(() {
      _selectedCategory = category;
      // 分类强制问答时一级类型必须同步为问答；“默认问答”只在当前
      // 仍是普通帖子时应用，不覆盖用户已经显式选择的投票类型。
      if (category.onlyPostVotingInThisCategory ||
          (category.createAsPostVotingDefault &&
              _topicType == _TopicComposeType.regular)) {
        _topicType = _TopicComposeType.postVoting;
      }
    });

    final currentContent = _contentController.text.trim();
    if (currentContent.isEmpty ||
        (_templateContent != null &&
            currentContent == _templateContent!.trim())) {
      if (category.topicTemplate != null &&
          category.topicTemplate!.isNotEmpty) {
        _contentController.text = category.topicTemplate!;
        _templateContent = category.topicTemplate;
      } else {
        _contentController.clear();
        _templateContent = null;
      }
    }

    // 触发草稿保存
    _onDraftContentChanged();
  }

  /// 标签变化时触发草稿保存
  void _onTagsChanged(List<String> newTags) {
    setState(() => _selectedTags = newTags);
    _onDraftContentChanged();
  }

  void _togglePreview() {
    if (_showPreview) {
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      FocusScope.of(context).unfocus();
    }
  }

  String _topicTypeLabel(_TopicComposeType type) {
    return switch (type) {
      _TopicComposeType.regular => _isChinese ? '普通帖子' : 'Regular topic',
      _TopicComposeType.poll => _isChinese ? '投票帖子' : 'Poll topic',
      _TopicComposeType.postVoting => context.l10n.createTopic_postVoting,
    };
  }

  IconData _topicTypeIcon(_TopicComposeType type) {
    return switch (type) {
      _TopicComposeType.regular => Icons.article_outlined,
      _TopicComposeType.poll => Icons.poll_outlined,
      _TopicComposeType.postVoting => Icons.thumbs_up_down_outlined,
    };
  }

  Future<void> _editPrimaryPoll() async {
    final spec = await showPollBuilderDialog(
      context,
      existingPollCount: 0,
      initial: _pollSpec,
    );
    if (spec == null || !mounted) return;
    setState(() {
      _topicType = _TopicComposeType.poll;
      _pollSpec = spec;
    });
    _onDraftContentChanged();
  }

  Future<void> _selectTopicType(
    _TopicComposeType type, {
    required bool sitePostVoting,
  }) async {
    final postVotingLocked =
        _selectedCategory?.onlyPostVotingInThisCategory ?? false;
    if (postVotingLocked && type != _TopicComposeType.postVoting) {
      ToastService.showInfo(
        _isChinese
            ? '当前分类只允许创建问答帖子'
            : 'This category only allows Q&A topics.',
      );
      return;
    }

    if (type == _TopicComposeType.poll) {
      if (!_canCreatePoll) {
        ToastService.showInfo(
          _isChinese
              ? '当前账号没有创建投票的权限'
              : 'Your account cannot create polls on this site.',
        );
        return;
      }
      await _editPrimaryPoll();
      return;
    }

    if (type == _TopicComposeType.postVoting && !sitePostVoting) return;

    if (!mounted) return;
    setState(() => _topicType = type);
    _onDraftContentChanged();
  }

  Widget _buildTopicTypePicker({required bool sitePostVoting}) {
    final theme = Theme.of(context);
    final locked = _selectedCategory?.onlyPostVotingInThisCategory ?? false;
    final current = locked ? _TopicComposeType.postVoting : _topicType;
    return PopupMenuButton<_TopicComposeType>(
      tooltip: _isChinese ? '帖子类型' : 'Topic type',
      onSelected: (type) {
        unawaited(_selectTopicType(type, sitePostVoting: sitePostVoting));
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _TopicComposeType.regular,
          enabled: !locked,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.article_outlined, size: 20),
            title: Text(_topicTypeLabel(_TopicComposeType.regular)),
            trailing: current == _TopicComposeType.regular
                ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
                : null,
          ),
        ),
        if (_canCreatePoll)
          PopupMenuItem(
            value: _TopicComposeType.poll,
            enabled: !locked,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.poll_outlined, size: 20),
              title: Text(_topicTypeLabel(_TopicComposeType.poll)),
              trailing: current == _TopicComposeType.poll
                  ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
                  : null,
            ),
          ),
        if (sitePostVoting)
          PopupMenuItem(
            value: _TopicComposeType.postVoting,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.thumbs_up_down_outlined, size: 20),
              title: Text(_topicTypeLabel(_TopicComposeType.postVoting)),
              trailing: current == _TopicComposeType.postVoting
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (locked) ...[
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Icon(
                          Icons.check_rounded,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    )
                  : null,
            ),
          ),
      ],
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: current == _TopicComposeType.regular
                ? theme.colorScheme.outlineVariant
                : theme.colorScheme.primary.withValues(alpha: 0.55),
          ),
          color: current == _TopicComposeType.regular
              ? Colors.transparent
              : theme.colorScheme.primaryContainer.withValues(alpha: 0.22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _topicTypeIcon(current),
              size: 15,
              color: current == _TopicComposeType.regular
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.primary,
            ),
            const SizedBox(width: 5),
            Text(
              _topicTypeLabel(current),
              style: theme.textTheme.labelMedium?.copyWith(
                color: current == _TopicComposeType.regular
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  String _pollTypeDescription(PollSpec spec) {
    return switch (spec.type) {
      kPollTypeRegular => _isChinese
          ? '${spec.options.length} 个选项 · 单选'
          : '${spec.options.length} options · single choice',
      kPollTypeMultiple => _isChinese
          ? '${spec.options.length} 个选项 · 可选 ${spec.min ?? 1}–${spec.max ?? spec.options.length} 项'
          : '${spec.options.length} options · choose ${spec.min ?? 1}–${spec.max ?? spec.options.length}',
      kPollTypeNumber => _isChinese
          ? '评分 ${spec.min ?? 1}–${spec.max ?? 10} · 步长 ${spec.step ?? 1}'
          : 'Rating ${spec.min ?? 1}–${spec.max ?? 10} · step ${spec.step ?? 1}',
      _ => spec.type,
    };
  }

  Widget _buildPrimaryPollCard(ThemeData theme) {
    final spec = _pollSpec;
    if (!_isPollTopic || spec == null) return const SizedBox.shrink();
    final title = spec.title.trim().isEmpty
        ? (_isChinese ? '主投票' : 'Primary poll')
        : spec.title.trim();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => unawaited(_editPrimaryPoll()),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.poll_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _pollTypeDescription(spec),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: _isChinese ? '编辑投票' : 'Edit poll',
                      onPressed: () => unawaited(_editPrimaryPoll()),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                  ],
                ),
                if (spec.type != kPollTypeNumber && spec.options.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final option in spec.options.take(4))
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Row(
                        children: [
                          Icon(
                            spec.type == kPollTypeMultiple
                                ? Icons.check_box_outline_blank_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              option,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (spec.options.length > 4)
                    Padding(
                      padding: const EdgeInsets.only(top: 5, left: 23),
                      child: Text(
                        _isChinese
                            ? '还有 ${spec.options.length - 4} 个选项…'
                            : '${spec.options.length - 4} more options…',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    // 富文本模式:先强制序列化镜像
    _richKey.currentState?.flushToController();
    if (!_formKey.currentState!.validate()) {
      // 预览模式下验证错误不可见，切回编辑模式并提示
      if (_showPreview) {
        _togglePreview();
        ToastService.showInfo(S.current.common_checkInput);
      }
      // 标题在滚动流里可能已滚出屏,拉回顶部让校验错误可见
      _richKey.currentState?.scrollToTop();
      _editorKey.currentState?.scrollToTop();
      return;
    }

    if (_isPollTopic && _pollSpec == null) {
      if (_showPreview) _togglePreview();
      ToastService.showInfo(
        _isChinese ? '请先配置投票' : 'Configure the poll before publishing.',
      );
      return;
    }

    // poll 类型的主投票属于首帖内容，因此允许说明正文为空；长度校验按
    // 最终序列化 raw 计算，而不是只看说明编辑器。
    final minContentLength = ref.read(minFirstPostLengthProvider).value ?? 20;
    final serializedContent = _serializedContent();
    final contentText = serializedContent.trim();
    if (contentText.isEmpty) {
      if (_showPreview) _togglePreview();
      ToastService.showInfo(S.current.createTopic_enterContent);
      return;
    }
    if (contentText.length < minContentLength) {
      if (_showPreview) _togglePreview();
      ToastService.showInfo(
        S.current.createTopic_minContentLength(minContentLength),
      );
      return;
    }

    if (_selectedCategory == null) {
      if (_showPreview) _togglePreview();
      ToastService.showInfo(S.current.createTopic_selectCategory);
      return;
    }

    if (_selectedCategory!.minimumRequiredTags > 0 &&
        _selectedTags.length < _selectedCategory!.minimumRequiredTags) {
      if (_showPreview) _togglePreview();
      ToastService.showInfo(
        S.current.createTopic_minTags(_selectedCategory!.minimumRequiredTags),
      );
      return;
    }

    if (_templateContent != null &&
        _contentController.text.trim() == _templateContent!.trim()) {
      final confirm = await showAppDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.common_hint),
          content: Text(context.l10n.createTopic_templateNotModified),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.createTopic_continueEditing),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.createTopic_confirmPublish),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isSubmitting = true);

    try {
      final service = ref.read(discourseServiceProvider);
      final topicId = await service.createTopic(
        title: _titleController.text.trim(),
        raw: serializedContent,
        categoryId: _selectedCategory!.id,
        tags: _selectedTags.isNotEmpty ? _selectedTags : null,
        featuredLink: _featuredLink,
        createAsPostVoting: _createAsPostVoting,
      );

      // 发送成功后删除草稿
      await _draftController.deleteDraft();
      _submitted = true;

      if (!mounted) return;
      Navigator.of(context).pop(topicId);
    } on PostEnqueuedException {
      // 审核场景：删除草稿，提示用户（带「查看」入口），关闭编辑器
      await _draftController.deleteDraft();
      _submitted = true;
      if (!mounted) return;
      ToastService.show(
        S.current.createTopic_pendingReview,
        type: ToastType.info,
        actionLabel: S.current.review_viewAction,
        onAction: () {
          navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => const PendingPostsPage()),
          );
        },
      );
      Navigator.of(context).pop();
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// 滚动头部:顶部透明 AppBar 避让 + 一级帖子类型 + 标题 + 主投票。
  /// poll 类型的投票配置是 composer 元数据，不进入正文编辑器；正文只写
  /// 说明文字。分类/标签/字数仍在底部 ComposerMetaBar 常驻。
  Widget _buildComposerHeader(
    ThemeData theme,
    int minTitleLength, {
    required bool sitePostVoting,
  }) {
    // extendBodyBehindAppBar 后滚动内容从屏顶开始,首屏让出渐变模糊层
    final topInset = ProgressiveTopBlur.heightFor(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topInset + 10, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopicTypePicker(sitePostVoting: sitePostVoting),
          const SizedBox(height: 12),
          TextFormField(
            controller: _titleController,
            decoration: InputDecoration(
              hintText: context.l10n.createTopic_titleHint,
              hintStyle: TextStyle(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                fontWeight: FontWeight.normal,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
            maxLines: null,
            maxLength: _featuredLinkEnabled ? null : 200,
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => null,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return context.l10n.createTopic_enterTitle;
              }
              if (value.trim().length < minTitleLength) {
                return context.l10n.createTopic_minTitleLength(minTitleLength);
              }
              return null;
            },
            onTap: () {
              _editorKey.currentState?.closeEmojiPanel();
              _richKey.currentState?.closeEmojiPanel();
            },
          ),
          _buildPrimaryPollCard(theme),
          if (_isPollTopic) const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 底部属性条:分类/标签/字数。问答不再作为一个独立 toggle 混在
  /// 元数据条里，它与普通/投票一起由顶部“帖子类型”统一管理。
  Widget _buildMetaBar(
    List<Category> categories,
    bool canTagTopics,
    AsyncValue<List<String>> tagsAsync,
  ) {
    return ComposerMetaBar(
      category: _selectedCategory,
      categories: categories,
      onCategorySelected: _onCategorySelected,
      showTags: canTagTopics,
      selectedTags: _selectedTags,
      allTags: tagsAsync.value ?? const [],
      onTagsChanged: _onTagsChanged,
      charCount: _contentLength,
    );
  }

  /// 构建草稿保存状态指示器
  /// 草稿保存状态指示器(瞬态):保存中转圈、失败红色警示;
  /// 已保存/空闲不显示 —— 成功无需常驻宣告,失败才需要被看见。
  Widget _buildDraftStatusIndicator(DraftSaveStatus status, ThemeData theme) {
    final Widget child;
    switch (status) {
      case DraftSaveStatus.idle:
      case DraftSaveStatus.pending:
      case DraftSaveStatus.saved:
        return const SizedBox.shrink();
      case DraftSaveStatus.saving:
        child = SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: theme.colorScheme.outline,
          ),
        );
      case DraftSaveStatus.error:
        child = Icon(
          Symbols.cloud_off_rounded,
          size: 18,
          color: theme.colorScheme.error,
        );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 4),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final tagsAsync = ref.watch(tagsProvider);
    final canTagTopics = ref.watch(canTagTopicsProvider).value ?? false;
    final theme = Theme.of(context);

    // 获取站点配置的最小长度
    final minTitleLength = ref.watch(minTopicTitleLengthProvider).value ?? 15;

    final page = PopScope(
      canPop: !_showEmojiPanel,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        _editorKey.currentState?.closeEmojiPanel();
        _richKey.currentState?.closeEmojiPanel();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        // 顶栏渐变模糊:AppBar 纯透明只承载功能件,模糊/遮罩由 body
        // Stack 顶部的 ProgressiveTopBlur 提供(从上到下消散到全透明,
        // 无均匀毛玻璃的硬下边);分类/标签/字数在底部 ComposerMetaBar
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text(context.l10n.createTopic_title),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          // 透明背景下 Material 推导不出状态栏图标亮暗(会给成浅色
          // 图标,浅色主题下隐形),按主题显式指定
          systemOverlayStyle: theme.brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          actions: [
            // 草稿保存状态(瞬态:保存中转圈/失败警示;已保存不常驻
            // —— 成功无需一直宣告,失败才需要喊)
            ValueListenableBuilder<DraftSaveStatus>(
              valueListenable: _draftController.statusNotifier,
              builder: (context, status, _) {
                return _buildDraftStatusIndicator(status, theme);
              },
            ),
            // 功能按钮全部图标直出不折叠(⋯ 菜单藏舍弃太难用):
            // 舍弃 🗑 / AI 审核 ✨,tooltip 兜底语义
            IconButton(
              onPressed: _isSubmitting ? null : _discardDraft,
              tooltip: context.l10n.common_discard,
              icon: const Icon(Symbols.delete_rounded, size: 22),
            ),
            // AiPostReviewButton builder 形态:图标按钮即审核结果
            // popover 的锚
            AiPostReviewButton(
              titleBuilder: () => _titleController.text,
              contentBuilder: _serializedContent,
              target: AiPostReviewTarget.topic,
              enabled: !_isSubmitting,
              categoryNameBuilder: () => _selectedCategory?.name,
              categoryDescriptionBuilder: () => _selectedCategory?.description,
              tagsBuilder: () => _selectedTags,
              builder: (anchorContext, isReviewing, trigger) {
                // 功能关闭(trigger null 且非审核中)时不占位
                if (trigger == null && !isReviewing) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  onPressed: trigger,
                  tooltip: context.l10n.aiPostReview_button,
                  icon: isReviewing
                      ? LoadingSpinner(
                          size: 18,
                          color: theme.colorScheme.primary,
                        )
                      : const Icon(Symbols.auto_awesome_rounded, size: 22),
                );
              },
            ),
            const SizedBox(width: 2),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton(
                onPressed: (_isSubmitting || _isResolvingFeaturedLink)
                    ? null
                    : _submit,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(context.l10n.common_publish),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            categoriesAsync.when(
              data: (categories) {
                final sitePostVoting = categories.any(
                  (c) => c.hasPostVotingFields,
                );
                final editorHint = _isPollTopic
                    ? (_isChinese
                          ? '补充投票说明（可选）'
                          : 'Add context for the poll (optional)')
                    : context.l10n.createTopic_contentHint;
                return Stack(
                  children: [
                    Column(
                      children: [
                        Expanded(
                          child: PageView(
                            controller: _pageController,
                            allowImplicitScrolling: true,
                            onPageChanged: (index) {
                              setState(() {
                                _showPreview = index == 1;
                              });
                              if (_showPreview) {
                                FocusScope.of(context).unfocus();
                                _editorKey.currentState?.closeEmojiPanel();
                                _richKey.currentState?.closeEmojiPanel();
                              }
                            },
                            children: [
                              // Page 0: 编辑模式 —— 一级类型/标题/主投票/正文
                              // 处在同一滚动流；分类/标签/字数常驻底部。
                              // 双模切换 = 无并存直切 + 新编辑器淡入。
                              Form(
                                key: _formKey,
                                child: ComposerSwitchFade(
                                  child:
                                      (ref
                                              .watch(preferencesProvider)
                                              .useRichComposer &&
                                          !_richFallback)
                                      // 草稿加载完成前不挂富 composer:初始导入
                                      // 一次性,提前挂会以空文档镜像覆盖草稿。
                                      ? (_isLoadingDraft
                                            ? const SizedBox.shrink()
                                            : RichComposerEditor(
                                                key: _richKey,
                                                header: _buildComposerHeader(
                                                  theme,
                                                  minTitleLength,
                                                  sitePostVoting:
                                                      sitePostVoting,
                                                ),
                                                metaBar: _buildMetaBar(
                                                  categories,
                                                  canTagTopics,
                                                  tagsAsync,
                                                ),
                                                controller: _contentController,
                                                focusNode: _contentFocusNode,
                                                hintText: editorHint,
                                                emojiPanelHeight: 350,
                                                onEmojiPanelChanged: (show) {
                                                  setState(
                                                    () =>
                                                        _showEmojiPanel = show,
                                                  );
                                                },
                                                mentionDataSource: (term) => ref
                                                    .read(
                                                      discourseServiceProvider,
                                                    )
                                                    .searchUsers(
                                                      term: term,
                                                      categoryId:
                                                          _selectedCategory?.id,
                                                      includeGroups: true,
                                                    ),
                                                onFallbackToPlain: () {
                                                  if (mounted) {
                                                    setState(
                                                      () =>
                                                          _richFallback = true,
                                                    );
                                                  }
                                                },
                                                // 主动切源码(可经工具栏
                                                // 「富文本模式」切回)
                                                onSwitchToSource: () {
                                                  if (mounted) {
                                                    setState(
                                                      () =>
                                                          _richFallback = true,
                                                    );
                                                  }
                                                },
                                              ))
                                      : MarkdownEditor(
                                          key: _editorKey,
                                          header: _buildComposerHeader(
                                            theme,
                                            minTitleLength,
                                            sitePostVoting: sitePostVoting,
                                          ),
                                          metaBar: _buildMetaBar(
                                            categories,
                                            canTagTopics,
                                            tagsAsync,
                                          ),
                                          controller: _contentController,
                                          focusNode: _contentFocusNode,
                                          hintText: editorHint,
                                          expands: true,
                                          emojiPanelHeight: 350,
                                          onTogglePreview: _togglePreview,
                                          isPreview: _showPreview,
                                          onEmojiPanelChanged: (show) {
                                            setState(
                                              () => _showEmojiPanel = show,
                                            );
                                          },
                                          // 源码 → 富文本(开关开着即可,
                                          // 门禁降级后也允许重试)
                                          onSwitchToRich:
                                              ref
                                                  .watch(preferencesProvider)
                                                  .useRichComposer
                                              ? () {
                                                  if (mounted) {
                                                    setState(
                                                      () =>
                                                          _richFallback = false,
                                                    );
                                                  }
                                                }
                                              : null,
                                          mentionDataSource: (term) => ref
                                              .read(discourseServiceProvider)
                                              .searchUsers(
                                                term: term,
                                                categoryId:
                                                    _selectedCategory?.id,
                                                includeGroups: true,
                                              ),
                                        ),
                                ),
                              ),

                              // Page 1: 预览模式。poll 类型使用真正提交的 raw，
                              // 因而预览里主投票与发布结果一致。
                              SingleChildScrollView(
                                padding: EdgeInsets.fromLTRB(
                                  24,
                                  // 透明 AppBar+消散尾巴避让
                                  ProgressiveTopBlur.heightFor(context) + 16,
                                  24,
                                  MediaQuery.paddingOf(context).bottom + 80,
                                ),
                                child: Builder(
                                  builder: (context) {
                                    final previewRaw = _serializedContent();
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _titleController.text.isEmpty
                                              ? context.l10n.createTopic_noTitle
                                              : _titleController.text,
                                          style: theme.textTheme.headlineSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: -0.5,
                                              ),
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Icon(
                                              _topicTypeIcon(_topicType),
                                              size: 15,
                                              color: theme.colorScheme.primary,
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              _topicTypeLabel(_topicType),
                                              style: theme.textTheme.labelMedium
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .primary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            if (_selectedCategory != null)
                                              CategoryTrigger(
                                                category: _selectedCategory,
                                                categories: categories,
                                                onSelected:
                                                    _onCategorySelected,
                                              ),
                                            PreviewTagsList(
                                              tags: _selectedTags,
                                            ),
                                          ],
                                        ),
                                        const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 24,
                                          ),
                                          child: Divider(height: 1),
                                        ),
                                        if (previewRaw.trim().isEmpty)
                                          Text(
                                            context.l10n.createTopic_noContent,
                                            style: TextStyle(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          )
                                        else
                                          MarkdownBody(
                                            data: previewRaw,
                                            onImageScaleChanged:
                                                (image, scale) {
                                                  // 主投票不在正文 controller，
                                                  // 图片缩放只修改说明正文。
                                                  final next =
                                                      applyImageScaleToRaw(
                                                        _contentController.text,
                                                        image,
                                                        scale,
                                                      );
                                                  if (next != null) {
                                                    _contentController.text =
                                                        next;
                                                    setState(() {});
                                                  }
                                                },
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // 预览模式下的退出预览按钮
                    if (_showPreview)
                      Positioned(
                        right: 16,
                        bottom: MediaQuery.paddingOf(context).bottom + 16,
                        child: FloatingActionButton.small(
                          onPressed: _togglePreview,
                          tooltip: context.l10n.common_exitPreview,
                          child: const Icon(Symbols.edit_rounded),
                        ),
                      ),
                    // 草稿加载遮罩
                    if (_isLoadingDraft)
                      Positioned.fill(
                        child: Container(
                          color: theme.colorScheme.surface.withValues(
                            alpha: 0.7,
                          ),
                          child: const Center(child: LoadingSpinner()),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const Center(child: LoadingSpinner()),
              error: (err, stack) => ErrorView(
                error: err,
                stackTrace: stack,
                onRetry: () => ref.invalidate(categoriesProvider),
              ),
            ),
            // 顶栏渐变模糊:内容从透明 AppBar 下滚过,模糊+遮罩自上
            // 而下消散到全透明(尾巴伸出 AppBar 下缘 36pt)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ProgressiveTopBlur(
                height: ProgressiveTopBlur.heightFor(context),
              ),
            ),
          ],
        ),
      ),
    );

    // Cmd/Ctrl+Enter 发布(对齐 Discourse composer):包整页,焦点在
    // 标题/标签输入框时同样生效;守卫与发布按钮一致。
    return CallbackShortcuts(
      bindings: {
        for (final activator in composerSubmitActivators())
          activator: () {
            if (!_isSubmitting && !_isResolvingFeaturedLink) _submit();
          },
      },
      child: page,
    );
  }
}
