import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/topic.dart';
import '../providers/discourse_parity_providers.dart';
import '../widgets/common/error_view.dart';
import 'topic_detail_page/topic_detail_page.dart';

enum PmSpecialMailboxKind { warnings, tag }

class PmSpecialMailboxPage extends ConsumerStatefulWidget {
  const PmSpecialMailboxPage.warnings({super.key})
      : kind = PmSpecialMailboxKind.warnings,
        tagName = null;

  const PmSpecialMailboxPage.tag({super.key, required this.tagName})
      : kind = PmSpecialMailboxKind.tag;

  final PmSpecialMailboxKind kind;
  final String? tagName;

  @override
  ConsumerState<PmSpecialMailboxPage> createState() =>
      _PmSpecialMailboxPageState();
}

class _PmSpecialMailboxPageState
    extends ConsumerState<PmSpecialMailboxPage> {
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

  Future<TopicListResponse> _fetch(int page) {
    return switch (widget.kind) {
      PmSpecialMailboxKind.warnings => ref.read(
          parityPmPageProvider(
            ParityPmPageQuery(ParityPmMailbox.warnings, page: page),
          ).future,
        ),
      PmSpecialMailboxKind.tag => ref.read(
          pmTagPageProvider(
            PmTagQuery(tagName: widget.tagName!, page: page),
          ).future,
        ),
    };
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _fetch(0);
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
      final response = await _fetch(nextPage);
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

  String _title(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return switch (widget.kind) {
      PmSpecialMailboxKind.warnings => zh ? '警告私信' : 'Warnings',
      PmSpecialMailboxKind.tag => '#${widget.tagName}',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title(context))),
      body: _loading && _topics.isEmpty
          ? const Center(child: CircularProgressIndicator.adaptive())
          : _error != null && _topics.isEmpty
              ? ErrorView(error: _error!, onRetry: _refresh)
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount:
                        _topics.length + (_hasMore || _loadingMore ? 1 : 0),
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
                                    child: Text(
                                      Localizations.localeOf(context)
                                                  .languageCode ==
                                              'zh'
                                          ? '加载更多'
                                          : 'Load more',
                                    ),
                                  ),
                          ),
                        );
                      }
                      final topic = _topics[index];
                      return ListTile(
                        leading: const Icon(Icons.mail_outline_rounded),
                        title: Text(
                          topic.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _openTopic(topic),
                      );
                    },
                  ),
                ),
    );
  }
}

/// Extra PM destinations. Warning visibility is based on a successful server
/// response rather than hard-coded staff/admin status.
class PmParityMenuButton extends ConsumerWidget {
  const PmParityMenuButton({super.key});

  Future<void> _openTag(BuildContext context) async {
    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          Localizations.localeOf(context).languageCode == 'zh'
              ? '私信标签'
              : 'PM tag',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: Localizations.localeOf(context).languageCode == 'zh'
                ? '标签名称'
                : 'Tag name',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!context.mounted || tag == null || tag.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PmSpecialMailboxPage.tag(tagName: tag)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warnings = ref.watch(pmWarningsAvailableProvider).valueOrNull == true;
    if (!warnings) {
      return IconButton(
        tooltip: Localizations.localeOf(context).languageCode == 'zh'
            ? '私信标签'
            : 'PM tags',
        onPressed: () => _openTag(context),
        icon: const Icon(Icons.label_outline_rounded),
      );
    }
    return PopupMenuButton<String>(
      tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
      onSelected: (value) {
        if (value == 'warnings') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const PmSpecialMailboxPage.warnings(),
            ),
          );
        } else if (value == 'tag') {
          _openTag(context);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'warnings',
          child: Text(
            Localizations.localeOf(context).languageCode == 'zh'
                ? '警告私信'
                : 'Warnings',
          ),
        ),
        PopupMenuItem(
          value: 'tag',
          child: Text(
            Localizations.localeOf(context).languageCode == 'zh'
                ? '私信标签…'
                : 'PM tag…',
          ),
        ),
      ],
    );
  }
}
