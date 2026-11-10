import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/s.dart';
import '../models/notification.dart';
import '../providers/discourse_providers.dart';
import '../providers/selected_topic_provider.dart';
import '../navigation/nav_action_bus.dart';
import '../utils/notification_post_target.dart';
import '../pages/badge_page.dart';
import '../pages/chat/chat_message_page.dart';
import '../pages/reaction_notification_target_page.dart';
import '../pages/topic_detail_page/topic_detail_page.dart';
import '../pages/user_profile_page.dart';
import '../services/local_notification_service.dart';
import '../widgets/layout/master_detail_layout.dart';

NavigatorState? _rootNavigator(BuildContext context) {
  return navigatorKey.currentState ??
      Navigator.of(context, rootNavigator: true);
}

/// 通知入口不再使用覆盖内容的预览弹窗。
void openNotificationPage(BuildContext context, Widget page) {
  _rootNavigator(context)?.push(MaterialPageRoute(builder: (_) => page));
}

/// 通知 → 落点页面。null = 该通知没有可打开的目标(如入群申请通过)。
///
/// 话题/私信共用 TopicDetailPage,无需辨 archetype;
/// autoSwitchToMasterDetail 保持关闭 —— 通知打开的是临时查看面,中途
/// 拉宽窗口保持原样,不自动折叠进工作区栈(私信话题会折进错误的栈,
/// 这正是弹窗方案要消灭的分支)。
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
  container.read(selectedTopicProvider.notifier).openTopicTab(
    topicId: topicId,
    initialTitle: notification.data.topicTitle ?? notification.fancyTitle,
    scrollToPostNumber: postNumber ?? notification.postNumber,
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
  int postId,
) async {
  try {
    final response = await container
        .read(discourseServiceProvider)
        .dio
        .get('/posts/$postId.json');
    final target = parseNotificationPostTarget(response.data);
    if (target != null) {
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
  if (notification.topicId != null) {
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
  _markNotificationRead(container, notification);

  if (MasterDetailLayout.canShowBothPanesFor(context) &&
      _isTopicNotification(notification)) {
    final fallbackPostId = reactionFallbackPostId(notification);
    if (fallbackPostId != null) {
      _openReactionTabAfterLookup(container, notification, fallbackPostId);
      return;
    }
    if (notification.topicId != null) {
      _openTopicNotificationTab(
        container,
        notification,
        topicId: notification.topicId!,
      );
      return;
    }
  }

  final page = _notificationTargetPage(
    notification,
    currentUsername: ref.read(currentUserProvider).value?.username,
  );
  if (page != null) {
    _rootNavigator(context)?.push(MaterialPageRoute(builder: (_) => page));
  }
}
