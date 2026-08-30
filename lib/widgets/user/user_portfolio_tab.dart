import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../../l10n/s.dart';
import '../../models/topic.dart';
import '../../providers/discourse_providers.dart';
import '../../providers/preferences_provider.dart';
import '../../utils/load_more_coordinator.dart';
import '../common/paged_list_footer.dart';
import '../topic/topic_item_builder.dart';
import '../topic/topic_list_skeleton.dart';

/// 用户主页的作品集标签页。
///
/// 作品集沿用标准话题列表展示；服务端只返回该用户创建且带有「作品集」标签的话题。
class UserPortfolioTab extends ConsumerStatefulWidget {
  final String username;
  final ValueChanged<Topic> onOpenTopic;

  const UserPortfolioTab({
    super.key,
    required this.username,
    required this.onOpenTopic,
  });

  @override
  ConsumerState<UserPortfolioTab> createState() => _UserPortfolioTabState();
}

class _UserPortfolioTabState extends ConsumerState<UserPortfolioTab> {
  List<Topic>? _topics;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadMoreFailed = false;
  int _page = 0;
  final LoadMoreCoordinator _loadMoreCoordinator = LoadMoreCoordinator();

  @override
  void initState() {
    super.initState();
    _loadPortfolio();
  }

  @override
  void didUpdateWidget(covariant UserPortfolioTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.username != widget.username) {
      _topics = null;
      _hasMore = true;
      _loading = false;
      _loadMoreFailed = false;
      _page = 0;
      _loadMoreCoordinator.resetCooldown();
      _loadPortfolio();
    }
  }

  Future<void> _loadMore() async {
    await _loadMoreCoordinator.loadMore(
      loadMore: () => _loadPortfolio(loadMore: true),
      hasMore: () => _hasMore,
      isActive: () => mounted,
      progressCount: () => _topics?.length ?? 0,
    );
  }

  Future<void> _loadPortfolio({bool loadMore = false}) async {
    if (_loading && _topics != null) return;
    if (!loadMore) _loadMoreCoordinator.resetCooldown();

    if (mounted) {
      setState(() {
        _loading = true;
        _loadMoreFailed = false;
      });
    }

    try {
      final service = ref.read(discourseServiceProvider);
      final page = loadMore ? _page + 1 : 0;
      final response = await service.getUserPortfolioTopics(
        widget.username,
        page: page,
      );
      if (!mounted) return;

      setState(() {
        if (loadMore) {
          final existingIds = (_topics ?? []).map((topic) => topic.id).toSet();
          final freshTopics = response.topics.where(
            (topic) => !existingIds.contains(topic.id),
          );
          _topics = [...?_topics, ...freshTopics];
        } else {
          _topics = response.topics;
        }
        _page = page;
        _hasMore = response.moreTopicsUrl != null;
        _loading = false;
        _loadMoreFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (loadMore) {
          _loadMoreFailed = true;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _topics == null) {
      return const TopicListSkeleton();
    }

    final topics = _topics ?? const <Topic>[];
    final enableLongPress = ref.watch(
      preferencesProvider.select((p) => p.longPressPreview),
    );

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical) {
          final distance =
              notification.metrics.maxScrollExtent - notification.metrics.pixels;
          if (_loadMoreCoordinator.shouldTriggerForDistance(distance)) {
            _loadMore();
          }
        }
        return false;
      },
      child: M3eRefreshIndicator(
        onRefresh: () => _loadPortfolio(),
        child: topics.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.42,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.collections_outlined,
                            size: 64,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            context.l10n.userProfile_noPortfolio,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: topics.length + 1,
                itemBuilder: (context, index) {
                  if (index == topics.length) {
                    return PagedListFooter(
                      hasMore: _hasMore,
                      isLoadingMore:
                          _loadMoreCoordinator.isRunning && _loading,
                      isLoadMoreFailed: _loadMoreFailed,
                      onRetry: _loadMore,
                    );
                  }

                  final topic = topics[index];
                  return buildTopicItem(
                    context: context,
                    topic: topic,
                    isSelected: false,
                    onTap: () => widget.onOpenTopic(topic),
                    enableLongPress: enableLongPress,
                  );
                },
              ),
      ),
    );
  }
}
