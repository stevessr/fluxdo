import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/discourse_providers.dart';
import '../utils/url_helper.dart';
import '../widgets/common/smart_avatar.dart';
import 'user_profile_page.dart';

/// Linux.do 社区点数排行榜。
///
/// 数据来自 discourse-gamification 的 `/leaderboard/1.json`。接口对高频请求
/// 较敏感，因此页面只在首次进入 / 用户主动刷新 / 用户主动加载更多时请求，
/// 并在页面生命周期内缓存各个周期的数据，不做后台轮询或自动翻页。
class LeaderboardPage extends ConsumerStatefulWidget {
  const LeaderboardPage({super.key, this.isActive = true});

  final bool isActive;

  @override
  ConsumerState<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends ConsumerState<LeaderboardPage> {
  static const int _serverPageSize = 100;

  final Map<_LeaderboardPeriod, _LeaderboardSnapshot> _cache = {};
  final Map<_LeaderboardPeriod, Object> _errors = {};

  _LeaderboardPeriod _period = _LeaderboardPeriod.allTime;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      scheduleMicrotask(_ensureLoaded);
    }
  }

  @override
  void didUpdateWidget(covariant LeaderboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      scheduleMicrotask(_ensureLoaded);
    }
  }

  Future<void> _ensureLoaded() async {
    if (!mounted || !widget.isActive || _cache.containsKey(_period)) return;
    await _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || !mounted) return;

    final requestedPeriod = _period;
    final previous = _cache[requestedPeriod];
    if (!reset && previous != null && !previous.hasMore) return;

    final page = reset ? 0 : (previous?.nextPage ?? 0);
    setState(() {
      _loading = true;
      _errors.remove(requestedPeriod);
    });

    try {
      final service = ref.read(discourseServiceProvider);
      final response = await service.dio.get(
        '/leaderboard/1.json',
        queryParameters: {
          'period': requestedPeriod.apiValue,
          'page': page,
        },
      );

      if (response.statusCode == 202) {
        throw const _LeaderboardNotReadyException();
      }

      final raw = response.data;
      if (raw is! Map) {
        throw const FormatException('Invalid leaderboard response');
      }
      final data = Map<String, dynamic>.from(raw);
      final rawUsers = data['users'] as List? ?? const [];
      final entries = rawUsers
          .whereType<Map>()
          .map((item) => _LeaderboardEntry.fromJson(Map<String, dynamic>.from(item)))
          .where((entry) => entry.username.isNotEmpty)
          .toList(growable: false);

      final merged = reset
          ? entries
          : _mergeEntries(previous?.entries ?? const [], entries);
      final snapshot = _LeaderboardSnapshot(
        entries: merged,
        nextPage: page + 1,
        hasMore: rawUsers.length >= _serverPageSize,
        updatedAt: DateTime.now(),
      );

      if (!mounted) return;
      setState(() {
        _cache[requestedPeriod] = snapshot;
        _errors.remove(requestedPeriod);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _errors[requestedPeriod] = error);
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);

      // 周期切换在请求进行时被禁用；这里仍做兜底，确保外部状态变化后
      // 当前周期不会停留在未加载状态。
      if (widget.isActive && !_cache.containsKey(_period) && !_errors.containsKey(_period)) {
        scheduleMicrotask(_ensureLoaded);
      }
    }
  }

  List<_LeaderboardEntry> _mergeEntries(
    List<_LeaderboardEntry> oldEntries,
    List<_LeaderboardEntry> newEntries,
  ) {
    final seen = <int>{};
    final merged = <_LeaderboardEntry>[];
    for (final entry in [...oldEntries, ...newEntries]) {
      final key = entry.id != 0 ? entry.id : entry.username.hashCode;
      if (seen.add(key)) merged.add(entry);
    }
    return merged;
  }

  void _selectPeriod(_LeaderboardPeriod period) {
    if (_loading || period == _period) return;
    setState(() => _period = period);
    scheduleMicrotask(_ensureLoaded);
  }

  void _openUser(_LeaderboardEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfilePage(username: entry.username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 自定义底栏会保活所有页面。隐藏时不订阅用户状态、不构建长列表，也不
    // 触发网络请求；切回来后复用本 State 中的周期缓存。
    if (!widget.isActive) return const SizedBox.shrink();

    final snapshot = _cache[_period];
    final error = _errors[_period];
    final currentUsername = ref.watch(currentUserProvider).value?.username;

    return Scaffold(
      appBar: AppBar(
        title: Text(_copy(context).title),
        actions: [
          IconButton(
            tooltip: _copy(context).refresh,
            onPressed: _loading ? null : () => _load(reset: true),
            icon: const Icon(Symbols.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _PeriodSelector(
            selected: _period,
            enabled: !_loading,
            onSelected: _selectPeriod,
          ),
          const Divider(height: 1),
          Expanded(
            child: _buildBody(
              context,
              snapshot: snapshot,
              error: error,
              currentUsername: currentUsername,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required _LeaderboardSnapshot? snapshot,
    required Object? error,
    required String? currentUsername,
  }) {
    if (snapshot == null && _loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (snapshot == null && error != null) {
      return _LeaderboardError(
        error: error,
        onRetry: _loading ? null : () => _load(reset: true),
      );
    }

    final entries = snapshot?.entries ?? const <_LeaderboardEntry>[];
    if (entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 160),
            Icon(
              Symbols.leaderboard_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Center(child: Text(_copy(context).empty)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
        itemCount: entries.length + 1,
        separatorBuilder: (_, index) => index < entries.length - 1
            ? const Divider(height: 1, indent: 72)
            : const SizedBox.shrink(),
        itemBuilder: (context, index) {
          if (index == entries.length) {
            return _LeaderboardFooter(
              snapshot: snapshot!,
              loading: _loading,
              error: error,
              onLoadMore: () => _load(reset: false),
            );
          }
          final entry = entries[index];
          return _LeaderboardTile(
            entry: entry,
            isCurrentUser:
                currentUsername != null && entry.username == currentUsername,
            onTap: () => _openUser(entry),
          );
        },
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final _LeaderboardPeriod selected;
  final bool enabled;
  final ValueChanged<_LeaderboardPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: _LeaderboardPeriod.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final period = _LeaderboardPeriod.values[index];
          return FilterChip(
            selected: selected == period,
            label: Text(period.label(context)),
            onSelected: enabled ? (_) => onSelected(period) : null,
            showCheckmark: false,
          );
        },
      ),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  const _LeaderboardTile({
    required this.entry,
    required this.isCurrentUser,
    required this.onTap,
  });

  final _LeaderboardEntry entry;
  final bool isCurrentUser;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final score = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    ).format(entry.totalScore);

    return Material(
      color: isCurrentUser
          ? colors.secondaryContainer.withValues(alpha: 0.45)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: SizedBox(
          width: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                width: 28,
                child: entry.position <= 3
                    ? Icon(
                        Symbols.emoji_events_rounded,
                        size: 22,
                        color: colors.primary,
                      )
                    : Text(
                        '#${entry.position}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
              ),
              SmartAvatar(
                imageUrl: entry.avatarUrl,
                radius: 18,
                fallbackText: entry.username,
              ),
            ],
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                entry.name?.isNotEmpty == true ? entry.name! : entry.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isCurrentUser) ...[
              const SizedBox(width: 6),
              Text(
                _copy(context).you,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.primary,
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '@${entry.username}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              score,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              _copy(context).points,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardFooter extends StatelessWidget {
  const _LeaderboardFooter({
    required this.snapshot,
    required this.loading,
    required this.error,
    required this.onLoadMore,
  });

  final _LeaderboardSnapshot snapshot;
  final bool loading;
  final Object? error;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: TextButton.icon(
            onPressed: onLoadMore,
            icon: const Icon(Symbols.refresh_rounded),
            label: Text(_copy(context).retryLoadMore),
          ),
        ),
      );
    }
    if (!snapshot.hasMore) {
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Center(
          child: Text(
            _copy(context).end,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: onLoadMore,
          icon: const Icon(Symbols.expand_more_rounded),
          label: Text(_copy(context).loadMore),
        ),
      ),
    );
  }
}

class _LeaderboardError extends StatelessWidget {
  const _LeaderboardError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final copy = _copy(context);
    final isRateLimited = error is DioException &&
        (error as DioException).response?.statusCode == 429;
    final isNotReady = error is _LeaderboardNotReadyException;
    final message = isRateLimited
        ? copy.rateLimited
        : isNotReady
        ? copy.notReady
        : copy.failed;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isRateLimited
                  ? Symbols.hourglass_top_rounded
                  : Symbols.error_outline_rounded,
              size: 44,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Symbols.refresh_rounded),
              label: Text(copy.retry),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardSnapshot {
  const _LeaderboardSnapshot({
    required this.entries,
    required this.nextPage,
    required this.hasMore,
    required this.updatedAt,
  });

  final List<_LeaderboardEntry> entries;
  final int nextPage;
  final bool hasMore;
  final DateTime updatedAt;
}

class _LeaderboardEntry {
  const _LeaderboardEntry({
    required this.id,
    required this.username,
    required this.name,
    required this.avatarTemplate,
    required this.totalScore,
    required this.position,
  });

  final int id;
  final String username;
  final String? name;
  final String? avatarTemplate;
  final int totalScore;
  final int position;

  factory _LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return _LeaderboardEntry(
      id: asInt(json['id'] ?? json['user_id']),
      username: json['username']?.toString() ?? '',
      name: json['name']?.toString(),
      avatarTemplate: json['avatar_template']?.toString(),
      totalScore: asInt(json['total_score']),
      position: asInt(json['position']),
    );
  }

  String get avatarUrl {
    final template = avatarTemplate;
    if (template == null || template.isEmpty) return '';
    return UrlHelper.resolveUrlWithCdn(template.replaceAll('{size}', '96'));
  }
}

class _LeaderboardNotReadyException implements Exception {
  const _LeaderboardNotReadyException();
}

enum _LeaderboardPeriod { allTime, daily, weekly, monthly, quarterly, yearly }

extension on _LeaderboardPeriod {
  String get apiValue {
    switch (this) {
      case _LeaderboardPeriod.allTime:
        return 'all_time';
      case _LeaderboardPeriod.daily:
        return 'daily';
      case _LeaderboardPeriod.weekly:
        return 'weekly';
      case _LeaderboardPeriod.monthly:
        return 'monthly';
      case _LeaderboardPeriod.quarterly:
        return 'quarterly';
      case _LeaderboardPeriod.yearly:
        return 'yearly';
    }
  }

  String label(BuildContext context) {
    final copy = _copy(context);
    switch (this) {
      case _LeaderboardPeriod.allTime:
        return copy.allTime;
      case _LeaderboardPeriod.daily:
        return copy.daily;
      case _LeaderboardPeriod.weekly:
        return copy.weekly;
      case _LeaderboardPeriod.monthly:
        return copy.monthly;
      case _LeaderboardPeriod.quarterly:
        return copy.quarterly;
      case _LeaderboardPeriod.yearly:
        return copy.yearly;
    }
  }
}

class _LeaderboardCopy {
  const _LeaderboardCopy({
    required this.title,
    required this.refresh,
    required this.empty,
    required this.points,
    required this.you,
    required this.loadMore,
    required this.retryLoadMore,
    required this.end,
    required this.failed,
    required this.rateLimited,
    required this.notReady,
    required this.retry,
    required this.allTime,
    required this.daily,
    required this.weekly,
    required this.monthly,
    required this.quarterly,
    required this.yearly,
  });

  final String title;
  final String refresh;
  final String empty;
  final String points;
  final String you;
  final String loadMore;
  final String retryLoadMore;
  final String end;
  final String failed;
  final String rateLimited;
  final String notReady;
  final String retry;
  final String allTime;
  final String daily;
  final String weekly;
  final String monthly;
  final String quarterly;
  final String yearly;
}

_LeaderboardCopy _copy(BuildContext context) {
  final locale = Localizations.localeOf(context);
  if (locale.languageCode != 'zh') {
    return const _LeaderboardCopy(
      title: 'Leaderboard',
      refresh: 'Refresh',
      empty: 'No leaderboard data',
      points: 'points',
      you: 'You',
      loadMore: 'Load more',
      retryLoadMore: 'Load more again',
      end: 'End of leaderboard',
      failed: 'Failed to load leaderboard',
      rateLimited: 'Too many leaderboard requests. Please try again later.',
      notReady: 'The leaderboard is being generated. Please refresh later.',
      retry: 'Retry',
      allTime: 'All time',
      daily: 'Daily',
      weekly: 'Weekly',
      monthly: 'Monthly',
      quarterly: 'Quarterly',
      yearly: 'Yearly',
    );
  }

  final traditional = locale.scriptCode == 'Hant' ||
      locale.countryCode == 'TW' ||
      locale.countryCode == 'HK';
  if (traditional) {
    return const _LeaderboardCopy(
      title: '排行榜',
      refresh: '重新整理',
      empty: '暫無排行榜資料',
      points: '點數',
      you: '你',
      loadMore: '載入更多',
      retryLoadMore: '重新載入更多',
      end: '已到排行榜末尾',
      failed: '排行榜載入失敗',
      rateLimited: '排行榜請求過於頻繁，請稍後再試。',
      notReady: '排行榜正在產生，請稍後重新整理。',
      retry: '重試',
      allTime: '總榜',
      daily: '日榜',
      weekly: '週榜',
      monthly: '月榜',
      quarterly: '季榜',
      yearly: '年榜',
    );
  }

  return const _LeaderboardCopy(
    title: '排行榜',
    refresh: '刷新',
    empty: '暂无排行榜数据',
    points: '点数',
    you: '你',
    loadMore: '加载更多',
    retryLoadMore: '重新加载更多',
    end: '已到排行榜末尾',
    failed: '排行榜加载失败',
    rateLimited: '排行榜请求过于频繁，请稍后再试。',
    notReady: '排行榜正在生成，请稍后刷新。',
    retry: '重试',
    allTime: '总榜',
    daily: '日榜',
    weekly: '周榜',
    monthly: '月榜',
    quarterly: '季榜',
    yearly: '年榜',
  );
}
