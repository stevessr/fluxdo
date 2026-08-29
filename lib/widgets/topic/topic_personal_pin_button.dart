import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../providers/discourse_providers.dart';
import '../../services/toast_service.dart';
import '../common/app_bottom_sheet.dart';

/// Discourse 对当前用户暴露的置顶状态。
///
/// 这里刻意不实现 staff 的全局 `/status` 置顶：普通用户能做的是对一个
/// 已由站点/分类置顶的话题设置 `TopicUser.cleared_pinned_at`，也就是：
/// - clear-pin: 仅“对我取消置顶”；
/// - re-pin: 清除个人覆盖，恢复站点/分类原本的置顶。
@immutable
class PersonalTopicPinState {
  const PersonalTopicPinState({required this.pinned, required this.unpinned});

  final bool pinned;
  final bool unpinned;

  /// 只有服务端本身存在可恢复的 pin 时，这两个字段才会有一个为 true。
  bool get canModify => pinned || unpinned;
}

class TopicPersonalPinButton extends ConsumerStatefulWidget {
  const TopicPersonalPinButton({
    super.key,
    required this.topicId,
    required this.categoryId,
  });

  final int topicId;
  final int categoryId;

  @override
  ConsumerState<TopicPersonalPinButton> createState() =>
      _TopicPersonalPinButtonState();
}

class _TopicPersonalPinButtonState
    extends ConsumerState<TopicPersonalPinButton> {
  bool _loading = false;
  bool _mutating = false;
  PersonalTopicPinState? _lastState;

  Future<PersonalTopicPinState> _fetchState() async {
    final response = await ref
        .read(discourseServiceProvider)
        .dio
        .get<Map<String, dynamic>>('/t/${widget.topicId}.json');
    final data = response.data ?? const <String, dynamic>{};
    return PersonalTopicPinState(
      pinned: data['pinned'] == true,
      unpinned: data['unpinned'] == true,
    );
  }

  Future<void> _open() async {
    if (_loading || _mutating) return;
    setState(() => _loading = true);

    PersonalTopicPinState state;
    try {
      // 不在话题详情首屏额外请求一次完整 JSON；只有用户主动点开个人置顶
      // 设置时才拉当前用户视角的 pinned/unpinned，避免给所有话题加冷启动税。
      state = await _fetchState();
    } catch (error) {
      if (mounted) {
        ToastService.showError(context.l10n.common_operationFailed('$error'));
      }
      return;
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    if (!mounted) return;
    _lastState = state;

    if (!state.canModify) {
      ToastService.showInfo('此话题当前未被站点或分类置顶');
      return;
    }

    await showAppBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => AppSheetScaffold(
        title: '个人置顶',
        showCloseButton: false,
        contentPadding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Symbols.push_pin_rounded,
                fill: state.pinned ? 1 : 0,
                color: Theme.of(sheetContext).colorScheme.primary,
              ),
              title: Text(state.pinned ? '对我取消置顶' : '恢复置顶'),
              subtitle: Text(
                state.pinned
                    ? '仅影响当前账号，不改变站点或分类的置顶状态'
                    : '移除当前账号的取消置顶覆盖，重新跟随站点或分类置顶',
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_setPinned(!state.pinned));
              },
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Future<void> _setPinned(bool pinned) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try {
      final path = pinned
          ? '/t/${widget.topicId}/re-pin'
          : '/t/${widget.topicId}/clear-pin';
      await ref.read(discourseServiceProvider).dio.put<void>(path);
      if (!mounted) return;

      setState(() {
        _lastState = PersonalTopicPinState(
          pinned: pinned,
          unpinned: !pinned,
        );
      });

      // 置顶会影响 latest 与分类列表的排序/图标。让两类常用列表在返回时
      // 重新取当前用户视角的数据；认证/session 本身完全不动。
      ref.invalidate(topicListProvider(null));
      ref.invalidate(topicListProvider(widget.categoryId));

      ToastService.showSuccess(pinned ? '已恢复置顶' : '已对你取消置顶');
    } catch (error) {
      if (mounted) {
        ToastService.showError(context.l10n.common_operationFailed('$error'));
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).value;
    if (currentUser == null) return const SizedBox.shrink();

    final state = _lastState;
    final active = state?.pinned == true;
    return Tooltip(
      message: '个人置顶',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _open,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: active
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
              ),
            ),
            child: _loading || _mutating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Symbols.push_pin_rounded,
                    size: 16,
                    fill: active ? 1 : 0,
                    color: Theme.of(context).colorScheme.primary,
                  ),
          ),
        ),
      ),
    );
  }
}
