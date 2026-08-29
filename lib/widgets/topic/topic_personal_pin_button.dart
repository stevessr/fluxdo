import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../providers/discourse_providers.dart';
import '../../services/toast_service.dart';

/// Discourse 对当前用户暴露的置顶状态。
///
/// Discourse 将“管理员是否仍然设置了置顶”和“当前用户是否显示这个置顶”
/// 分成两组状态：
/// - `pinned_at != null`：话题当前存在站点/分类置顶；
/// - `pinned_globally`：true 为全局置顶，false 为分类置顶；
/// - `pinned` / `unpinned`：经过 TopicUser.cleared_pinned_at 计算后的
///   当前用户视角状态。
///
/// 因此按钮显隐只能看 `pinned_at`，不能拿用户态 `pinned` 代替，否则用户
/// 执行 clear-pin 后按钮会跟着消失，无法再调用 re-pin 恢复。
@immutable
class PersonalTopicPinState {
  const PersonalTopicPinState({
    required this.hasAdminPin,
    required this.pinned,
    required this.unpinned,
    required this.pinnedGlobally,
  });

  final bool hasAdminPin;
  final bool pinned;
  final bool unpinned;
  final bool pinnedGlobally;

  String get scopeLabel => pinnedGlobally ? '全局置顶' : '板块置顶';
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
  bool _loadFailed = false;
  PersonalTopicPinState? _state;

  Future<PersonalTopicPinState> _fetchState() async {
    final response = await ref
        .read(discourseServiceProvider)
        .dio
        .get<Map<String, dynamic>>('/t/${widget.topicId}.json');
    final data = response.data ?? const <String, dynamic>{};

    return PersonalTopicPinState(
      // 与 Discourse TopicViewSerializer / PinnedCheck 保持一致：pinned_at
      // 是管理员置顶是否仍存在的主来源；用户 clear-pin 不会清除此字段。
      hasAdminPin: data['pinned_at'] != null,
      pinned: data['pinned'] == true,
      unpinned: data['unpinned'] == true,
      pinnedGlobally: data['pinned_globally'] == true,
    );
  }

  Future<void> _loadState() async {
    if (_loading || _mutating || _state != null) return;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });

    try {
      final state = await _fetchState();
      if (!mounted) return;
      setState(() => _state = state);
    } catch (_) {
      // 这是为了决定一个辅助按钮是否显示的后台探测。失败时保持隐藏，
      // 不在用户刚进入话题时主动弹错误；后续重建/切换话题可重新尝试。
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setPinned(bool pinned) async {
    if (_mutating) return;
    final current = _state;
    if (current == null || !current.hasAdminPin) return;

    setState(() => _mutating = true);
    try {
      final path = pinned
          ? '/t/${widget.topicId}/re-pin'
          : '/t/${widget.topicId}/clear-pin';
      await ref.read(discourseServiceProvider).dio.put<void>(path);
      if (!mounted) return;

      setState(() {
        _state = PersonalTopicPinState(
          hasAdminPin: current.hasAdminPin,
          pinned: pinned,
          unpinned: !pinned,
          pinnedGlobally: current.pinnedGlobally,
        );
      });

      // 个人置顶状态会影响 latest 与分类列表的排序/图标。让两类常用列表
      // 在返回时重新取当前用户视角的数据；认证/session 本身完全不动。
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
  void didUpdateWidget(covariant TopicPersonalPinButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topicId != widget.topicId) {
      _state = null;
      _loadFailed = false;
      if (!_loading) {
        unawaited(_loadState());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).value;
    if (currentUser == null) return const SizedBox.shrink();

    // TopicDetail 目前没有保留 Discourse 顶层的 pinned_at，因此在登录用户
    // 打开话题时只探测一次。结果出来前保持隐藏，不让“取消置顶”按钮在普通
    // 未置顶话题上短暂闪现。
    if (_state == null && !_loading && !_loadFailed) {
      unawaited(_loadState());
    }

    final state = _state;
    if (state == null || !state.hasAdminPin) {
      return const SizedBox.shrink();
    }

    // Discourse 的 pinned / unpinned 在存在 pinned_at 时互斥。若服务端因兼容
    // 性问题没有返回 unpinned，则仍以 pinned 为当前显示状态的权威来源。
    final isPinned = state.pinned && !state.unpinned;
    final tooltip = isPinned
        ? '${state.scopeLabel} · 当前已置顶，点击取消置顶'
        : '${state.scopeLabel} · 当前未置顶，点击恢复置顶';
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _mutating ? null : () => unawaited(_setPinned(!isPinned)),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isPinned
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isPinned ? theme.colorScheme.primary : Colors.transparent,
              ),
            ),
            child: _mutating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    // 箭头表达“当前状态”而非下一步操作：向上=当前置顶，
                    // 向下=当前已取消置顶。Tooltip 同时明确点击后的动作。
                    isPinned
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
          ),
        ),
      ),
    );
  }
}
