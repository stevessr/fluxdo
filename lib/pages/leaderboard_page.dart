import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/discourse_providers.dart';
import '../utils/leaderboard_period_range.dart';
import '../utils/time_utils.dart';
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

  final Map<LeaderboardPeriod, _LeaderboardSnapshot> _cache = {};
  final Map<LeaderboardPeriod, Object> _errors = {};

  LeaderboardPeriod _period = LeaderboardPeriod.allTime;
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
    if (!mounted || !widget.isActive) return;
    final viewer = ref.read(currentUserProvider).value?.username;
    final saved = _cache[_period];
    if (saved != null && saved.viewerUsername == viewer) return;
    await _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || !mounted) return;

    final requestedPeriod = _period;
    final previous = _cache[requestedPeriod];
    final viewer = ref.read(currentUserProvider).value?.username;
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
        queryParameters: {'period': requestedPeriod.apiValue, 'page': page},
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
          .map(
            (item) =>
                _LeaderboardEntry.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((entry) => entry.username.isNotEmpty)
          .toList(growable: false);

      final merged = reset
          ? entries
          : _mergeEntries(previous?.entries ?? const [], entries);

      // 个人名次由官方 personal 字段独立返回，不依赖已加载的榜单页数。
      // 翻页响应不覆盖首页的个人信息，账号切换时也不能展示旧账号的缓存。
      final rawPersonal = data['personal'];
      final personal = reset
          ? rawPersonal is Map
              ? _LeaderboardPersonal.fromJson(
                  Map<String, dynamic>.from(rawPersonal),
                )
              : null
          : previous?.personal;

      final rawLeaderboard = data['leaderboard'];
      final leaderboard = rawLeaderboard is Map
          ? Map<String, dynamic>.from(rawLeaderboard)
          : const <String, dynamic>{};
      final snapshot = _LeaderboardSnapshot(
        entries: merged,
        personal: personal,
        viewerUsername: viewer,
        fromDate: _leaderboardDate(leaderboard['from_date']) ?? previous?.fromDate,
        toDate: _leaderboardDate(leaderboard['to_date']) ?? previous?.toDate,
        periodFilterDisabled:
            leaderboard['period_filter_disabled'] == true ||
            (previous?.periodFilterDisabled ?? false),
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
      if (widget.isActive &&
          _errors[_period] == null &&
          _cache[_period]?.viewerUsername !=
              ref.read(currentUserProvider).value?.username) {
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

  void _selectPeriod(LeaderboardPeriod period) {
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
    if (!_loading && snapshot != null && snapshot.viewerUsername != currentUsername) {
      scheduleMicrotask(_ensureLoaded);
    }

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
            enabled: !_loading && !(snapshot?.periodFilterDisabled ?? false),
            fromDate: snapshot?.fromDate,
            toDate: snapshot?.toDate,
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

    // 和官方一致：前三名在领奖台展示，个人名次独立显示，普通榜单从第 4 名开始。
    final rankings = entries.skip(3).toList(growable: false);
    final personal = snapshot!.viewerUsername == currentUsername
        ? snapshot.personal
        : null;
    final showPersonal = currentUsername != null && personal != null;
    final listStart = showPersonal ? 3 : 2;

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
        itemCount: rankings.length + listStart + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _LeaderboardPodium(
              winners: entries.take(3).toList(growable: false),
              onOpenUser: _openUser,
            );
          }
          if (showPersonal && index == 1) {
            return _LeaderboardSelfRank(
              personal: personal!,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserProfilePage(username: currentUsername!),
                ),
              ),
            );
          }
          if (index == listStart - 1) {
            return _LeaderboardListHeading();
          }
          final entryIndex = index - listStart;
          if (entryIndex >= rankings.length) {
            return _LeaderboardFooter(
              snapshot: snapshot!,
              loading: _loading,
              error: error,
              onLoadMore: () => _load(reset: false),
            );
          }
          final entry = rankings[entryIndex];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LeaderboardTile(
                entry: entry,
                isCurrentUser: currentUsername != null &&
                    entry.username.toLowerCase() ==
                        currentUsername.toLowerCase(),
                onTap: () => _openUser(entry),
              ),
              if (entryIndex < rankings.length - 1)
                const Divider(height: 1, indent: 64),
            ],
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
    required this.fromDate,
    required this.toDate,
    required this.onSelected,
  });

  final LeaderboardPeriod selected;
  final bool enabled;
  final DateTime? fromDate;
  final DateTime? toDate;
  final ValueChanged<LeaderboardPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final range = _formatLeaderboardRange(context, selected, fromDate, toDate);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: PopupMenuButton<LeaderboardPeriod>(
          enabled: enabled,
          tooltip: _periodLabel(context, selected),
          initialValue: selected,
          position: PopupMenuPosition.under,
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 400),
          onSelected: onSelected,
          itemBuilder: (menuContext) => LeaderboardPeriod.values.map((period) {
            final description =
                _formatLeaderboardRange(menuContext, period, fromDate, toDate);
            return PopupMenuItem<LeaderboardPeriod>(
              value: period,
              height: 62,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _periodLabel(menuContext, period),
                          style: Theme.of(menuContext).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: period == selected
                                    ? FontWeight.bold
                                    : null,
                              ),
                        ),
                        if (description.isNotEmpty)
                          Text(
                            description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(menuContext).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(menuContext)
                                      .colorScheme.onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                  ),
                  if (period == selected)
                    Icon(Symbols.check_rounded, color: scheme.primary, size: 20),
                ],
              ),
            );
          }).toList(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _periodLabel(context, selected),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Symbols.expand_more_rounded,
                color: enabled ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
              if (range.isNotEmpty) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    range,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _periodLabel(BuildContext context, LeaderboardPeriod period) {
  final locale = Localizations.localeOf(context);
  final zh = locale.languageCode == 'zh';
  final hant = locale.scriptCode == 'Hant' ||
      locale.countryCode == 'TW' || locale.countryCode == 'HK';
  return switch (period) {
    LeaderboardPeriod.allTime =>
      zh ? (hant ? '所有時間' : '所有时间') : 'All time',
    LeaderboardPeriod.yearly => zh ? '年' : 'Year',
    LeaderboardPeriod.quarterly => zh ? '季度' : 'Quarter',
    LeaderboardPeriod.monthly => zh ? '月' : 'Month',
    LeaderboardPeriod.weekly => zh ? '周' : 'Week',
    LeaderboardPeriod.daily => zh ? '今天' : 'Today',
  };
}

String _formatLeaderboardRange(
  BuildContext context,
  LeaderboardPeriod period,
  DateTime? fromDate,
  DateTime? toDate,
) {
  final range = LeaderboardDateRange.forPeriod(
    period,
    fromDate: fromDate,
    toDate: toDate,
  );
  final start = range.start;
  final end = range.end;
  if (start == null && end == null) return '';
  final locale = Localizations.localeOf(context);
  final useYear = start == null || end == null || start.year != end.year;
  String formatDate(DateTime value) {
    if (locale.languageCode == 'zh') {
      return useYear
          ? '${value.year}年${value.month}月${value.day}日'
          : '${value.month}月${value.day}日';
    }
    return DateFormat(useYear ? 'MMM d, y' : 'MMM d', locale.toString())
        .format(value);
  }

  if (start == null) return formatDate(end!);
  if (end == null || start == end) return formatDate(start);
  return '${formatDate(start)} – ${formatDate(end)}';
}

/// 官方领奖台顺序为第二名、第一名、第三名，普通榜单不重复前三名。
class _LeaderboardPodium extends StatelessWidget {
  const _LeaderboardPodium({
    required this.winners,
    required this.onOpenUser,
  });

  final List<_LeaderboardEntry> winners;
  final ValueChanged<_LeaderboardEntry> onOpenUser;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = winners.isNotEmpty ? winners[0] : null;
    final second = winners.length > 1 ? winners[1] : null;
    final third = winners.length > 2 ? winners[2] : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 22, 12, 24),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: second == null
                ? const SizedBox.shrink()
                : _LeaderboardWinner(
                    entry: second,
                    rank: second.position,
                    onTap: () => onOpenUser(second),
                  ),
          ),
          Expanded(
            child: first == null
                ? const SizedBox.shrink()
                : _LeaderboardWinner(
                    entry: first,
                    rank: first.position,
                    onTap: () => onOpenUser(first),
                  ),
          ),
          Expanded(
            child: third == null
                ? const SizedBox.shrink()
                : _LeaderboardWinner(
                    entry: third,
                    rank: third.position,
                    onTap: () => onOpenUser(third),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardWinner extends StatelessWidget {
  const _LeaderboardWinner({
    required this.entry,
    required this.rank,
    required this.onTap,
  });

  final _LeaderboardEntry entry;
  final int rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = rank == 1;
    final medal = switch (rank) {
      1 => const Color(0xFFFFD32A),
      2 => const Color(0xFFC8C9CD),
      _ => const Color(0xFFCA8643),
    };
    final avatarRadius = first ? 42.0 : 34.0;
    final squareAvatar = isSquareAvatarUrl(entry.avatarUrl);
    final score = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    ).format(entry.totalScore);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: EdgeInsets.fromLTRB(2, first ? 0 : 24, 2, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (first)
              Icon(
                Icons.workspace_premium_rounded,
                color: medal,
                size: 28,
              ),
            Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: medal, width: 2),
                      shape: squareAvatar ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius: squareAvatar
                          ? BorderRadius.circular(12)
                          : null,
                    ),
                    child: SmartAvatar(
                      imageUrl: entry.avatarUrl,
                      radius: avatarRadius,
                      fallbackText: entry.username,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: medal,
                    child: Text(
                      '$rank',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF202020),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: Center(
                child: Text(
                  entry.name?.isNotEmpty == true
                      ? entry.name!
                      : entry.username,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                score,
                maxLines: 1,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 使用官方 personal 返回的名次，分页与当前用户是否在前百名无关。
class _LeaderboardSelfRank extends StatelessWidget {
  const _LeaderboardSelfRank({
    required this.personal,
    required this.onTap,
  });

  final _LeaderboardPersonal personal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context);
    final score = NumberFormat.decimalPattern(locale.toString())
        .format(personal.totalScore);
    final compactScore = NumberFormat.compact(locale: 'en')
        .format(personal.totalScore).toLowerCase();

    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 20),
      child: Material(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    '${personal.position}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    _copy(context).you,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Tooltip(
                  message: score,
                  child: Text(
                    compactScore,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LeaderboardListHeading extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context);
    final rank = locale.languageCode == 'zh' ? '排名' : 'Rank';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Row(
        children: [
          Text(
            rank,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Icon(
            Icons.workspace_premium_rounded,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            _copy(context).points,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
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
    final isRateLimited =
        error is DioException &&
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
    required this.personal,
    required this.viewerUsername,
    required this.fromDate,
    required this.toDate,
    required this.periodFilterDisabled,
    required this.nextPage,
    required this.hasMore,
    required this.updatedAt,
  });

  final List<_LeaderboardEntry> entries;
  final _LeaderboardPersonal? personal;
  final String? viewerUsername;
  final DateTime? fromDate;
  final DateTime? toDate;
  final bool periodFilterDisabled;
  final int nextPage;
  final bool hasMore;
  final DateTime updatedAt;
}

class _LeaderboardPersonal {
  const _LeaderboardPersonal({required this.position, required this.totalScore});

  final int position;
  final int totalScore;

  static _LeaderboardPersonal? fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    if (user is! Map) return null;
    final position = int.tryParse('${json['position'] ?? user['position'] ?? ''}');
    final score = int.tryParse('${user['total_score'] ?? ''}');
    if (position == null || position < 1 || score == null) return null;
    return _LeaderboardPersonal(position: position, totalScore: score);
  }
}

/// Date 类型的 API 值先交由项目统一时间解析器转换，再取回 UTC 日期。
DateTime? _leaderboardDate(dynamic raw) {
  final text = raw?.toString();
  if (text == null || text.isEmpty) return null;
  // 纯日期必须明确标记 UTC，否则解析器在非 UTC 时区可能错开一天。
  final normalized = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)
      ? '${text}T00:00:00Z'
      : text;
  final parsed = TimeUtils.parseUtcTime(normalized);
  if (parsed == null) return null;
  final utc = parsed.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
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

  final traditional =
      locale.scriptCode == 'Hant' ||
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
).hasMatch(text)
      ? '${text}T00:00:00Z'
      : text;
  final parsed = TimeUtils.parseUtcTime(normalized);
  if (parsed == null) return null;
  final utc = parsed.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
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

  final traditional =
      locale.scriptCode == 'Hant' ||
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
