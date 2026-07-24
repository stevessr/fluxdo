import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification.dart';
import '../providers/discourse_providers.dart';
import '../pages/topic_detail_page/topic_detail_page.dart';
import '../pages/user_profile_page.dart';
import '../pages/badge_page.dart';
import '../pages/chat/chat_message_page.dart';
import '../services/local_notification_service.dart';
import '../l10n/s.dart';

NavigatorState? _rootNavigator(BuildContext context) {
  return navigatorKey.currentState ??
      Navigator.of(context, rootNavigator: true);
}

void _pushOnRootNavigator(BuildContext context, Widget page) {
  _rootNavigator(context)?.push(MaterialPageRoute(builder: (_) => page));
}

/// 处理通知点击：标记已读 + 按类型跳转
/// 快捷面板和历史列表页面共用
void handleNotificationTap(
  BuildContext context,
  WidgetRef ref,
  DiscourseNotification notification,
) {
  // 如果通知未读，先标记为已读
  if (!notification.read) {
    // 更新快捷面板本地状态
    ref.read(recentNotificationsProvider.notifier).markAsRead(notification.id);

    // 异步发送标记已读请求
    ref
        .read(discourseServiceProvider)
        .markNotificationRead(notification.id)
        .catchError((e) {
          debugPrint('标记通知已读失败: $e');
        });
  }

  // 根据通知类型决定跳转逻辑
  switch (notification.notificationType) {
    case NotificationType.inviteeAccepted:
    case NotificationType.following:
      if (notification.username != null) {
        _pushOnRootNavigator(
          context,
          UserProfilePage(username: notification.username!),
        );
      }
      break;

    case NotificationType.grantedBadge:
      if (notification.data.badgeId != null) {
        final currentUser = ref.read(currentUserProvider).value;
        _pushOnRootNavigator(
          context,
          BadgePage(
            badgeId: notification.data.badgeId!,
            badgeSlug: notification.data.badgeSlug,
            username: currentUser?.username,
          ),
        );
      }
      break;

    case NotificationType.membershipRequestAccepted:
      break;

    case NotificationType.boost:
      if (notification.topicId != null) {
        _pushOnRootNavigator(
          context,
          TopicDetailPage(
            topicId: notification.topicId!,
            scrollToPostNumber: notification.postNumber,
            highlightBoostUsername: notification.data.displayUsername,
          ),
        );
      }
      break;

    case NotificationType.edited:
      // 帖子被编辑通知:跳转到对应话题 + 打开编辑历史 modal 到指定 revision。
      // 对齐 discourse 网页版 `edited.js` 的 `setLastEditNotificationClick` 逻辑。
      if (notification.topicId != null) {
        _pushOnRootNavigator(
          context,
          TopicDetailPage(
            topicId: notification.topicId!,
            scrollToPostNumber: notification.postNumber,
            initialRevisionPostNumber: notification.postNumber,
            initialRevisionNumber: notification.data.revisionNumber,
          ),
        );
      }
      break;

    case NotificationType.chatMention:
    case NotificationType.chatMessage:
    case NotificationType.chatInvitation:
    case NotificationType.chatGroupMention:
    case NotificationType.chatQuotedPost:
    case NotificationType.chatWatchedThread:
      if (notification.data.chatChannelId != null) {
        _pushOnRootNavigator(
          context,
          ChatMessagePage(
            channelId: notification.data.chatChannelId!,
            channelTitle: notification.data.topicTitle ?? S.current.chat_title,
          ),
        );
      } else if (notification.topicId != null) {
        // 降级：没有频道 ID 时跳转到话题
        _pushOnRootNavigator(
          context,
          TopicDetailPage(
            topicId: notification.topicId!,
            scrollToPostNumber: notification.postNumber,
          ),
        );
      }
      break;

    default:
      if (notification.topicId != null) {
        _pushOnRootNavigator(
          context,
          TopicDetailPage(
            topicId: notification.topicId!,
            scrollToPostNumber: notification.postNumber,
          ),
        );
      }
      break;
  }
}
