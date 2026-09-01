import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_session.dart';
import '../services/preloaded_data_service.dart';
import 'core_providers.dart';
import 'bookmark_name_suggestions_provider.dart';
import 'bookmark_sync_controller.dart';
import 'notification_list_provider.dart';
import 'topic_list/topic_list_provider.dart';
import 'topic_list/filter_provider.dart';
import 'topic_list/sort_provider.dart';
import 'topic_list/tab_state_provider.dart';
import 'pinned_categories_provider.dart';
import 'user_content_providers.dart';
import 'category_provider.dart';
import 'message_bus/notification_providers.dart';
import 'message_bus/topic_tracking_providers.dart';
import 'ldc_providers.dart';
import 'chat_providers.dart';
import 'cdk_providers.dart';

class AppStateRefresher {
  AppStateRefresher._();

  static DateTime? _lastRefreshTime;
  static int _refreshEpoch = 0;

  /// 调用方用 [ProviderScope.containerOf] 取 container 后传入，
  /// 避免 [Future.delayed] 闭包持有的 [WidgetRef] 在延迟期间随 widget unmount 失效，
  /// 进而抛 StateError 中断后续 invalidate（曾导致登录后 ProfilePage 卡 loading）。
  static void refreshAll(
    ProviderContainer container, {
    bool force = false,
    bool refreshCurrentUser = true,
  }) {
    // 去抖：2 秒内重复调用直接跳过（如 authStateProvider listener + _goToLogin 同时触发）。
    // 多账号切换等关键路径用 force=true 绕过去抖，确保切换后状态必然刷新。
    final now = DateTime.now();
    if (!force &&
        _lastRefreshTime != null &&
        now.difference(_lastRefreshTime!) < const Duration(seconds: 2)) {
      return;
    }
    _lastRefreshTime = now;
    final refreshEpoch = ++_refreshEpoch;

    // 第一批：主页渲染必需（用户信息 + 分类 + 话题列表）。账号切换会先
    // 原子刷新 currentUser，再用 refreshCurrentUser=false 刷其余状态，避免
    // 第二次 invalidate 把刚提交的目标身份重新打回 loading/游客外观。
    if (refreshCurrentUser) {
      container.invalidate(currentUserProvider);
    }
    for (final refresh in _coreRefreshers) {
      refresh(container);
    }
    _refreshTopicTabs(container);
    // 第二批：延迟 1 秒执行，避免并发请求过多触发风控
    Future.delayed(const Duration(seconds: 1), () {
      // 切换账号后，上一轮延迟刷新不能再把旧账号请求重新唤醒。
      if (refreshEpoch != _refreshEpoch) return;
      for (final refresh in _deferredRefreshers) {
        refresh(container);
      }
    });
  }

  static Future<void> resetForLogout(ProviderContainer container) async {
    // 先使已有的延迟刷新失效，避免退出/重新登录窗口中的旧闭包重新
    // invalidate provider，把旧账号请求带入新会话。
    _refreshEpoch++;
    final generation = AuthSession().generation;
    await Future.wait([
      container.read(currentUserProvider.notifier).clearCache(),
      container.read(userSummaryProvider.notifier).clearCache(),
    ]);
    if (!AuthSession().isValid(generation)) return;
    container.read(bookmarkNameSuggestionsProvider.notifier).clearCache();
    container.read(bookmarkSyncControllerProvider.notifier).reset();
    container.invalidate(currentUsernameProvider);
    // 登出时 invalidate 所有（不会发请求，因为数据被清空了）
    container.invalidate(currentUserProvider);
    for (final refresh in _coreRefreshers) {
      refresh(container);
    }
    for (final refresh in _deferredRefreshers) {
      refresh(container);
    }
    // 重置筛选/排序/标签（会通过 signal listener 触发话题列表刷新，
    // 无需再手动 invalidate 话题列表）
    container
        .read(topicFilterProvider.notifier)
        .setFilter(TopicListFilter.latest);
    container
        .read(topicSortOrderProvider.notifier)
        .setOrder(TopicSortOrder.defaultOrder);
    container.read(topicSortAscendingProvider.notifier).setAscending(false);
    final pinnedIds = container.read(pinnedCategoriesProvider);
    container.read(tabTagsProvider(null).notifier).state = [];
    for (final id in pinnedIds) {
      container.read(tabTagsProvider(id).notifier).state = [];
    }
    container.read(activeCategorySlugsProvider.notifier).reset();
    await container.read(ldcUserInfoProvider.notifier).disable();
    await container.read(cdkUserInfoProvider.notifier).disable();
  }

  /// 多账号切换后调用：清掉与「上一个账号」绑定的本地缓存并整体刷新。
  ///
  /// 与 [resetForLogout] 的差别：不重置筛选/排序、不禁用 LDC/CDK，也不把
  /// currentUser 主动清成 null。切换遮罩还在时先把身份原子刷新为目标账号，
  /// 再重建其余账号级状态，避免导航和“我的”短暂/持续落入游客外观。
  static Future<void> resetForAccountSwitch(ProviderContainer container) async {
    // 清理尚未执行的上一账号延迟刷新；refreshAll 完成后会再建立新 epoch。
    _refreshEpoch++;
    final generation = AuthSession().generation;

    // currentUser 的持久缓存本身按 username 校验，目标身份刷新成功后也会
    // 覆盖旧缓存。这里不能调用 clearCache()：它会同步 emit data(null)，
    // 导航层把 null 当作真实登出，正是切换后出现“游客 UI”的来源。
    await container.read(userSummaryProvider.notifier).clearCache();
    if (!AuthSession().isValid(generation)) return;
    container.read(bookmarkNameSuggestionsProvider.notifier).clearCache();
    container.read(bookmarkSyncControllerProvider.notifier).reset();
    container.invalidate(currentUsernameProvider);

    await _refreshCurrentUserForAccountSwitch(container, generation);
    if (!AuthSession().isValid(generation)) return;

    // 身份已经由 preload 快路径或网络兜底提交，不要再次 invalidate currentUser。
    refreshAll(container, force: true, refreshCurrentUser: false);
  }

