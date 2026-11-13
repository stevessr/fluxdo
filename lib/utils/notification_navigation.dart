import 'package:common_ui/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/s.dart';
import '../models/notification.dart';
import '../providers/discourse_providers.dart';
import '../providers/notification_list_provider.dart';
import '../providers/selected_topic_provider.dart';
import '../navigation/nav_action_bus.dart';
import '../utils/notification_post_target.dart';
import '../utils/dialog_utils.dart';
import '../pages/badge_page.dart';
import '../pages/private_messages_page.dart';
import '../pages/chat/chat_message_page.dart';
import '../pages/reaction_notification_target_page.dart';
import '../pages/topic_detail_page/topic_detail_page.dart';
import '../pages/user_profile_page.dart';
import '../services/local_notification_service.dart';
import '../widgets/layout/master_detail_layout.dart';
import '../widgets/common/page_dialog.dart';
import '../widgets/notification/notification_item.dart';

/// 隔离正在等待原帖回查的通知：后一次点击优先于较早的异步跳转。
final Expando<int> _notificationNavigationGeneration =
    Expando<int>('notificationNavigationGeneration');

NavigatorState? _rootNavigator(BuildContext context) {
  return navigatorKey.currentState ??
      Navigator.of(context, rootNavigator: true);
}

/// 完整通知页从其他位置作为路由进入时，用稳定名称识别该入口。
const notificationPageRouteName = '/fluxdo/notifications';

/// 切换到首页工作区前退出临时通知列表路由；主导航常驻页不受影响。
void _closeNotificationRouteIfNeeded(
  NavigatorState? navigator,
  Route<dynamic>? originRoute,
) {
  if (originRoute?.settings.name == notificationPageRouteName &&
      originRoute?.isCurrent == true) {
    navigator?.pop();
  }
}

/// 打开通知页面。完整列表使用稳定路由名；其他页面维持大屏弹窗体验。
void openNotificationPage(
  BuildContext context,
  Widget page, {
  bool isNotificationList = false,
}) {
  if (!isNotificationList && MasterDetailLayout.canShowBothPanesFor(context)) {
    showPageDialog(context: context, builder: (_) => page);
    return;
  }
  _rootNavigator(context)?.push(
    InteractionPageRoute(
      settings: RouteSettings(
        name: isNotificationList ? notificationPageRouteName : null,
      ),
      builder: (_) => page,
    ),
  );
}

