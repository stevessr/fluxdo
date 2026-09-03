import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/topic.dart';
import '../providers/discourse_parity_providers.dart';
import '../widgets/common/error_view.dart';
import 'topic_detail_page/topic_detail_page.dart';

/// Topics created by members of a Discourse group.
///
/// Pagination stays server-backed through ListController#group_topics; this
/// never expands group members and joins their topics on the client.
class GroupTopicsTab extends ConsumerStatefulWidget {
  const GroupTopicsTab({super.key, required this.groupName});

  final String groupName;

  @override
  ConsumerState<GroupTopicsTab> createState() => _GroupTopicsTabState();
}

class _GroupTopicsTabState extends ConsumerState<GroupTopicsTab> {
  final ScrollController _scrollController = ScrollController();
  List<Topic> _topics = const [];
  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    Future.microtask(_refresh);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore || !_hasMore) return;
    if (_scrollController.position.extentAfter < 500) _loadMore();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await ref.read(
        groupTopicsProvider(
          GroupTopicsQuery(groupName: widget.groupName),
        ).future,
      );
      if (!mounted) return;
      setState(() {
        _topics = response.topics;
        _page = 0;
        _hasMore = response.moreTopicsUrl != null && response.topics.isNotEmpty;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final response = await ref.read(
        groupTopicsProvider(
          GroupTopicsQuery(groupName: widget.groupName, page: nextPage),
        ).future,
      );
      if (!mounted) return;
      final byId = <int, Topic>{for (final topic in _topics) topic.id: topic};
      for (final topic in response.topics) {
        byId[topic.id] = topic;
      }
      setState(() {
        _topics = byId.values.toList(growable: false);
        _page = nextPage;
        _hasMore =
            response.moreTopicsUrl != null && response.topics.isNotEmpty;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _openTopic(Topic topic) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TopicDetailPage(
          topicId: topic.id,
          initialTitle: topic.title,
          scrollToPostNumber: topic.lastReadPostNumber,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _topics.isEmpty) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_error != null && _topics.isEmpty) {
      return ErrorView(error: _error!, onRetry: _refresh);
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: _topics.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.55,
                  child: const Center(child: Text('No topics yet')),
                ),
              ],
            )
          : ListView.separated(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _topics.length + (_hasMore || _loadingMore ? 1 : 0),
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == _topics.length) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: _loadingMore
                          ? const CircularProgressIndicator.adaptive()
                          : FilledButton.tonal(
                              onPressed: _loadMore,
                              child: const Text('Load more'),
                            ),
                    ),
                  );
                }
                final topic = _topics[index];
                return ListTile(
                  title: Text(
                    topic.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: topic.postsCount > 0
                      ? Text('${topic.postsCount} posts')
                      : null,
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openTopic(topic),
                );
              },
            ),
    );
  }
}
