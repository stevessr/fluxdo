// ignore_for_file: invalid_use_of_protected_member

part of '../post_footer_section.dart';

extension _PostFooterManageActions on _PostFooterSectionState {
  Future<void> _toggleSolution() async {
    if (_isTogglingAnswer) return;

    HapticFeedback.lightImpact();
    setState(() => _isTogglingAnswer = true);

    try {
      if (_isAcceptedAnswer) {
        await _service.unacceptAnswer(widget.post.id);
        if (mounted) {
          setState(() => _isAcceptedAnswer = false);
          widget.onAcceptedAnswerChanged?.call(false);
          widget.onSolutionChanged?.call(widget.post.id, false);
          ToastService.showSuccess(S.current.post_solutionUnaccepted);
        }
      } else {
        await _service.acceptAnswer(widget.post.id);
        if (mounted) {
          setState(() => _isAcceptedAnswer = true);
          widget.onAcceptedAnswerChanged?.call(true);
          widget.onSolutionChanged?.call(widget.post.id, true);
          ToastService.showSuccess(S.current.post_solutionAccepted);
        }
      }
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    } finally {
      if (mounted) {
        setState(() => _isTogglingAnswer = false);
      }
    }
  }

  Future<void> _toggleWiki() async {
    try {
      await _service.setPostWiki(widget.post.id, wiki: !widget.post.wiki);
      if (!mounted) return;
      ToastService.showSuccess(widget.post.wiki ? '已取消 Wiki' : '已设为 Wiki');
      widget.onRefreshPost?.call(widget.post.id);
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    }
  }

  Future<void> _togglePostLocked() async {
    try {
      final locked = await _service.setPostLocked(
        widget.post.id,
        locked: !widget.post.locked,
      );
      if (!mounted) return;
      final zh =
          Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';
      ToastService.showSuccess(
        locked
            ? (zh ? '帖子已锁定' : 'Post locked')
            : (zh ? '帖子已解锁' : 'Post unlocked'),
      );
      widget.onRefreshPost?.call(widget.post.id);
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    }
  }