  static Future<void> _refreshCurrentUserForAccountSwitch(
    ProviderContainer container,
    int generation,
  ) async {
    final service = container.read(discourseServiceProvider);
    final expectedUsername = await service.getCurrentUsername();
    if (!AuthSession().isValid(generation) ||
        expectedUsername == null ||
        expectedUsername.isEmpty) {
      return;
    }

    // finalizeNativeLoginSuccess 已经等待首页 preload 完成。正常切换时这里
    // 已经有目标账号 current_user：让 provider 直接从这份内存数据重建，
    // build 内会立即提交目标身份，并把 /u/... 的完整资料刷新留到后台。
    // 这样前台切换不再为同一个用户额外等待一次网络 RTT。
    final preloaded = PreloadedDataService().currentUserSync;
    final preloadedUsername = preloaded?['username']?.toString();
    if (preloadedUsername != null &&
        preloadedUsername.toLowerCase() == expectedUsername.toLowerCase()) {
      container.invalidate(currentUserProvider);
      final currentUser = await container.read(currentUserProvider.future);
      if (!AuthSession().isValid(generation)) return;
      if (currentUser?.username.toLowerCase() == expectedUsername.toLowerCase()) {
        return;
      }
    }

    // preload 不可用（网络/CF/解析失败）时保留原来的同步网络兜底，确保
    // 账户切换不会因为性能优化而牺牲身份一致性。
    var notifier = container.read(currentUserProvider.notifier);
    await notifier.refreshSilently(force: true);
    if (!AuthSession().isValid(generation)) return;

    var currentUser = container.read(currentUserProvider).value;
    if (currentUser?.username == expectedUsername) return;

    // finalizeNativeLoginSuccess 已经验证过目标会话；这里若第一次资料请求
    // 恰好撞上 preload/网络切换窗口，只重试资料刷新，不再走会清会话的
    // isLoggedIn() 路径，也不把 UI 降级成游客态。
    notifier = container.read(currentUserProvider.notifier);
    await notifier.refreshSilently(force: true);
    if (!AuthSession().isValid(generation)) return;
    currentUser = container.read(currentUserProvider).value;
    if (currentUser?.username != expectedUsername) {
      // 保留上一帧已登录身份。后续生命周期/手动刷新仍可继续自愈；比把
      // 已经通过服务端校验的会话错误呈现成“未登录”更安全。
      return;
    }
  }

  static void _refreshTopicTabs(ProviderContainer container) {
    final currentCategoryId = container.read(currentTabCategoryIdProvider);
    container.invalidate(topicListProvider(currentCategoryId));

    // 非当前 tab 标记 stale，不发请求
    final pinnedIds = container.read(pinnedCategoriesProvider);
    final staleTabs = <int?>{};
    for (final categoryId in [null, ...pinnedIds]) {
      if (categoryId == currentCategoryId) continue;
      staleTabs.add(categoryId);
    }
    container.read(staleTabsProvider.notifier).state = staleTabs;
  }

  /// 第一批：主页渲染必需的 provider
  /// currentUser 单独处理，便于账号切换时跳过第二次身份 invalidate。
  static final List<void Function(ProviderContainer container)>
  _coreRefreshers = [
    (c) => c.invalidate(categoriesProvider),
    (c) => c.invalidate(topicTrackingStateMetaProvider),
    (c) => c.invalidate(topicTrackingStateProvider),
  ];

  /// 第二批：非首屏必需，延迟执行以降低并发请求量
  static final List<void Function(ProviderContainer container)>
  _deferredRefreshers = [
    (c) => c.invalidate(userSummaryProvider),
    (c) => c.invalidate(notificationListProvider),
    (c) => c.invalidate(tagsProvider),
    (c) => c.invalidate(canTagTopicsProvider),
    (c) {
      final activeSlugs = c.read(activeCategorySlugsProvider);
      for (final slug in activeSlugs) {
        c.invalidate(categoryTopicsProvider(slug));
      }
    },
    (c) => c.invalidate(browsingHistoryProvider),
    (c) => c.invalidate(bookmarksProvider),
    (c) => c.invalidate(myTopicsProvider),
    (c) => c.invalidate(notificationCountStateProvider),
    (c) => c.invalidate(notificationChannelProvider),
    (c) => c.invalidate(notificationAlertChannelProvider),
    (c) => c.invalidate(latestChannelProvider),
    (c) => c.invalidate(messageBusInitProvider),
    (c) => c.invalidate(ldcUserInfoProvider),
    (c) => c.invalidate(cdkUserInfoProvider),
    // 多账号切换相关：私信收件箱/已发送、聊天频道列表都是按账号返回的
    (c) => c.invalidate(pmInboxProvider),
    (c) => c.invalidate(pmSentProvider),
    (c) => c.invalidate(chatChannelsProvider),
  ];
}
