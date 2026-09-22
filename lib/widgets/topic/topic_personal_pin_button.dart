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
  bool _loadScheduled = false;
  PersonalTopicPinState? _state;

  Future<PersonalTopicPinState> _fetchState() async {
    final topicId = widget.topicId;
    final response = await ref
        .read(discourseServiceProvider)
        .dio
        .get<Map<String, dynamic>>('/t/$topicId.json');
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
    final requestedTopicId = widget.topicId;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });

    try {
      final state = await _fetchState();
      if (!mounted || requestedTopicId != widget.topicId) return;
      setState(() => _state = state);
    } catch (_) {
      // 这是为了决定一个辅助按钮是否显示的后台探测。失败时保持隐藏，
      // 不在用户刚进入话题时主动弹错误；后续重建/切换话题可重新尝试。
      if (mounted && requestedTopicId == widget.topicId) {
        setState(() => _loadFailed = true);
      }
    } finally {
      if (mounted && requestedTopicId == widget.topicId) {
        setState(() => _loading = false);
      }
    }
  }

  void _scheduleLoadState() {
    if (_loadScheduled || _loading || _state != null || _loadFailed) return;
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScheduled = false;
      if (!mounted || _loading || _state != null || _loadFailed) return;
      unawaited(_loadState());
    });
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
      // 旧话题的异步请求可能仍在路上；先为新话题重置本地探测状态。
      // 旧请求完成时会因为 requestedTopicId 不匹配而被丢弃。
      _state = null;
      _loading = false;
      _mutating = false;
      _loadFailed = false;
      _loadScheduled = false;
      _scheduleLoadState();
    }
  }

  // 与 Discourse pinned-options 一致：选择“置顶 / 取消置顶”，而不是
  // 用上下箭头暗示阅读位置，或把当前状态误当成下一步操作。
  String _optionTitle(bool pinned, PersonalTopicPinState state) =>
      pinned ? state.scopeLabel : '取消置顶';

  String _optionDescription(bool pinned, PersonalTopicPinState state) {
    if (!pinned) return '仅对你取消置顶，不影响其他用户';
    return state.pinnedGlobally
        ? '在你看到的所有话题列表中保持置顶'
        : '在你看到的所属板块话题列表中保持置顶';
  }

  Widget _optionContent(
    BuildContext context,
    PersonalTopicPinState state, {
    required bool pinned,
    required bool selected,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          color: selected ? colors.primary : colors.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_optionTitle(pinned, state)),
              const SizedBox(height: 2),
              Text(
                _optionDescription(pinned, state),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (selected) ...[
          const SizedBox(width: 12),
          Icon(Icons.check_rounded, size: 18, color: colors.primary),
        ],
      ],
    );
  }

  Future<void> _showMobileOptions(
    PersonalTopicPinState state,
    bool isPinned,
  ) async {
    final requestedTopicId = widget.topicId;
    final choice = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final pinned in [true, false])
              ListTile(
                leading: Icon(
                  pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                ),
                title: Text(_optionTitle(pinned, state)),
                subtitle: Text(_optionDescription(pinned, state)),
                trailing: pinned == isPinned
                    ? Icon(
                        Icons.check_rounded,
                        color: Theme.of(sheetContext).colorScheme.primary,
                      )
                    : null,
                selected: pinned == isPinned,
                onTap: () => Navigator.pop(sheetContext, pinned),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    // 用户可能在面板打开时切换右侧详情话题，不要把旧选择写入新话题。
    if (!mounted ||
        requestedTopicId != widget.topicId ||
        choice == null ||
        choice == isPinned) {
      return;
    }
    await _setPinned(choice);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).value;
    if (currentUser == null) return const SizedBox.shrink();

    // TopicDetail 目前没有保留 Discourse 顶层的 pinned_at，因此在登录用户
    // 打开话题时只探测一次。结果出来前保持隐藏，不让“取消置顶”按钮在普通
    // 未置顶话题上短暂闪现。请求放到当前 frame 结束后启动，避免 build 中
    // 直接 setState。
    if (_state == null && !_loading && !_loadFailed) {
      _scheduleLoadState();
    }

    final state = _state;
    if (state == null || !state.hasAdminPin) {
      return const SizedBox.shrink();
    }

    // Discourse 原生操作是带选中态的双选项菜单：管理员设置的
    // 全局/板块置顶只决定作用范围，用户在这里修改的仅是自己的显示状态。
    final isPinned = state.pinned && !state.unpinned;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final trigger = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_mutating)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.onSurfaceVariant,
              ),
            )
          else
            Icon(
              isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              size: 16,
              color: colors.onSurfaceVariant,
            ),
          const SizedBox(width: 6),
          Text(
            isPinned ? state.scopeLabel : '已取消置顶',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down_rounded, size: 18, color: colors.onSurfaceVariant),
        ],
      ),
    );

    const tooltip = '选择个人置顶状态（不影响其他用户）';
    if (MediaQuery.sizeOf(context).width < 600) {
      return Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _mutating
                ? null
                : () => unawaited(_showMobileOptions(state, isPinned)),
            borderRadius: BorderRadius.circular(8),
            child: trigger,
          ),
        ),
      );
    }

    return PopupMenuButton<bool>(
      tooltip: tooltip,
      enabled: !_mutating,
      onSelected: (value) {
        if (value != isPinned) unawaited(_setPinned(value));
      },
      itemBuilder: (menuContext) => [
        for (final pinned in [true, false])
          PopupMenuItem<bool>(
            value: pinned,
            height: 72,
            child: SizedBox(
              width: 300,
              child: _optionContent(
                menuContext,
                state,
                pinned: pinned,
                selected: pinned == isPinned,
              ),
            ),
          ),
      ],
      child: trigger,
    );
  }
}