/// 通知 → 落点页面。null = 该通知没有可打开的目标(如入群申请通过)。
///
/// 这是窄屏路由及非话题目标的构造器；宽屏话题（包括私信）由
/// _openTopicNotificationTab 直接交给首页工作区的独立 Tab。
/// 两者共用 TopicDetailPage，无需预取话题 archetype。
Widget? _notificationTargetPage(
  DiscourseNotification notification, {
  String? currentUsername,
}) {
  switch (notification.notificationType) {
    case NotificationType.inviteeAccepted:
    case NotificationType.following:
      final username = notification.username;
      if (username == null) return null;
      return UserProfilePage(username: username);

    case NotificationType.grantedBadge:
      final badgeId = notification.data.badgeId;
      if (badgeId == null) return null;
      return BadgePage(
        badgeId: badgeId,
        badgeSlug: notification.data.badgeSlug,
        username: currentUsername,
      );

    case NotificationType.membershipRequestAccepted:
      return null;

    case NotificationType.groupMessageSummary:
      // 汇总通知可能没有 topic_id，此时仍要能进入私信列表。
      if (notification.topicId == null) {
        return const PrivateMessagesPage();
      }
      return TopicDetailPage(
        topicId: notification.topicId!,
        scrollToPostNumber: notification.postNumber,
      );

    case NotificationType.boost:
      if (notification.topicId == null) return null;
      return TopicDetailPage(
        topicId: notification.topicId!,
        scrollToPostNumber: notification.postNumber,
        highlightBoostUsername: notification.data.displayUsername,
      );

    case NotificationType.edited:
      // 帖子被编辑通知:跳转到对应话题 + 打开编辑历史 modal 到指定
      // revision。对齐网页版 `edited.js` 的 setLastEditNotificationClick。
      if (notification.topicId == null) return null;
      return TopicDetailPage(
        topicId: notification.topicId!,
        scrollToPostNumber: notification.postNumber,
        initialRevisionPostNumber: notification.postNumber,
        initialRevisionNumber: notification.data.revisionNumber,
      );

    case NotificationType.reaction:
      // discourse-reactions 会把同一用户对多条帖子的 reaction 合并；
      // consolidated 通知没有顶层 topic_id/post_number，但仍保留
      // data.original_post_id。交给专用页面按 post id 回查真实落点，
      // 私信与普通话题都能精确跳到被 reaction 的帖子。
      if (notification.topicId == null &&
          int.tryParse(notification.data.originalPostId ?? '') == null) {
        return null;
      }
      return ReactionNotificationTargetPage(notification: notification);

    case NotificationType.chatMention:
    case NotificationType.chatMessage:
    case NotificationType.chatInvitation:
    case NotificationType.chatGroupMention:
    case NotificationType.chatQuotedPost:
    case NotificationType.chatWatchedThread:
      // 聊天通知：打开频道并定位到具体消息
      final channelId = notification.data.chatChannelId;
      if (channelId == null) {
        if (notification.topicId == null) return null;
        return TopicDetailPage(
          topicId: notification.topicId!,
          scrollToPostNumber: notification.postNumber,
        );
      }
      return ChatMessagePage(
        channelId: channelId,
        channelTitle: notification.data.topicTitle ?? S.current.chat_title,
        targetMessageId: notification.data.chatMessageId,
      );

    default:
      // privateMessage/posted/liked 等所有话题类落点
      if (notification.topicId == null) return null;
      return TopicDetailPage(
        topicId: notification.topicId!,
        scrollToPostNumber: notification.postNumber,
      );
  }
}

/// 标记已读的副作用(快捷面板本地态 + 服务端),点击与弹窗内翻页共用
void _markNotificationRead(
  ProviderContainer container,
  DiscourseNotification notification,
) {
  if (notification.read) return;
  container
      .read(recentNotificationsProvider.notifier)
      .markAsRead(notification.id);
  // 仅更新已经挂载的完整通知列表。快捷面板单独使用时不额外触发
  // 历史通知首屏请求；两种入口同时存在时也能同步已读/未读筛选。
  if (container.exists(notificationListProvider)) {
    container
        .read(notificationListProvider.notifier)
        .markAsRead(notification.id);
  }
  container
      .read(discourseServiceProvider)
      .markNotificationRead(notification.id)
      .catchError((e) {
        debugPrint('标记通知已读失败: $e');
      });
}

/// 通知跳转采用稳定的导航 ID，兼容自定义底栏顺序。
void _openTopicNotificationTab(
  ProviderContainer container,
  DiscourseNotification notification, {
  required int topicId,
  int? postNumber,
}) {
  final targetPostNumber = postNumber ?? notification.postNumber;
  // 已打开的 Tab 可能缓存了上一次浏览的楼层。通知带有明确落点时先
  // 清掉该实例的恢复位置，否则 TopicDetailPane 会优先读旧缓存，
  // 从而忽略这次通知的新楼层。
  if (targetPostNumber != null) {
    final previousTabs = container.read(selectedTopicProvider).stack;
    for (final pane in previousTabs) {
      if (pane.kind == PaneKind.topic &&
          pane.topicId == topicId &&
          pane.instanceId != null) {
        container
            .read(
              detailScrollPositionProvider((
                topicId: topicId,
                instanceId: pane.instanceId!,
              )).notifier,
            )
            .state = null;
        break;
      }
    }
  }

  container.read(selectedTopicProvider.notifier).openTopicTab(
    topicId: topicId,
    initialTitle: notification.data.topicTitle ?? notification.fancyTitle,
    scrollToPostNumber: targetPostNumber,
    isPrivateMessage:
        notification.notificationType == NotificationType.privateMessage ||
        notification.notificationType ==
            NotificationType.invitedToPrivateMessage ||
        notification.notificationType ==
            NotificationType.groupMessageSummary,
    replaceNavigationTarget: true,
    highlightBoostUsername: notification.notificationType == NotificationType.boost
        ? notification.data.displayUsername
        : null,
    initialRevisionPostNumber:
        notification.notificationType == NotificationType.edited
            ? notification.postNumber
            : null,
    initialRevisionNumber:
        notification.notificationType == NotificationType.edited
            ? notification.data.revisionNumber
            : null,
  );
  final previous = container.read(navDestinationRequestProvider);
  container.read(navDestinationRequestProvider.notifier).state =
      NavDestinationRequest(
        targetId: NavEntryIds.home,
        nonce: (previous?.nonce ?? 0) + 1,
      );
}

