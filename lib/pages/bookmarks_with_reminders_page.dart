import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/topic.dart';
import '../pages/bookmarks/bookmarks_models.dart';
import '../providers/discourse_parity_providers.dart';
import '../providers/user_content_providers.dart';
import '../utils/link_launcher.dart';
import '../utils/time_utils.dart';
import 'topic_detail_page/topic_detail_page.dart';

/// Server-backed bookmark data, filtered to entries carrying reminder metadata.
class BookmarksWithRemindersPage extends ConsumerStatefulWidget {
  const BookmarksWithRemindersPage({super.key});

  @override
  ConsumerState<BookmarksWithRemindersPage> createState() =>
      _BookmarksWithRemindersPageState();
}

class _BookmarksWithRemindersPageState
    extends ConsumerState<BookmarksWithRemindersPage> {
  bool _hydratingAll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_hydrateAllCachedBookmarks());
    });
  }

  Future<void> _hydrateAllCachedBookmarks() async {
    if (_hydratingAll) return;
    _hydratingAll = true;
    if (mounted) setState(() {});
    try {
      final notifier = ref.read(bookmarksProvider.notifier);
      while (mounted && notifier.hasMore) {
        final before = ref.read(bookmarksProvider).value?.length ?? 0;
        await notifier.loadMore();
        final after = ref.read(bookmarksProvider).value?.length ?? 0;
        if (after <= before) break;
      }
    } finally {
      _hydratingAll = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _refresh() async {
    await ref.read(bookmarksProvider.notifier).refresh();
    await _hydrateAllCachedBookmarks();
  }

  void _openBookmark(Topic topic) {
    if (topic.isChatMessageBookmark) {
      final url = topic.bookmarkableUrl;
      if (url != null && url.isNotEmpty) launchContentLink(context, url);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TopicDetailPage(
          topicId: topic.id,
          initialTitle: topic.title,
          scrollToPostNumber: resolveBookmarkScrollToPostNumber(topic),
          initialBookmarkId: topic.bookmarkId,
          initialBookmarkName: topic.bookmarkName,
          initialBookmarkReminderAt: topic.bookmarkReminderAt,
          initialBookmarkableType: topic.bookmarkableType,
        ),
      ),
    );
  }

  String _label(BuildContext context, String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  Widget build(BuildContext context) {
    final remindersAsync = ref.watch(bookmarksWithRemindersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_label(context, '带提醒的书签', 'Bookmarks with reminders'))),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: remindersAsync.when(
          data: (topics) {
            if (topics.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.55,
                    child: Center(
                      child: _hydratingAll
                          ? const CircularProgressIndicator.adaptive()
                          : Text(_label(context, '当前没有设置提醒的书签', 'No bookmarks with reminders')),
                    ),
                  ),
                ],
              );
            }
            final sorted = [...topics]
              ..sort((a, b) => a.bookmarkReminderAt!.compareTo(b.bookmarkReminderAt!));
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: sorted.length + (_hydratingAll ? 1 : 0),
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == sorted.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  );
                }
                final topic = sorted[index];
                final reminderAt = topic.bookmarkReminderAt!;
                return ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: Text(topic.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(TimeUtils.formatDetailTime(reminderAt)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openBookmark(topic),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator.adaptive()),
          error: (error, stack) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: 320,
                child: Center(child: Text(error.toString(), textAlign: TextAlign.center)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
