import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification.dart';
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

/// 通知列表 Notifier (支持分页和刷新，用于历史通知页面)
/// autoDispose：离开页面后自动清除，下次进入重新加载
class NotificationListNotifier
    extends AsyncNotifier<List<DiscourseNotification>>
    with PagedAsyncNotifierMixin<DiscourseNotification> {
  int _totalRows = 0;
  NotificationReadFilter _filter = NotificationReadFilter.all;

  NotificationReadFilter get filter => _filter;

  /// 分页助手
  static final _paginationHelper = PaginationHelpers.forNotifications<DiscourseNotification>(
    keyExtractor: (n) => n.id,
  );

  Future<PagedPage<DiscourseNotification>> _fetchFirstPage() async {
    final service = ref.read(discourseServiceProvider);
    final response = await service.getNotifications(filter: _filter.apiValue);
    _totalRows = response.totalRowsNotifications;
    return PagedPage(
      items: response.notifications,
      hasMore: response.notifications.length < _totalRows,
    );
  }

  @override
  Future<List<DiscourseNotification>> build() async {
    resetPagingState();
    final page = await _fetchFirstPage();
    return completePagedRefresh(page);
  }

  /// 切换全部 / 已读 / 未读筛选。
  ///
  /// 直接重新请求 Discourse，而不是只过滤本地已加载页，保证分页总数正确。
  Future<void> setFilter(NotificationReadFilter filter) async {
    if (_filter == filter && state.hasValue) return;
    _filter = filter;
    await refresh();
  }

  /// 刷新列表
  Future<void> refresh() async {
    await runPagedRefresh(_fetchFirstPage);
  }

  /// 加载更多
  Future<void> loadMore() async {
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

final notificationListProvider = AsyncNotifierProvider.autoDispose<NotificationListNotifier, List<DiscourseNotification>>(() {
  return NotificationListNotifier();
});
