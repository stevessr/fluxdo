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
  LoadMoreCoordinator _loadMoreCoordinator = LoadMoreCoordinator();
  NotificationReadFilter _filter = NotificationReadFilter.all;
  NotificationCategory _category = NotificationCategory.all;
  bool _autoFillScheduled = false;
  int _autoFillAttempts = 0;
  static const int _maxAutoFillAttempts = 2;

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
    if (!_scrollController.hasClients) return;
    final distance =
        _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    if (_loadMoreCoordinator.shouldTriggerForDistance(distance)) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final notifier = ref.read(notificationListProvider.notifier);
    if (notifier.category != _category ||
        notifier.filter != _filter ||
        notifier.needsManualLoadMore) {
      return;
    }
    await _loadMoreCoordinator.loadMore(
      loadMore: notifier.loadMore,
      hasMore: () => notifier.hasMore,
      isActive: () => mounted,
      progressCount: () =>
          ref.read(notificationListProvider).value?.length ?? 0,
    );
  }

  /// 首屏记录不足以撑满视口时没有滚动事件，主动尝试补充少量历史页。
  /// 每次分类切换只自动补两轮，避免稀有类型无限扫描。
  void _maybeAutoFillViewport() {
    if (_autoFillScheduled || _autoFillAttempts >= _maxAutoFillAttempts) {
      return;
    }
    _autoFillScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoFillScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;
      final notifier = ref.read(notificationListProvider.notifier);
      if (notifier.category != _category ||
          notifier.filter != _filter ||
          !notifier.hasMore ||
          notifier.isLoadingMore ||
          notifier.needsManualLoadMore ||
          _scrollController.position.maxScrollExtent > 0) {
        return;
      }
      _autoFillAttempts++;
      _loadMore();
    });
  }

  Future<void> _continueHistory() async {
    _loadMoreCoordinator.resetCooldown();
    ref.read(notificationListProvider.notifier).allowMoreHistoryScan();
    // Manual continuation should not restart automatic scanning loops.
    _autoFillAttempts = _maxAutoFillAttempts;
    await _loadMore();
  }

  Future<void> _onRefresh() async {
    _autoFillAttempts = 0;
    // 旧分类的网络请求可能仍未结束，不能占用新分类的协调器。
    _loadMoreCoordinator = LoadMoreCoordinator();
    await ref.read(notificationListProvider.notifier).refresh();
  }

  Future<void> _setFilter(NotificationReadFilter filter) async {
    if (_filter == filter) return;
    setState(() {
      _filter = filter;
      _autoFillAttempts = 0;
    });
    // 旧分类的网络请求可能仍未结束，不能占用新分类的协调器。
    _loadMoreCoordinator = LoadMoreCoordinator();
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
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const BookmarksPage()));
      return;
    }

    if (_category == category) return;
    setState(() {
      _category = category;
      _autoFillAttempts = 0;
    });
    // 旧分类的网络请求可能仍未结束，不能占用新分类的协调器。
    _loadMoreCoordinator = LoadMoreCoordinator();
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

  String _categoryLabel(BuildContext context, NotificationCategory category) {
    return switch (category) {
      NotificationCategory.all => context.l10n.notification_categoryAll,
      NotificationCategory.mentions =>
        context.l10n.notification_categoryMentions,
      NotificationCategory.replies => context.l10n.notification_categoryReplies,
      NotificationCategory.likes => context.l10n.notification_categoryLikes,
      NotificationCategory.messages =>
        context.l10n.notification_categoryMessages,
      NotificationCategory.bookmarks =>
        context.l10n.notification_categoryBookmarks,
      NotificationCategory.assigned =>
        context.l10n.notification_categoryAssigned,
      NotificationCategory.chat => context.l10n.notification_categoryChat,
      NotificationCategory.other => context.l10n.notification_categoryOther,
    };
  }

  IconData _categoryIcon(NotificationCategory category) {
    return switch (category) {
      NotificationCategory.all => Symbols.notifications_rounded,
      NotificationCategory.mentions => Symbols.alternate_email_rounded,
      NotificationCategory.replies => Symbols.reply_rounded,
      NotificationCategory.likes => Symbols.favorite_rounded,
      NotificationCategory.messages => Symbols.mail_rounded,
      NotificationCategory.bookmarks => Symbols.bookmark_rounded,
      NotificationCategory.assigned => Symbols.person_add_rounded,
      NotificationCategory.chat => Symbols.chat_bubble_rounded,
      NotificationCategory.other => Symbols.more_horiz_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationListProvider);
    final systemAvatarTemplate = ref
        .watch(systemUserAvatarTemplateProvider)
        .value;

    // Use this pane's actual constraints, not the physical display width.
    // A notification page nested inside a narrow parallel pane stays compact.
    return LayoutBuilder(
      builder: (context, constraints) {
        // 平行视界中直接展示一级通知分类，不再折叠到二级选择。
        final showCategoryRail = constraints.maxWidth >= 640;
        return Scaffold(
          appBar: AppBar(
            title: Text(context.l10n.common_notification),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Symbols.done_all_rounded),
                onPressed: () async {
                  await ref
                      .read(notificationListProvider.notifier)
                      .markAllAsRead();
                  // 快捷面板下次打开时会自动 silentRefresh 同步已读状态
                },
                tooltip: context.l10n.notification_markAllRead,
              ),
            ],
          ),
          body: Row(
            children: [
              if (showCategoryRail) ...[
                SizedBox(
                  width: 216,
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: SafeArea(
                      top: false,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 16,
                        ),
                        children: [
                          for (final category in NotificationCategory.values)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: ListTile(
                                dense: true,
                                leading: Icon(_categoryIcon(category)),
                                title: Text(_categoryLabel(context, category)),
                                selected: _category == category,
                                selectedTileColor: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                onTap: () => _setCategory(category),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
              ],
              Expanded(
                child: Column(
                  children: [
                    if (!showCategoryRail)
                      SizedBox(
                        height: 52,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                          itemCount: NotificationCategory.values.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 8),
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
                                (filter) =>
                                    ButtonSegment<NotificationReadFilter>(
                                      value: filter,
                                      label: Text(
                                        _filterLabel(context, filter),
                                      ),
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
                            // 历史游标扫描及类型筛选由 provider 负责；
                            // UI 只做用户屏蔽过滤，避免影响分页偏移量。
                            final visibleNotifications = notifications
                                .where(
                                  (notification) =>
                                      !BlockedUserFilter.isBlockedNotification(
                                        notification,
                                        blockedUsernames,
                                      ),
                                )
                                .toList(growable: false);
                            final notifier = ref.read(
                              notificationListProvider.notifier,
                            );

                            // 即使分类为空也必须保留一个可滚动的分页视图；
                            // 否则该分类永远不会触发下一页历史查询。
                            if (visibleNotifications.isEmpty &&
                                !notifier.hasMore) {
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
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            if (notifier.hasMore &&
                                !notifier.isLoadingMore &&
                                !notifier.isLoadMoreFailed &&
                                !notifier.needsManualLoadMore) {
                              _maybeAutoFillViewport();
                            }

                            return ListView.builder(
                              controller: _scrollController,
                              itemCount: visibleNotifications.length + 1,
                              itemBuilder: (context, index) {
                                if (index == visibleNotifications.length) {
                                  if (notifier.hasMore &&
                                      !notifier.isLoadingMore &&
                                      !notifier.isLoadMoreFailed &&
                                      (notifier.needsManualLoadMore ||
                                          _autoFillAttempts >=
                                              _maxAutoFillAttempts)) {
                                    return Center(
                                      child: TextButton(
                                        onPressed: _continueHistory,
                                        child: Text(
                                          context.l10n.common_searchMore,
                                        ),
                                      ),
                                    );
                                  }
                                  return PagedListFooter(
                                    hasMore: notifier.hasMore,
                                    isLoadingMore: notifier.isLoadingMore,
                                    isLoadMoreFailed: notifier.isLoadMoreFailed,
                                    onRetry: notifier.retryLoadMore,
                                  );
                                }
                                final notification =
                                    visibleNotifications[index];
                                return NotificationItem(
                                  notification: notification,
                                  systemAvatarTemplate: systemAvatarTemplate,
                                  // siblings = 当前数据源已经正确分类后的列表。
                                  onTap: () {
                                    // 已读状态统一由导航入口同步近期与完整列表。
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
              ),
            ],
          ),
        );
      },
    );
  }
}