/// 私信本身就是 topic：不区分 archetype，同普通话题使用独立 Tab。
bool _isTopicNotification(DiscourseNotification notification) {
  switch (notification.notificationType) {
    case NotificationType.inviteeAccepted:
    case NotificationType.following:
    case NotificationType.grantedBadge:
    case NotificationType.membershipRequestAccepted:
    case NotificationType.chatMention:
    case NotificationType.chatMessage:
    case NotificationType.chatInvitation:
    case NotificationType.chatGroupMention:
    case NotificationType.chatQuotedPost:
    case NotificationType.chatWatchedThread:
      return false;
    default:
      return notification.topicId != null ||
          (notification.notificationType == NotificationType.reaction &&
              reactionFallbackPostId(notification) != null);
  }
}

/// Discourse 对同一用户多帖 Reaction 聚合后可能清空顶层 topic_id。
/// 回查原帖定位成功再开 Tab；失败时提供可重试的完整落点页。
Future<void> _openReactionTabAfterLookup(
  ProviderContainer container,
  DiscourseNotification notification,
  int postId, {
  required int navigationGeneration,
  required NavigatorState? navigator,
  required Route<dynamic>? originRoute,
}) async {
  try {
    final response = await container
        .read(discourseServiceProvider)
        .dio
        .get('/posts/$postId.json');
    // 用户可能在网络请求期间点开了另一条通知，旧结果不能抢回前台。
    if (_notificationNavigationGeneration[container] != navigationGeneration ||
        (originRoute != null && !originRoute.isCurrent)) {
      return;
    }
    final target = parseNotificationPostTarget(response.data);
    if (target != null) {
      _closeNotificationRouteIfNeeded(navigator, originRoute);
      _openTopicNotificationTab(
        container,
        notification,
        topicId: target.topicId,
        postNumber: target.postNumber,
      );
      return;
    }
  } catch (error) {
    debugPrint('无法定位聚合 Reaction 通知: $error');
  }
  if (_notificationNavigationGeneration[container] != navigationGeneration ||
      (originRoute != null && !originRoute.isCurrent)) {
    return;
  }
  if (notification.topicId != null) {
    _closeNotificationRouteIfNeeded(navigator, originRoute);
    _openTopicNotificationTab(
      container,
      notification,
      topicId: notification.topicId!,
    );
  } else {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ReactionNotificationTargetPage(
          notification: notification,
        ),
      ),
    );
  }
}

