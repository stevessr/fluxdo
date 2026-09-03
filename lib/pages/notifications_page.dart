import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification_category.dart';
import '../providers/discourse_providers.dart';
import '../providers/preferences_provider.dart';
import '../utils/load_more_coordinator.dart';
import '../widgets/desktop_refresh_indicator.dart';
import '../utils/notification_navigation.dart';
import '../widgets/notification/notification_item.dart';
import '../widgets/notification/notification_list_skeleton.dart';
import '../widgets/common/error_view.dart';
import '../widgets/common/paged_list_footer.dart';
import '../l10n/s.dart';
import '../utils/blocked_user_filter.dart';
import 'bookmarks_page.dart';

/// 通知历史列表页面（独立分页，不受 messageBus 干扰）
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  final ScrollController _scrollController = ScrollController();
  final LoadMoreCoordinator _loadMoreCoordinator = LoadMoreCoordinator();
  NotificationReadFilter _filter = NotificationReadFilter.all;
  NotificationCategory _category = NotificationCategory.all;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final distance =
        _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    if (_loadMoreCoordinator.shouldTriggerForDistance(distance)) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final notifier = ref.read(notificationListProvider.notifier);
    await _loadMoreCoordinator.loadMore(
      loadMore: notifier.loadMore,
      hasMore: () => notifier.hasMore,
      isActive: () => mounted,
      progressCount: () =>
          ref.read(notificationListProvider).value?.length ?? 0,
    );
  }

  Future<void> _onRefresh() async {
    _loadMoreCoordinator.resetCooldown();
    await ref.read(notificationListProvider.notifier).refresh();
  }

  Future<void> _setFilter(NotificationReadFilter filter) async {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    _loadMoreCoordinator.resetCooldown();
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    await ref.read(notificationListProvider.notifier).setFilter(filter);
  }

  Future<void> _setCategory(NotificationCategory category) async {
    // Discourse 的“书签”用户菜单不是 bookmark_reminder 通知分类：它通过
    // /u/:username/user-menu-bookmarks 混合真实书签和提醒。FluxDO 已有完整
    // 的书签数据源/缓存/分页，因此这里进入真实书签页，避免继续把“书签”
    // 错做成只有 reminder 的通知列表。
    if (category == NotificationCategory.bookmarks) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const BookmarksPage()));
      return;
    }

    if (_category == category) return;
    setState(() => _category = category);
    _loadMoreCoordinator.resetCooldown();
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    await ref.read(notificationListProvider.notifier).setCategory(category);
  }

  String _filterLabel(BuildContext context, NotificationReadFilter filter) {
    switch (filter) {
      case NotificationReadFilter.all:
        return context.l10n.notification_filterAll;
      case NotificationReadFilter.read:
        return context.l10n.notification_filterRead;
      case NotificationReadFilter.unread:
        return context.l10n.notification_filterUnread;
    }
  }

  String _parityLabel(BuildContext context, String zh, String en) {
    return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
  }

  String _categoryLabel(BuildContext context, NotificationCategory category) {
    return switch (category) {
      NotificationCategory.all => context.l10n.notification_categoryAll,
      NotificationCategory.responses => _parityLabel(context, '回复', 'Responses'),
      NotificationCategory.likes => _parityLabel(
        context,
        '收到的赞',
        'Likes received',
      ),
      NotificationCategory.mentions => _parityLabel(context, '提及', 'Mentions'),
      NotificationCategory.edits => _parityLabel(context, '编辑', 'Edits'),
      NotificationCategory.links => _parityLabel(context, '链接', 'Links'),
      NotificationCategory.messages => context.l10n.notification_categoryMessages,
      NotificationCategory.bookmarks => context.l10n.notification_categoryBookmarks,
      NotificationCategory.other => context.l10n.notification_categoryOther,
    };
  }

  IconData _categoryIcon(NotificationCategory category) {
    return switch (category) {
      NotificationCategory.all => Symbols.notifications_rounded,
      NotificationCategory.responses => Symbols.reply_rounded,
      NotificationCategory.likes => Symbols.favorite_rounded,
      NotificationCategory.mentions => Symbols.alternate_email_rounded,
      NotificationCategory.edits => Symbols.edit_rounded,
      NotificationCategory.links => Symbols.link_rounded,
      NotificationCategory.messages => Symbols.mail_rounded,
      NotificationCategory.bookmarks => Symbols.bookmark_rounded,
      NotificationCategory.other => Symbols.more_horiz_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationListProvider);
    final systemAvatarTemplate = ref
        .watch(systemUserAvatarTemplateProvider)
        .value;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.common_notification),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Symbols.done_all_rounded),
            onPressed: () async {
              await ref.read(notificationListProvider.notifier).markAllAsRead();
              // 快捷面板下次打开时会自动 silentRefresh 同步已读状态
            },
            tooltip: context.l10n.notification_markAllRead,
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              itemCount: NotificationCategory.values.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = NotificationCategory.values[index];
                return ChoiceChip(
                  avatar: Icon(_categoryIcon(category), size: 18),
                  label: Text(_categoryLabel(context, category)),
                  selected: _category == category,
                  onSelected: (_) => _setCategory(category),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SegmentedButton<NotificationReadFilter>(
                segments: NotificationReadFilter.values
                    .map(
                      (filter) => ButtonSegment<NotificationReadFilter>(
                        value: filter,
                        label: Text(_filterLabel(context, filter)),
                      ),
                    )
                    .toList(growable: false),
                selected: {_filter},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  if (selection.isNotEmpty) {
                    _setFilter(selection.first);
                  }
                },
              ),
            ),
          ),
          Expanded(
            child: DesktopRefreshIndicator(
              onRefresh: _onRefresh,
              child: notificationsAsync.when(
                data: (notifications) {
                  final blockedUsernames = ref.watch(
                    preferencesProvider.select(
                      (p) => p.normalizedBlockedUsernames,
                    ),
                  );
                  // 类型分类已经在 provider 的数据源层完成，这里只保留本地
                  // 用户屏蔽过滤，绝不再为了“凑够分类条目”扫描历史分页。
                  final visibleNotifications = notifications
                      .where(
                        (notification) =>
                            !BlockedUserFilter.isBlockedNotification(
                              notification,
                              blockedUsernames,
                            ),
                      )
                      .toList(growable: false);
                  final notifier = ref.read(notificationListProvider.notifier);

                  // 只有“全部”历史分页可能因为当前页全被本地屏蔽而需要补载。
                  // 子分类本身是 bounded recent，hasMore=false，不会触发这里。
                  if (_category == NotificationCategory.all &&
                      visibleNotifications.isEmpty &&
                      notifications.isNotEmpty &&
                      notifier.hasMore) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _loadMore();
                    });
                  }

                  if (visibleNotifications.isEmpty &&
                      (notifications.isEmpty || !notifier.hasMore)) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Symbols.notifications_rounded,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            context.l10n.notification_empty,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    itemCount: visibleNotifications.length + 1,
                    itemBuilder: (context, index) {
                      if (index == visibleNotifications.length) {
                        return PagedListFooter(
                          hasMore: notifier.hasMore,
                          isLoadingMore: notifier.isLoadingMore,
                          isLoadMoreFailed: notifier.isLoadMoreFailed,
                          onRetry: notifier.retryLoadMore,
                        );
                      }
                      final notification = visibleNotifications[index];
                      return NotificationItem(
                        notification: notification,
                        systemAvatarTemplate: systemAvatarTemplate,
                        // siblings = 当前数据源已经正确分类后的列表。
                        onTap: () {
                          notifier.markAsRead(notification.id);
                          handleNotificationTap(
                            context,
                            ref,
                            notification,
                            siblings: visibleNotifications,
                          );
                        },
                      );
                    },
                  );
                },
                loading: () => const NotificationListSkeleton(),
                error: (error, stack) => ErrorView(
                  error: error,
                  stackTrace: stack,
                  onRetry: _onRefresh,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
