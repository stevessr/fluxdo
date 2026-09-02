import 'dart:collection';

import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/topic.dart';
import '../providers/discourse_parity_providers.dart';
import '../providers/preferences_provider.dart';
import '../widgets/common/error_view.dart';
import '../widgets/topic/topic_card_prewarmer.dart';
import '../widgets/topic/topic_item_builder.dart';
import '../widgets/topic/topic_list_skeleton.dart';
import 'topic_detail_page/topic_detail_page.dart';

enum _GroupPmMailbox { inbox, unread, newMessages, archive }

/// Native Discourse group PM view (`/g/:name/messages/...`).
///
/// Each mailbox owns its pagination state because Discourse exposes separate
/// topic-list routes for inbox/unread/new/archive. The server remains the
/// permission boundary; callers only expose this page for current group members.
class GroupMessagesPage extends StatefulWidget {
  const GroupMessagesPage({
    super.key,
    required this.groupName,
    this.groupLabel,
  });

  final String groupName;
  final String? groupLabel;

  @override
  State<GroupMessagesPage> createState() => _GroupMessagesPageState();
}

class _GroupMessagesPageState extends State<GroupMessagesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _mailboxes = [
    _GroupPmMailbox.inbox,
    _GroupPmMailbox.unread,
    _GroupPmMailbox.newMessages,
    _GroupPmMailbox.archive,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _mailboxes.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupLabel ?? widget.groupName),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: copy.inbox),
            Tab(text: copy.unread),
            Tab(text: copy.newMessages),
            Tab(text: copy.archive),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          for (final mailbox in _mailboxes)
            _GroupMessageList(
              groupName: widget.groupName,
              mailbox: mailbox,
            ),
        ],
      ),
    );
  }
}

class _GroupMessageList extends ConsumerStatefulWidget {
  const _GroupMessageList({
    required this.groupName,
    required this.mailbox,
  });

  final String groupName;
  final _GroupPmMailbox mailbox;

  @override
  ConsumerState<_GroupMessageList> createState() => _GroupMessageListState();
}

class _GroupMessageListState extends ConsumerState<_GroupMessageList>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  List<Topic>? _topics;
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadingMore = false;
  Object? _error;
  StackTrace? _errorStack;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    Future.microtask(_refresh);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  GroupPrivateMessageQuery _query(int page) => GroupPrivateMessageQuery(
        groupName: widget.groupName,
        page: page,
        unreadOnly: widget.mailbox == _GroupPmMailbox.unread,
        newOnly: widget.mailbox == _GroupPmMailbox.newMessages,
        archived: widget.mailbox == _GroupPmMailbox.archive,
      );

  Future<TopicListResponse> _fetch(int page) {
    return ref.read(groupPrivateMessagesProvider(_query(page)).future);
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _errorStack = null;
    });
    try {
      final response = await _fetch(0);
      if (!mounted) return;
      setState(() {
        _topics = response.topics;
        _page = 0;
        _hasMore = response.moreTopicsUrl?.isNotEmpty == true;
      });
    } catch (error, stack) {
      if (mounted) {
        setState(() {
          _error = error;
          _errorStack = stack;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _loadingMore ||
        !_hasMore ||
        _loading) {
      return;
    }
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels < 500) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final response = await _fetch(nextPage);
      if (!mounted) return;
      final byId = LinkedHashMap<int, Topic>();
      for (final topic in [...?_topics, ...response.topics]) {
        byId[topic.id] = topic;
      }
      setState(() {
        _topics = byId.values.toList(growable: false);
        _page = nextPage;
        _hasMore = response.moreTopicsUrl?.isNotEmpty == true;
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
    super.build(context);
    final copy = _copy(context);
    final topics = _topics;

    if (topics == null && _loading) {
      return const TopicListSkeleton(messageStyle: true);
    }
    if (topics == null && _error != null) {
      return ErrorView(
        error: _error!,
        stackTrace: _errorStack,
        onRetry: _refresh,
      );
    }

    final data = topics ?? const <Topic>[];
    return RefreshIndicator(
      onRefresh: _refresh,
      child: data.isEmpty
          ? ListView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.55,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Symbols.mail_rounded, size: 52),
                        const SizedBox(height: 12),
                        Text(copy.empty),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : TopicCardPrewarmScope(
              topics: data,
              messageStyle: true,
              child: ListView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: data.length + 1,
                itemBuilder: (context, index) {
                  if (index == data.length) {
                    if (_loadingMore) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      );
                    }
                    if (_hasMore) {
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Center(
                          child: FilledButton.tonal(
                            onPressed: _loadMore,
                            child: Text(copy.loadMore),
                          ),
                        ),
                      );
                    }
                    return const SizedBox(height: 12);
                  }

                  final topic = data[index];
                  return buildTopicItem(
                    context: context,
                    topic: topic,
                    onTap: () => _openTopic(topic),
                    enableLongPress:
                        ref.watch(preferencesProvider).longPressPreview,
                    messageStyle: true,
                  );
                },
              ),
            ),
    );
  }
}

class _GroupMessagesCopy {
  const _GroupMessagesCopy(this.zh);
  final bool zh;

  String get inbox => zh ? '收件箱' : 'Inbox';
  String get unread => zh ? '未读' : 'Unread';
  String get newMessages => zh ? '新消息' : 'New';
  String get archive => zh ? '归档' : 'Archive';
  String get empty => zh ? '暂无群组私信' : 'No group messages';
  String get loadMore => zh ? '加载更多' : 'Load more';
}

_GroupMessagesCopy _copy(BuildContext context) => _GroupMessagesCopy(
      Localizations.localeOf(context).languageCode.toLowerCase() == 'zh',
    );