/// 点击直接进入话题 Tab 或对应页面；不再创建通知内预览/翻页弹窗。
/// [siblings] 为旧调用方保留，通知列表自行负责分类和切换。
void handleNotificationTap(
  BuildContext context,
  WidgetRef ref,
  DiscourseNotification notification, {
  List<DiscourseNotification>? siblings,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final navigator = _rootNavigator(context);
  final originRoute = ModalRoute.of(context);
  final navigationGeneration =
      (_notificationNavigationGeneration[container] ?? 0) + 1;
  _notificationNavigationGeneration[container] = navigationGeneration;
  _markNotificationRead(container, notification);

  if (MasterDetailLayout.canShowBothPanesFor(context) &&
      _isTopicNotification(notification)) {
    final fallbackPostId = reactionFallbackPostId(notification);
    if (fallbackPostId != null) {
      _openReactionTabAfterLookup(
        container,
        notification,
        fallbackPostId,
        navigationGeneration: navigationGeneration,
        navigator: navigator,
        originRoute: originRoute,
      );
      return;
    }
    if (notification.topicId != null) {
      _closeNotificationRouteIfNeeded(navigator, originRoute);
      _openTopicNotificationTab(
        container,
        notification,
        topicId: notification.topicId!,
      );
      return;
    }
  }

  final currentUsername = ref.read(currentUserProvider).value?.username;
  final page = _notificationTargetPage(
    notification,
    currentUsername: currentUsername,
  );
  if (page == null) return;

  if (!MasterDetailLayout.canShowBothPanesFor(context)) {
    _rootNavigator(context)?.push(InteractionPageRoute(builder: (_) => page));
    return;
  }

  // 大屏:可翻页的通知弹窗。播放列表只保留有落点的通知,
  // 上一条/下一条不会停在"点了没反应"的条目上。
  final playlist = (siblings ?? [notification])
      .where(
        (n) =>
            _notificationTargetPage(n, currentUsername: currentUsername) !=
            null,
      )
      .toList(growable: false);
  final initialIndex = playlist.indexWhere((n) => n.id == notification.id);

  showAppGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: S.current.common_close,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _NotificationPagerDialog(
        playlist: playlist,
        initialIndex: initialIndex < 0 ? 0 : initialIndex,
        container: container,
        currentUsername: currentUsername,
      );
    },
  );
}

/// 大屏通知弹窗 + 上一条/下一条翻页 + 通知列表
///
/// 切换 = 换 [PageDialogScaffold.contentKey] 让嵌套导航整体重建(上一条
/// 里点开的内链子页不残留),同时补标已读。列表顺序即通知面板顺序,
/// 「下一条」向更早的通知走。
///
/// 列表形态自适应:屏幕够宽(≥1240)时常驻左侧栏,否则顶部给列表
/// 按钮,点开后列表作为抽屉盖在内容上。
class _NotificationPagerDialog extends StatefulWidget {
  const _NotificationPagerDialog({
    required this.playlist,
    required this.initialIndex,
    required this.container,
    required this.currentUsername,
  });

  final List<DiscourseNotification> playlist;
  final int initialIndex;

  /// 弹窗生命周期长于发起方 widget(快捷面板点击后即收起销毁),
  /// 副作用统一走开弹窗时捕获的 container,不再依赖发起方的 ref
  final ProviderContainer container;
  final String? currentUsername;

  @override
  State<_NotificationPagerDialog> createState() =>
      _NotificationPagerDialogState();
}

