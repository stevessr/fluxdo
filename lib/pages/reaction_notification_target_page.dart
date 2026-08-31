import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification.dart';
import '../providers/discourse_providers.dart';
import '../utils/notification_post_target.dart';
import '../widgets/common/error_view.dart';
import 'topic_detail_page/topic_detail_page.dart';

/// Reaction 通知的应用内落点。
///
/// 普通 reaction 直接使用通知顶层 topic_id + post_number；Discourse 会把
/// 同一用户对多条帖子的 reaction 合并，此时两个顶层字段都可能为空，
/// 只能借 data.original_post_id 回查 PostSerializer 中的真实位置。
class ReactionNotificationTargetPage extends ConsumerStatefulWidget {
  const ReactionNotificationTargetPage({
    super.key,
    required this.notification,
  });

  final DiscourseNotification notification;

  @override
  ConsumerState<ReactionNotificationTargetPage> createState() =>
      _ReactionNotificationTargetPageState();
}

class _ReactionNotificationTargetPageState
    extends ConsumerState<ReactionNotificationTargetPage> {
  Future<NotificationPostTarget>? _targetFuture;

  @override
  void initState() {
    super.initState();
    _startFallbackLookup();
  }

  void _startFallbackLookup() {
    final postId = reactionFallbackPostId(widget.notification);
    if (postId == null) return;
    _targetFuture = _loadTarget(postId);
  }

  Future<NotificationPostTarget> _loadTarget(int postId) async {
    final response = await ref
        .read(discourseServiceProvider)
        .dio
        .get('/posts/$postId.json');
    final target = parseNotificationPostTarget(response.data);
    if (target == null) {
      throw const FormatException(
        'Reaction post response is missing topic_id.',
      );
    }
    return target;
  }

  void _retry() {
    final postId = reactionFallbackPostId(widget.notification);
    if (postId == null) return;
    setState(() {
      _targetFuture = _loadTarget(postId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final notification = widget.notification;

    // 完整的单帖 reaction 不增加任何网络请求。
    if (notification.topicId != null && notification.postNumber != null) {
      return TopicDetailPage(
        topicId: notification.topicId!,
        scrollToPostNumber: notification.postNumber,
      );
    }

    final targetFuture = _targetFuture;
    if (targetFuture == null) {
      // 极旧/异常 payload 没有 original_post_id 时仍保留原先的降级能力：
      // 有 topic_id 就至少打开话题，不让通知彻底失去落点。
      if (notification.topicId != null) {
        return TopicDetailPage(topicId: notification.topicId!);
      }
      return Scaffold(
        appBar: AppBar(),
        body: ErrorView(
          error: const FormatException(
            'Reaction notification has no post target.',
          ),
          showDetails: false,
        ),
      );
    }

    return FutureBuilder<NotificationPostTarget>(
      future: targetFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          // 若通知至少还带着 topic_id，回查失败时继续沿用旧行为，避免网络
          // 抖动把原本可打开的话题变成死通知；只是无法精确定位楼层。
          if (notification.topicId != null) {
            return TopicDetailPage(topicId: notification.topicId!);
          }
          return Scaffold(
            appBar: AppBar(),
            body: ErrorView(
              error: snapshot.error ??
                  const FormatException('Reaction post target is unavailable.'),
              onRetry: _retry,
            ),
          );
        }

        final target = snapshot.data!;
        return TopicDetailPage(
          topicId: target.topicId,
          scrollToPostNumber: target.postNumber,
        );
      },
    );
  }
}
