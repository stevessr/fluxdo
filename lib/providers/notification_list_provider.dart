import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification.dart';
import '../models/notification_category.dart';
import '../utils/paged_async_notifier.dart';
import '../utils/pagination_helper.dart';
import 'core_providers.dart';
import 'message_bus_providers.dart';

/// Discourse 通知历史页原生的已读状态筛选。
enum NotificationReadFilter {
  all('all'),
  read('read'),
  unread('unread');

  final String apiValue;
  const NotificationReadFilter(this.apiValue);
}

/// 通知列表 Notifier。
///
/// “全部”使用 Discourse 历史通知接口并正常分页；用户菜单语义的通知子分类
/// 使用 bounded recent API。后者是 Discourse 真正支持 `filter_by_types` 的
/// 分支，避免为了在本地凑够某一类通知而把历史页连续全部拉下来。
class NotificationListNotifier
    extends AsyncNotifier<List<DiscourseNotification>>
    with PagedAsyncNotifierMixin<DiscourseNotification> {
  int _totalRows = 0;
  int _refreshGeneration = 0;
  NotificationReadFilter _filter = NotificationReadFilter.all;
  NotificationCategory _category = NotificationCategory.all;

  NotificationReadFilter get filter => _filter;
  NotificationCategory get category => _category;

  /// 分页助手
  static final _paginationHelper =
      PaginationHelpers.forNotifications<DiscourseNotification>(
        keyExtractor: (n) => n.id,
      );

  bool _matchesReadFilter(
    DiscourseNotification notification,
    NotificationReadFilter filter,
  ) {
    return switch (filter) {
      NotificationReadFilter.all => true,
      NotificationReadFilter.read => notification.read,
      NotificationReadFilter.unread => !notification.read,
    };
  }

  Future<({PagedPage<DiscourseNotification> page, int totalRows})>
  _fetchFirstPage({
    required NotificationCategory category,
    required NotificationReadFilter filter,
  }) async {
    final service = ref.read(discourseServiceProvider);

    if (category == NotificationCategory.all) {
      final response = await service.getNotifications(filter: filter.apiValue);
      return (
        page: PagedPage(
          items: response.notifications,
          hasMore: response.notifications.length < response.totalRowsNotifications,
        ),
        totalRows: response.totalRowsNotifications,
      );
    }

    // Discourse applies `filter_by_types` only to the recent endpoint.
    // Capture category/filter before awaiting: a quick tab switch must never
    // process an older response using the newly selected category.
    final response = await service.getRecentNotifications(
      filterByTypes: category.serverFilterTypeNames,
      limit: 60,
      silent: true,
      bumpLastSeenReviewable: false,
    );
    final items = response.notifications
        .where(category.matches)
        .where((notification) => _matchesReadFilter(notification, filter))
        .toList(growable: false);
    return (page: PagedPage(items: items, hasMore: false), totalRows: items.length);
  }

  @override
  Future<List<DiscourseNotification>> build() async {
    final generation = ++_refreshGeneration;
    resetPagingState();
    final result = await _fetchFirstPage(category: _category, filter: _filter);
    if (generation != _refreshGeneration) {
      // A selection change already started a newer refresh. Keep its result.
      return state.value ?? const <DiscourseNotification>[];
    }
    _totalRows = result.totalRows;
    return completePagedRefresh(result.page);
  }

  /// 切换全部 / 已读 / 未读筛选。
  ///
  /// “全部”模式由服务端历史接口筛选；子分类是 bounded recent 列表，已读
  /// 状态在这 60 条内过滤，且不会为此继续翻历史分页。
  Future<void> setFilter(NotificationReadFilter filter) async {
    if (_filter == filter && state.hasValue) return;
    _filter = filter;
    await refresh();
  }

  /// 切换通知类型子分类并重新从正确的数据源获取。
  Future<void> setCategory(NotificationCategory category) async {
    if (_category == category && state.hasValue) return;
    _category = category;
    await refresh();
  }

  /// 刷新列表。过期的分类请求不可覆盖最后一次用户选择。
  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    final category = _category;
    final filter = _filter;
    resetPagingState();
    state = const AsyncLoading<List<DiscourseNotification>>();
    try {
      final result = await _fetchFirstPage(category: category, filter: filter);
      if (generation != _refreshGeneration) return;
      _totalRows = result.totalRows;
      state = AsyncValue.data(completePagedRefresh(result.page));
    } catch (error, stackTrace) {
      if (generation != _refreshGeneration) return;
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// 加载更多。只有“全部”历史通知支持分页；子分类是 bounded recent。
  Future<void> loadMore() async {
    if (_category != NotificationCategory.all) return;

    await runPagedLoadMore((currentList, _) async {
      final offset = currentList.length;

      final service = ref.read(discourseServiceProvider);
      final response = await service.getNotifications(
        offset: offset,
        filter: _filter.apiValue,
      );

      final currentState = PaginationState(items: currentList);
      final paginationResult = _paginationHelper.processLoadMore(
        currentState,
        PaginationResult(items: response.notifications, totalRows: _totalRows),
      );

      return PagedPage(
        items: paginationResult.items,
        hasMore: response.notifications.isNotEmpty && paginationResult.hasMore,
      );
    });
  }

  /// 手动重试加载更多
  Future<void> retryLoadMore() {
    return retryPagedLoadMore(loadMore);
  }

  /// 标记所有为已读
  Future<void> markAllAsRead() async {
    final service = ref.read(discourseServiceProvider);
    await service.markAllNotificationsRead();

    // 重置通知计数
    ref.read(notificationCountStateProvider.notifier).markAllRead();

    // 未读筛选下所有项目都已离开当前筛选集合。
    if (_filter == NotificationReadFilter.unread) {
      _totalRows = 0;
      resetPagingState(hasMore: false);
      state = const AsyncValue.data([]);
      return;
    }

    // 其他筛选只需更新本地已加载项目。
    state.whenData((list) {
      state = AsyncValue.data(list.map((n) => n.copyWith(read: true)).toList());
    });
  }

  /// 标记单个通知为已读
  void markAsRead(int notificationId) {
    state.whenData((list) {
      if (_filter == NotificationReadFilter.unread) {
        final nextList = list.where((n) => n.id != notificationId).toList();
        if (nextList.length != list.length) {
          _totalRows = (_totalRows - 1).clamp(0, _totalRows).toInt();
          state = AsyncValue.data(nextList);
        }
        return;
      }

      state = AsyncValue.data(
        list.map((n) {
          if (n.id == notificationId && !n.read) {
            return n.copyWith(read: true);
          }
          return n;
        }).toList(),
      );
    });
  }
}

final notificationListProvider =
    AsyncNotifierProvider.autoDispose<
      NotificationListNotifier,
      List<DiscourseNotification>
    >(() {
      return NotificationListNotifier();
    });