class _NotificationPagerDialogState extends State<_NotificationPagerDialog>
    with SingleTickerProviderStateMixin {
  late int _index = widget.initialIndex;

  /// 本次弹窗会话内已补标已读的通知(播放列表是打开时的快照,provider
  /// 里的已读更新不会流回来,列表条目的未读圆点靠这份本地覆盖消隐)
  late final Set<int> _locallyRead = {widget.playlist[widget.initialIndex].id};

  /// 窄弹窗模式的列表抽屉开合
  late final AnimationController _drawerController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void dispose() {
    _drawerController.dispose();
    super.dispose();
  }

  void _goTo(int index, {bool closeDrawer = false}) {
    if (index < 0 || index >= widget.playlist.length) return;
    if (closeDrawer) _drawerController.reverse();
    if (index == _index) return;
    final notification = widget.playlist[index];
    setState(() {
      _index = index;
      _locallyRead.add(notification.id);
    });
    _markNotificationRead(widget.container, notification);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notification = widget.playlist[_index];
    final hasMultiple = widget.playlist.length > 1;
    // 常驻侧栏需要 880(内容) + 332(列表) + 页边距的空间
    final useSidebar = hasMultiple && MediaQuery.sizeOf(context).width >= 1240;

    final list = _NotificationPagerList(
      playlist: widget.playlist,
      currentIndex: _index,
      locallyRead: _locallyRead,
      container: widget.container,
      onSelect: (i) => _goTo(i, closeDrawer: !useSidebar),
    );

    return PageDialogScaffold(
      contentKey: ValueKey(notification.id),
      sidebar: useSidebar ? list : null,
      overlay: !useSidebar && hasMultiple ? _buildDrawer(theme, list) : null,
      topBar: [
        if (hasMultiple) ...[
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: Text(
              '${_index + 1} / ${widget.playlist.length}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (!useSidebar)
            pageDialogTopButton(
              tooltip: context.l10n.notification_showList,
              icon: Symbols.list_rounded,
              onPressed: () {
                if (_drawerController.isForwardOrCompleted) {
                  _drawerController.reverse();
                } else {
                  _drawerController.forward();
                }
              },
            ),
          pageDialogTopButton(
            tooltip: context.l10n.notification_previous,
            icon: Symbols.keyboard_arrow_up_rounded,
            onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
          ),
          pageDialogTopButton(
            tooltip: context.l10n.notification_next,
            icon: Symbols.keyboard_arrow_down_rounded,
            onPressed: _index < widget.playlist.length - 1
                ? () => _goTo(_index + 1)
                : null,
          ),
        ],
      ],
      builder: (_) =>
          _notificationTargetPage(
            notification,
            currentUsername: widget.currentUsername,
          ) ??
          const SizedBox.shrink(),
      // 全屏打开当前条目(播放列表已滤掉无落点通知,页面必然非 null);
      // 全屏后翻页/列表随弹窗一起退场,回来重新从通知入口进即可
      fullscreenBuilder: (_) =>
          _notificationTargetPage(
            notification,
            currentUsername: widget.currentUsername,
          ) ??
          const SizedBox.shrink(),
    );
  }

  /// 窄弹窗模式:列表抽屉从左滑入盖在内容上,点遮罩/选中条目收回
  Widget _buildDrawer(ThemeData theme, Widget list) {
    return AnimatedBuilder(
      animation: _drawerController,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_drawerController.value);
        if (t == 0) return const SizedBox.shrink();
        return Positioned.fill(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => _drawerController.reverse(),
                  child: ColoredBox(
                    color: Colors.black26.withValues(alpha: 0.26 * t),
                  ),
                ),
              ),
              PositionedDirectional(
                start: (t - 1) * 340,
                top: 0,
                bottom: 0,
                width: 340,
                child: Material(
                  color: theme.colorScheme.surface,
                  elevation: 4,
                  child: child,
                ),
              ),
            ],
          ),
        );
      },
      child: list,
    );
  }
}

/// 弹窗内的通知列表(常驻侧栏与抽屉共用):当前条目高亮,点击切换
class _NotificationPagerList extends StatefulWidget {
  const _NotificationPagerList({
    required this.playlist,
    required this.currentIndex,
    required this.locallyRead,
    required this.container,
    required this.onSelect,
  });

  final List<DiscourseNotification> playlist;
  final int currentIndex;
  final Set<int> locallyRead;
  final ProviderContainer container;
  final void Function(int index) onSelect;

  @override
  State<_NotificationPagerList> createState() => _NotificationPagerListState();
}

class _NotificationPagerListState extends State<_NotificationPagerList> {
  /// 初始定位到当前条目附近(条目高度不定,按估高粗定位即可)
  static const double _estimatedItemExtent = 88;

  late final ScrollController _scrollController = ScrollController(
    initialScrollOffset: (widget.currentIndex * _estimatedItemExtent - 120)
        .clamp(0, double.infinity),
  );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final systemAvatarTemplate = widget.container
        .read(systemUserAvatarTemplateProvider)
        .value;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.playlist.length,
      itemBuilder: (context, index) {
        var notification = widget.playlist[index];
        // 播放列表是快照,已读状态用本地覆盖修正未读圆点
        if (!notification.read &&
            widget.locallyRead.contains(notification.id)) {
          notification = notification.copyWith(read: true);
        }
        final selected = index == widget.currentIndex;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.45)
                : Colors.transparent,
          ),
          child: NotificationItem(
            notification: notification,
            systemAvatarTemplate: systemAvatarTemplate,
            onTap: () => widget.onSelect(index),
          ),
        );
      },
    );
  }
}
