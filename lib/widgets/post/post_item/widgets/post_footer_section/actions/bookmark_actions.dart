// ignore_for_file: invalid_use_of_protected_member, unused_element

part of '../post_footer_section.dart';

extension _PostFooterBookmarkActions on _PostFooterSectionState {
  /// 添加书签并弹出编辑 BottomSheet
  Future<void> _addBookmark() async {
    if (_isBookmarking) return;

    HapticFeedback.lightImpact();
    setState(() => _isBookmarking = true);

    try {
      final bookmarkId = await _service.bookmarkPost(widget.post.id);
      if (!mounted) return;

      setState(() {
        _isBookmarked = true;
        _bookmarkId = bookmarkId;
        _bookmarkName = null;
        _bookmarkReminderAt = null;
      });
      ToastService.showSuccess(S.current.common_bookmarkAdded);

      // 写穿本地书签缓存：帖子级书签新增后，书签列表页（数据源是
      // BookmarksRepository）能立即感知，避免本地与云端不一致。
      unawaited(_syncPostBookmarkToCache(
        bookmarkId: bookmarkId,
        name: null,
        reminderAt: null,
      ));

      // 触发 Notion 自动同步:post 级 -> 只同步这一条,独立 page
      unawaited(
        NotionBookmarkAutoSync.tryTriggerPost(
          ref: ref,
          topicId: widget.topicId,
          postId: widget.post.id,
        ),
      );

      // 弹出编辑 BottomSheet
      _showBookmarkSheet(bookmarkId);
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    } finally {
      if (mounted) setState(() => _isBookmarking = false);
    }
  }

  /// 删除书签
  Future<void> _removeBookmark() async {
    if (_isBookmarking) return;

    HapticFeedback.lightImpact();
    setState(() => _isBookmarking = true);

    try {
      final bookmarkId = _bookmarkId ?? widget.post.bookmarkId;
      if (bookmarkId != null) {
        await _service.deleteBookmark(bookmarkId);
        if (mounted) {
          setState(() {
            _isBookmarked = false;
            _bookmarkId = null;
            _bookmarkName = null;
            _bookmarkReminderAt = null;
          });
          ToastService.showSuccess(S.current.common_bookmarkRemoved);
          // 写穿本地缓存：删除后列表页立即不再显示该条。
          unawaited(_removePostBookmarkFromCache(bookmarkId));
        }
      }
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    } finally {
      if (mounted) setState(() => _isBookmarking = false);
    }
  }

  /// 把帖级书签状态写穿到 [BookmarksRepository]（本地缓存）。
  ///
  /// 详情页/帖子 footer 增删改书签后，书签列表页数据源是 BookmarksRepository，
  /// 若不写穿缓存，列表页只能等下一次对账才感知变化，造成本地与云端不一致。
  Future<void> _syncPostBookmarkToCache({
    required int bookmarkId,
    String? name,
    DateTime? reminderAt,
  }) async {
    try {
      final repo = ref.read(bookmarksRepositoryProvider);
      final username = await ref.read(currentUsernameProvider.future);
      if (username == null) return;
      final now = DateTime.now().toUtc();
      final topicId = widget.topicId;
      // 本地无该 entry（首次书签）时构造最小 payload upsert，保证列表页立即可见；
      // 已有 entry 时走 applyMetadataChange 更新 name/reminder。
      final existing = await repo.findOne(username, bookmarkId);
      if (existing == null) {
        final payload = <String, dynamic>{
          'id': topicId,
          '_bookmark_id': bookmarkId,
          '_bookmark_updated_at': now.toIso8601String(),
          '_bookmarkable_type': 'Post',
          if (name != null && name.isNotEmpty) '_bookmark_name': name,
          if (reminderAt != null)
            '_bookmark_reminder_at': reminderAt.toUtc().toIso8601String(),
        };
        await repo.upsertOne(
          username,
          BookmarkCacheEntry(
            bookmarkId: bookmarkId,
            topicId: topicId,
            nameNormalized:
                name == null || name.isEmpty ? null : name,
            updatedAt: now,
            cachedAt: now,
            payload: payload,
          ),
        );
      } else {
        await repo.applyMetadataChange(
          username,
          bookmarkId,
          name: name,
          reminderAt: reminderAt,
          bookmarkUpdatedAt: now,
        );
      }
    } catch (_) {
      // 缓存写穿失败不影响 UI 主流程，下次对账会纠正。
    }
  }

  /// 从本地缓存删除帖级书签条目。
  Future<void> _removePostBookmarkFromCache(int bookmarkId) async {
    try {
      final repo = ref.read(bookmarksRepositoryProvider);
      final username = await ref.read(currentUsernameProvider.future);
      if (username == null) return;
      await repo.deleteOne(username, bookmarkId);
    } catch (_) {
      // 缓存删除失败不影响 UI 主流程，下次对账会纠正。
    }
  }

  /// 编辑已有书签
  Future<void> _editBookmark() async {
    final bookmarkId = _bookmarkId ?? widget.post.bookmarkId;
    if (bookmarkId == null) return;
    _showBookmarkSheet(bookmarkId, isEdit: true);
  }

  /// 弹出书签编辑 BottomSheet
  Future<void> _showBookmarkSheet(int bookmarkId, {bool isEdit = false}) async {
    final traceId = createBookmarkEditTraceId();
    writeBookmarkEditTrace(
      phase: 'post_footer_bookmark_sheet_request',
      traceId: traceId,
      source: 'post_footer_bookmark_action',
      message: isEdit ? '帖子 footer 准备打开编辑书签面板' : '帖子 footer 准备打开新建书签编辑面板',
      topicId: widget.topicId,
      postId: widget.post.id,
      bookmarkId: bookmarkId,
      bookmarkName: _bookmarkName ?? widget.post.bookmarkName,
      initialName: isEdit ? (_bookmarkName ?? widget.post.bookmarkName) : null,
      bookmarked: _isBookmarked,
      hasReminder:
          isEdit
              ? ((_bookmarkReminderAt ?? widget.post.bookmarkReminderAt) != null)
              : false,
    );
    final result = await showBookmarkEditSheetWithCachedNames(
      context,
      ref,
      bookmarkId: bookmarkId,
      initialName: isEdit ? (_bookmarkName ?? widget.post.bookmarkName) : null,
      initialReminderAt: isEdit
          ? (_bookmarkReminderAt ?? widget.post.bookmarkReminderAt)
          : null,
      traceId: traceId,
      source: 'post_footer_bookmark_action',
      topicId: widget.topicId,
      postId: widget.post.id,
    );

    if (result == null || !mounted) return;

    if (result.deleted) {
      setState(() {
        _isBookmarked = false;
        _bookmarkId = null;
        _bookmarkName = null;
        _bookmarkReminderAt = null;
      });
    } else {
      setState(() {
        _bookmarkName = result.name;
        _bookmarkReminderAt = result.reminderAt;
      });
    }
  }

}