  Future<void> _editPostNotice() async {
    final zh =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';
    final controller = TextEditingController(
      text: widget.post.notice?.raw ?? '',
    );
    final value = await showAppDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(zh ? 'Staff 提示' : 'Staff notice'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(
            hintText: zh
                ? '输入提示内容；留空并保存可移除现有提示'
                : 'Enter notice text; save empty text to remove it',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(zh ? '保存' : 'Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;

    try {
      await _service.setPostNotice(
        widget.post.id,
        notice: value.trim().isEmpty ? null : value.trim(),
      );
      if (!mounted) return;
      ToastService.showSuccess(
        value.trim().isEmpty
            ? (zh ? '已移除 Staff 提示' : 'Staff notice removed')
            : (zh ? 'Staff 提示已更新' : 'Staff notice updated'),
      );
      widget.onRefreshPost?.call(widget.post.id);
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    }
  }

  Future<void> _rebakePost() async {
    try {
      await _service.rebakePost(widget.post.id);
      if (!mounted) return;
      final zh =
          Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';
      ToastService.showSuccess(zh ? '帖子已重新渲染' : 'Post rebaked');
      widget.onRefreshPost?.call(widget.post.id);
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    }
  }

  Future<void> _togglePostType() async {
    final targetType = widget.post.postType == 4 ? 1 : 4;
    try {
      await _service.setPostType(widget.post.id, targetType);
      if (!mounted) return;
      final zh =
          Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';
      ToastService.showSuccess(
        targetType == 4
            ? (zh ? '已转换为 Whisper' : 'Converted to whisper')
            : (zh ? '已转换为普通帖子' : 'Converted to regular post'),
      );
      widget.onRefreshPost?.call(widget.post.id);
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    }
  }

  Future<void> _mergePostWithOthers() async {
    final zh =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';
    try {
      final detail = await _service.getTopicDetail(
        widget.topicId,
        usernameFilters: widget.post.username,
      );
      final ids = <int>{...detail.postStream.stream, widget.post.id};
      final byId = <int, Post>{
        for (final post in detail.postStream.posts) post.id: post,
        widget.post.id: widget.post,
      };

      final missing = ids.where((id) => !byId.containsKey(id)).toList();
      const chunkSize = 40;
      for (var offset = 0; offset < missing.length; offset += chunkSize) {
        final end = offset + chunkSize < missing.length
            ? offset + chunkSize
            : missing.length;
        final stream = await _service.getPosts(
          widget.topicId,
          missing.sublist(offset, end),
        );
        for (final post in stream.posts) {
          byId[post.id] = post;
        }
      }

      final candidates = byId.values
          .where(
            (post) =>
                post.username == widget.post.username &&
                post.postNumber > 1 &&
                !post.isDeleted &&
                (post.id == widget.post.id || post.canDelete),
          )
          .toList()
        ..sort((a, b) => a.postNumber.compareTo(b.postNumber));

      if (candidates.length < 2) {
        ToastService.showError(
          zh
              ? '没有其它可与该帖子合并的同作者回复'
              : 'No other mergeable replies from the same author',
        );
        return;
      }
      if (!mounted) return;

      final selected = <int>{widget.post.id};
      final result = await showAppDialog<List<int>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(zh ? '合并帖子' : 'Merge posts'),
            content: SizedBox(
              width: 560,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 480),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final post = candidates[index];
                    final fixed = post.id == widget.post.id;
                    return CheckboxListTile(
                      value: selected.contains(post.id),
                      onChanged: fixed
                          ? null
                          : (checked) {
                              setDialogState(() {
                                if (checked == true) {
                                  selected.add(post.id);
                                } else {
                                  selected.remove(post.id);
                                }
                              });
                            },
                      title: Text(
                        '#${post.postNumber} · @${post.username}',
                      ),
                      subtitle: Text(
                        post.cooked
                            .replaceAll(RegExp(r'<[^>]+>'), ' ')
                            .replaceAll(RegExp(r'\s+'), ' ')
                            .trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(context.l10n.common_cancel),
              ),
              FilledButton(
                onPressed: selected.length < 2
                    ? null
                    : () => Navigator.pop(
                        dialogContext,
                        selected.toList(growable: false),
                      ),
                child: Text(
                  zh
                      ? '合并 ${selected.length} 条'
                      : 'Merge ${selected.length}',
                ),
              ),
            ],
          ),
        ),
      );
      if (result == null || result.length < 2 || !mounted) return;

      final confirmed =
          await showAppDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(zh ? '确认合并' : 'Confirm merge'),
              content: Text(
                zh
                    ? '被选中的内容会合并到最后一条回复，其余帖子会被删除。该操作将修改帖子历史。'
                    : 'Content will be merged into the last selected reply and the other posts will be deleted.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(context.l10n.common_cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(zh ? '合并' : 'Merge'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;

      final mergedTarget = candidates
          .where((post) => result.contains(post.id))
          .reduce((a, b) => a.postNumber > b.postNumber ? a : b);
      await _service.mergePosts(result);
      if (!mounted) return;
      ToastService.showSuccess(zh ? '帖子已合并' : 'Posts merged');
      widget.onRefreshPost?.call(mergedTarget.id);
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    }
  }

  Future<void> _showPermanentDeleteCheck() async {
    try {
      final check = await _service.getPostPermanentDeleteCheck(widget.post.id);
      if (!mounted) return;
      final zh =
          Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';
      await showAppDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(zh ? '永久删除检查' : 'Permanent delete check'),
          content: Text(
            check.canPermanentlyDelete
                ? (zh
                      ? '该帖子当前满足永久删除条件。'
                      : 'This post can currently be permanently deleted.')
                : (check.reason?.trim().isNotEmpty == true
                      ? check.reason!
                      : (zh
                            ? '该帖子当前不满足永久删除条件。'
                            : 'This post cannot currently be permanently deleted.')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(zh ? '关闭' : 'Close'),
            ),
          ],
        ),
      );
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    }
  }

  Future<void> _deletePost() async {
    if (_isDeleting) return;
    HapticFeedback.lightImpact();
    setState(() => _isDeleting = true);

    try {
      await _service.deletePost(widget.post.id);
      if (mounted) {
        ToastService.showSuccess(S.current.common_deleted);
        widget.onRefreshPost?.call(widget.post.id);
      }
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  Future<void> _recoverPost() async {
    if (_isDeleting) return;
    HapticFeedback.lightImpact();
    setState(() => _isDeleting = true);

    try {
      await _service.recoverPost(widget.post.id);
      if (mounted) {
        ToastService.showSuccess(S.current.common_restored);
        widget.onRefreshPost?.call(widget.post.id);
      }
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }
}
