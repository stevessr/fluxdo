import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification.dart';
import '../models/notification_category.dart';
import '../utils/paged_async_notifier.dart';
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

/// 通知列表：分类首屏使用 Discourse recent API，之后按历史 offset 续页。
///
/// recent 是唯一支持 filter_by_types 的分支，但完全忽略 offset；历史分支
/// 支持 offset / read 筛选，却忽略通知类型。续页因此必须逐批扫描并按类型
/// 本地筛选，不能用当前显示的分类条数当作原始历史记录的 offset。
class NotificationListNotifier
    extends AsyncNotifier<List<DiscourseNotification>>
    with PagedAsyncNotifierMixin<DiscourseNotification> {
  static const int _historyPageSize = 60;
  // 稀有类型最多每次扫描四个历史页，避免触底后请求风暴。
  static const int _maxHistoryPagesPerLoad = 4;

  int _totalRows = 0;
  int _historyOffset = 0;
  int _refreshGeneration = 0;
  bool _needsManualLoadMore = false;
  NotificationReadFilter _filter = NotificationReadFilter.all;
  NotificationCategory _category = NotificationCategory.all;

  NotificationReadFilter get filter => _filter;
  NotificationCategory get category => _category;
  bool get needsManualLoadMore => _needsManualLoadMore;
  int get historyOffset => _historyOffset;

  /// 用户明确继续查找更早的历史通知。
  void allowMoreHistoryScan() => _needsManualLoadMore = false;

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

  Future<({
    PagedPage<DiscourseNotification> page,
    int totalRows,
    int historyOffset,
  })> _fetchFirstPage({
    required NotificationCategory category,
    required NotificationReadFilter filter,
  }) async {
    final service = ref.read(discourseServiceProvider);

    if (category == NotificationCategory.all) {
      final response = await service.getNotifications(filter: filter.apiValue);
      return (
        page: PagedPage(
          items: response.notifications,
          // 服务端总数是在过滤不可见记录前统计的；不要用实际返回条数
          // 作为 offset，否则有被隐藏的项目时会重复请求同一批记录。
          hasMore: _historyPageSize < response.totalRowsNotifications,
        ),
        totalRows: response.totalRowsNotifications,
        historyOffset: _historyPageSize,
      );
    }

    // Discourse recent 按类型返回最近通知，但不支持 offset；保留它作为
    // 快速首屏，触底后从历史接口逐页寻找仍未显示的同类型记录。
    final response = await service.getRecentNotifications(
      filterByTypes: category.serverFilterTypeNames,
      limit: _historyPageSize,
      silent: true,
      bumpLastSeenReviewable: false,
    );
    final items = response.notifications
        .where(category.matches)
        .where((notification) => _matchesReadFilter(notification, filter))
        .toList(growable: false);
    return (
      page: PagedPage(items: items, hasMore: true),
      totalRows: 0, // recent 响应不包含历史总数，第一次续页时获取。
      historyOffset: 0,
    );
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
    _historyOffset = result.historyOffset;
    _needsManualLoadMore = false;
    return completePagedRefresh(result.page);
  }

  /// 切换全部 / 已读 / 未读筛选。
  ///
  /// “全部”模式由服务端历史接口筛选；子分类 recent 首屏在本地按已读
  /// 状态过滤，历史续页还会向服务端传入 read / unread 以减少扫描量。
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
      _historyOffset = result.historyOffset;
      _needsManualLoadMore = false;
      state = AsyncValue.data(completePagedRefresh(result.page));
    } catch (error, stackTrace) {
      if (generation != _refreshGeneration) return;
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// 继续分页。历史 offset 按服务端扫描记录数推进，而不是按分类命中数。
  ///
  /// 分类 recent 首屏可能已经涵盖了很久以前的 60 条，因此续页必须去重；
  /// 每轮至多扫描四页，若全是非目标类型 / 重复条目，则等待用户手动继续。
  Future<void> loadMore() async {
    if (_needsManualLoadMore) return;
    final generation = _refreshGeneration;
    final category = _category;
    final filter = _filter;

    await runPagedLoadMore(
      (currentList, _) async {
        final service = ref.read(discourseServiceProvider);
        var offset = _historyOffset;
        var totalRows = _totalRows;
        final ids = currentList.map((item) => item.id).toSet();
        final additions = <DiscourseNotification>[];
        final pages = category == NotificationCategory.all
            ? 1
            : _maxHistoryPagesPerLoad;

        for (var page = 0; page < pages; page++) {
          final response = await service.getNotifications(
            offset: offset,
            filter: filter.apiValue,
          );
          // 切换筛选/分类期间完成的旧请求不得写入新分类游标。
          if (generation != _refreshGeneration) {
            return PagedPage(items: currentList, hasMore: false);
          }
          totalRows = response.totalRowsNotifications;
          offset += _historyPageSize;

          for (final item in response.notifications) {
            if (category.matches(item) &&
                _matchesReadFilter(item, filter) &&
                ids.add(item.id)) {
              additions.add(item);
            }
          }

          if (offset >= totalRows || additions.isNotEmpty) break;
        }

        if (generation != _refreshGeneration) {
          return PagedPage(items: currentList, hasMore: false);
        }
        _historyOffset = offset;
        _totalRows = totalRows;
        final hasMoreHistory = offset < totalRows;
        _needsManualLoadMore =
            category != NotificationCategory.all &&
            additions.isEmpty &&
            hasMoreHistory;

        final result = [...currentList, ...additions];
        if (category != NotificationCategory.all) {
          result.sort((a, b) {
            final timeOrder = b.createdAt.compareTo(a.createdAt);
            return timeOrder != 0 ? timeOrder : b.id.compareTo(a.id);
          });
        }
        return PagedPage(items: result, hasMore: hasMoreHistory);
      },
      isCurrent: () => generation == _refreshGeneration,
    );
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
