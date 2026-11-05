import 'dart:async';

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

  Timer? _realtimeSyncTimer;
  final Set<int> _seenRealtimeIds = <int>{};

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

  Future<
    ({PagedPage<DiscourseNotification> page, int totalRows, int historyOffset})
  >
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
    ref.onDispose(() => _realtimeSyncTimer?.cancel());
    _seenRealtimeIds.clear();
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
    _realtimeSyncTimer?.cancel();
    _realtimeSyncTimer = null;
    _seenRealtimeIds.clear();
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

  /// Apply MessageBus updates to the visible history without rebuilding its pages.
  ///
  /// The recent notifications panel has its own provider; the full history
  /// page must receive the same events while it is mounted. Never instantiate
  /// this auto-dispose notifier merely because a background event arrived.
  void applyRealtimeUpdate({
    DiscourseNotification? latest,
    Map<int, bool> readStatuses = const <int, bool>{},
  }) {
    if (latest == null && readStatuses.isEmpty) return;
    final current = state.value;
    // A fresh page request will provide current data. If the push overtakes
    // that response, a silent reconciliation will recover the missing item.
    if (current == null || state.isLoading) {
      scheduleRealtimeSync();
      return;
    }

    final seen = current.any((item) => item.id == latest?.id);
    final isNewEvent = latest != null && _seenRealtimeIds.add(latest.id);
    if (_seenRealtimeIds.length > 256) {
      _seenRealtimeIds.clear();
      if (latest != null) _seenRealtimeIds.add(latest.id);
    }

    final next = <DiscourseNotification>[];
    var changed = false;
    var readFilteredSetChanged = false;
    for (final old in current) {
      var item = old;
      if (latest != null && old.id == latest.id) {
        // A repeated last_notification may contain the stale unread flag.
        // Only an explicit recent status can reverse an already-read item.
        item = latest.copyWith(read: old.read || latest.read);
      }
      final read = readStatuses[item.id];
      if (read != null && read != item.read) {
        item = item.copyWith(read: read);
      }
      if (_filter != NotificationReadFilter.all &&
          _matchesReadFilter(old, _filter) !=
              _matchesReadFilter(item, _filter)) {
        readFilteredSetChanged = true;
      }
      if (!_matchesReadFilter(item, _filter)) {
        changed = true;
        continue;
      }
      next.add(item);
      if (!identical(item, old)) changed = true;
    }

    if (latest != null && !seen) {
      var item = latest;
      final read = readStatuses[item.id];
      if (read != null && read != item.read) {
        item = item.copyWith(read: read);
      }
      if (_category.matches(item) && _matchesReadFilter(item, _filter)) {
        next.add(item);
        changed = true;
      }
    }

    // MessageBus does not carry the server's historical offset. It may
    // replay messages from before our last fetch, or remove read-filtered
    // rows at arbitrary positions. Rewind rather than guessing an offset
    // and silently skipping older notifications on the next load.
    if ((isNewEvent && !seen) || readFilteredSetChanged) {
      _historyOffset = 0;
      _totalRows = 0;
      _needsManualLoadMore = false;
      resetPagingState(hasMore: true);
    }

    if (!changed) return;
    next.sort((a, b) {
      final byTime = b.createdAt.compareTo(a.createdAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
    ++_refreshGeneration;
    state = AsyncValue.data(next);
  }

  /// Some MessageBus messages carry only counts/recent IDs, without a complete
  /// last_notification. Reconcile the first page quietly and coalesce bursts,
  /// keeping previously loaded history and the user's scroll position.
  void scheduleRealtimeSync() {
    _realtimeSyncTimer?.cancel();
    _realtimeSyncTimer = Timer(const Duration(milliseconds: 450), () {
      _realtimeSyncTimer = null;
      unawaited(_syncLatestSilently());
    });
  }

  Future<void> _syncLatestSilently() async {
    if (!ref.mounted) return;
    if (state.isLoading) {
      scheduleRealtimeSync();
      return;
    }
    final current = state.value;
    if (current == null) return;
    final generation = _refreshGeneration;
    final category = _category;
    final filter = _filter;
    try {
      final result = await _fetchFirstPage(category: category, filter: filter);
      if (!ref.mounted || generation != _refreshGeneration || state.isLoading) {
        return;
      }
      final fresh = result.page.items;
      final freshIds = fresh.map((n) => n.id).toSet();
      final oldestFresh = fresh.isEmpty ? null : fresh.last.createdAt;
      final olderCached = current.where((item) {
        if (freshIds.contains(item.id)) return false;
        // Records missing from the refreshed first page must not survive
        // inside that page's time window (for example after being read on
        // another device). Keep genuinely older pages for scroll stability.
        if (category == NotificationCategory.all &&
            !result.page.hasMore) {
          return false;
        }
        return _matchesReadFilter(item, filter) &&
            (oldestFresh == null ||
                item.createdAt.isBefore(oldestFresh));
      });
      final merged = <DiscourseNotification>[
        ...fresh,
        ...olderCached,
      ]..sort((a, b) {
        final byTime = b.createdAt.compareTo(a.createdAt);
        return byTime != 0 ? byTime : b.id.compareTo(a.id);
      });

      // The filtered recent endpoint has no historical raw offset. Start
      // scanning again at the beginning and dedupe against cached pages
      // rather than guessing where new rows landed in the raw history.
      _historyOffset = result.historyOffset;
      _totalRows = result.totalRows;
      _needsManualLoadMore = false;
      resetPagingState(hasMore: result.page.hasMore);
      for (final item in fresh) {
        _seenRealtimeIds.add(item.id);
      }
      state = AsyncValue.data(merged);
    } catch (_) {
      // A dropped push must not replace an otherwise usable list with an
      // error. Pull-to-refresh remains available if the connection is down.
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

    await runPagedLoadMore((currentList, _) async {
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
    }, isCurrent: () => generation == _refreshGeneration);
  }

  /// 手动重试加载更多
  Future<void> retryLoadMore() {
    return retryPagedLoadMore(loadMore);
  }

  /// 标记所有为已读
  Future<void> markAllAsRead() async {
    final service = ref.read(discourseServiceProvider);
    await service.markAllNotificationsRead();

    // 服务端操作已成功：取消所有仍在飞行中的旧分页响应。
    // 否则旧的 unread 结果可能在清空列表后再次发布。
    ++_refreshGeneration;
    ref.read(notificationCountStateProvider.notifier).markAllRead();

    if (_filter == NotificationReadFilter.unread) {
      _totalRows = 0;
      _historyOffset = 0;
      _needsManualLoadMore = false;
      resetPagingState(hasMore: false);
      state = const AsyncValue.data([]);
      return;
    }

    // 即使当前处于带有 previous value 的分页 loading 状态，
    // 也要立即发布已读数据，结束旧的 loading 快照。
    // read 筛选的服务端数据集已经扩大；刷新以免旧 offset 跳页。
    // Riverpod 的 loading 也可能保留上一分类的数据，不能将它当成本次首屏。
    if (_filter == NotificationReadFilter.read || state.isLoading) {
      await refresh();
      return;
    }
    final currentList = state.value;
    if (currentList == null) {
      await refresh();
      return;
    }
    state = AsyncValue.data(
      currentList.map((n) => n.copyWith(read: true)).toList(),
    );
  }

  /// 标记单个通知为已读。
  ///
  /// 取消正在进行的历史续页，避免它用请求开始时的旧列表覆盖本地已读状态。
  void markAsRead(int notificationId) {
    final currentList = state.value;
    if (currentList == null) return;

    if (_filter == NotificationReadFilter.unread) {
      final nextList = currentList
          .where((n) => n.id != notificationId)
          .toList();
      if (nextList.length == currentList.length) return;
      ++_refreshGeneration;
      _totalRows = (_totalRows - 1).clamp(0, _totalRows).toInt();
      // 未读列表在服务端缩短，下一次 offset 必须回退以免漏掉一条。
      if (_historyOffset > 0) _historyOffset--;
      state = AsyncValue.data(nextList);
      return;
    }

    if (!currentList.any((n) => n.id == notificationId && !n.read)) return;
    ++_refreshGeneration;
    state = AsyncValue.data(
      currentList.map((n) {
        if (n.id == notificationId) {
          return n.copyWith(read: true);
        }
        return n;
      }).toList(),
    );
  }
}

final notificationListProvider =
    AsyncNotifierProvider.autoDispose<
      NotificationListNotifier,
      List<DiscourseNotification>
    >(() {
      return NotificationListNotifier();
    });
