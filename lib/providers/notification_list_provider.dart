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
  NotificationReadFilter _filter = NotificationReadFilter.all;
  NotificationCategory _category = NotificationCategory.all;

  NotificationReadFilter get filter => _filter;
  NotificationCategory get category => _category;

  /// 分页助手
  static final _paginationHelper =
      PaginationHelpers.forNotifications<DiscourseNotification>(
        keyExtractor: (n) => n.id,
      );

  bool _matchesReadFilter(DiscourseNotification notification) {
    return switch (_filter) {
      NotificationReadFilter.all => true,
      NotificationReadFilter.read => notification.read,
      NotificationReadFilter.unread => !notification.read,
    };
  }

  Future<PagedPage<DiscourseNotification>> _fetchFirstPage() async {
    final service = ref.read(discourseServiceProvider);

    if (_category == NotificationCategory.all) {
      final response = await service.getNotifications(filter: _filter.apiValue);
      _totalRows = response.totalRowsNotifications;
      return PagedPage(
        items: response.notifications,
        hasMore: response.notifications.length < _totalRows,
      );
    }

    // `filter_by_types` is only applied by Discourse in the recent branch.
    // Keep this request bounded to one server page. `other` has no static type
    // list because plugins can add notification types; it fetches the same
    // bounded recent page and applies the complement locally.
    final response = await service.getRecentNotifications(
      filterByTypes: _category.serverFilterTypeNames,
      limit: 60,
      silent: true,
      bumpLastSeenReviewable: false,
    );
    final items = response.notifications
        .where(_category.matches)
        .where(_matchesReadFilter)
        .toList(growable: false);
    _totalRows = items.length;
    return PagedPage(items: items, hasMore: false);
  }

  @override
  Future<List<DiscourseNotification>> build() async {
    resetPagingState();
    final page = await _fetchFirstPage();
    return completePagedRefresh(page);
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

  /// 刷新列表
  Future<void> refresh() async {
    await runPagedRefresh(_fetchFirstPage);
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
        hasMore:
            response.notifications.isNotEmpty && paginationResult.hasMore,
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
      state = AsyncValue.data(
        list.map((n) => n.copyWith(read: true)).toList(),
      );
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

final notificationListProvider = AsyncNotifierProvider.autoDispose<
  NotificationListNotifier,
  List<DiscourseNotification>
>(() {
  return NotificationListNotifier();
});
