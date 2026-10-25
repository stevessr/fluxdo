import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/discourse_providers.dart';
import '../utils/url_helper.dart';
import '../utils/leaderboard_period_range.dart';
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
  int _accountVersion = 0;
  String? _cachedAccountUsername;

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
    // 非激活页面不会订阅 provider；再次显示时也必须核对账号身份。
    final username = ref.read(currentUserProvider).value?.username;
    if (_cachedAccountUsername != username) {
      _cachedAccountUsername = username;
      _accountVersion++;
      _cache.clear();
      _errors.clear();
    }
    if (_cache.containsKey(_period)) return;
    await _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || !mounted) return;

    final requestedPeriod = _period;
    final accountVersion = _accountVersion;
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

      // 官方 personal 字段由同一个响应返回，包含当前用户的全榜位置。
      // 不依赖前 100 名，也不需要额外查询或翻页。
      final personalJson = data['personal'];
      _LeaderboardEntry? personal;
      if (personalJson is Map && personalJson['user'] is Map) {
        final user = _LeaderboardEntry.fromJson(
          Map<String, dynamic>.from(personalJson['user'] as Map),
        );
        final rank = _LeaderboardEntry.asInt(personalJson['position']);
        if (user.username.isNotEmpty && rank > 0) {
          personal = user.withPosition(rank);
        }
      }
      final leaderboardJson = data['leaderboard'];
      final leaderboard = leaderboardJson is Map
          ? Map<String, dynamic>.from(leaderboardJson)
          : const <String, dynamic>{};
      final name = leaderboard['name']?.toString();

      final merged = reset
          ? entries
          : _mergeEntries(previous?.entries ?? const [], entries);
      final snapshot = _LeaderboardSnapshot(
        entries: merged,
        personal: reset ? personal : personal ?? previous?.personal,
        name: name?.isNotEmpty == true ? name : previous?.name,
        periodFilterDisabled:
            leaderboard['period_filter_disabled'] == true ||
            (!reset && (previous?.periodFilterDisabled ?? false)),
        nextPage: page + 1,
        hasMore: rawUsers.length >= _serverPageSize,
        updatedAt: DateTime.now(),
      );

      if (!mounted || accountVersion != _accountVersion) return;
      setState(() {
        _cache[requestedPeriod] = snapshot;
        _errors.remove(requestedPeriod);
      });
    } catch (error) {
      if (!mounted || accountVersion != _accountVersion) return;
      setState(() => _errors[requestedPeriod] = error);
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);

      // 周期切换在请求进行时被禁用；这里仍做兜底，确保外部状态变化后
      // 当前周期不会停留在未加载状态。
      if (widget.isActive &&
          !_cache.containsKey(_period) &&
          !_errors.containsKey(_period)) {
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

    // 切换账号后丢弃含有旧 personal 字段的快照；请求跨账号返回时
    // 由 _accountVersion 拒绝写入，避免展示前一账号的私有排名。
    ref.listen(currentUserProvider, (previous, next) {
      final username = next.value?.username;
      if (_cachedAccountUsername == username) return;
      _cachedAccountUsername = username;
      _accountVersion++;
      setState(() {
        _cache.clear();
        _errors.clear();
      });
      if (!_loading) scheduleMicrotask(_ensureLoaded);
    });

    final snapshot = _cache[_period];
    final error = _errors[_period];
    final currentUsername = ref.watch(currentUserProvider).value?.username;
    final colors = Theme.of(context).colorScheme;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    snapshot?.name ?? _copy(context).globalTitle,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _copy(context).about,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: Text(_copy(context).globalTitle),
                      content: Text(_copy(context).aboutBody),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: Text(MaterialLocalizations.of(context).closeButtonTooltip),
                        ),
                      ],
                    ),
                  ),
                  icon: Icon(AppIcons.info, color: colors.primary),
                ),
              ],
            ),
          ),
          _PeriodSelector(
            selected: _period,
            enabled: !_loading && snapshot?.periodFilterDisabled != true,
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

    // 领奖台 + 当前用户卡片 + 第四名起的常规列表。
    final visiblePersonal = snapshot?.personal;
    final showPersonal = currentUsername != null &&
        visiblePersonal != null &&
        visiblePersonal.username.toLowerCase() == currentUsername.toLowerCase();
    final ranked = entries.skip(3).toList(growable: false);
    final initialRows = 2 + (showPersonal ? 1 : 0);

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: initialRows + ranked.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _LeaderboardPodium(
              winners: entries.take(3).toList(growable: false),
              onTap: _openUser,
            );
          }
          if (index == 1) {
            return _LeaderboardRankingHeading(copy: _copy(context));
          }
          if (showPersonal && index == 2) {
            return _PersonalLeaderboardRank(
              entry: visiblePersonal!,
              onTap: () => _openUser(visiblePersonal!),
            );
          }
          final rankIndex = index - initialRows;
          if (rankIndex < ranked.length) {
            final entry = ranked[rankIndex];
            return Column(
              children: [
                _LeaderboardTile(
                  entry: entry,
                  isCurrentUser: currentUsername != null &&
                      entry.username.toLowerCase() == currentUsername.toLowerCase(),
                  onTap: () => _openUser(entry),
                ),
                const Divider(height: 1, indent: 60),
              ],
            );
          }
          return _LeaderboardFooter(
            snapshot: snapshot!,
            loading: _loading,
            error: error,
            onLoadMore: () => _load(reset: false),
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

  static const _periods = [
    _LeaderboardPeriod.allTime,
    _LeaderboardPeriod.yearly,
    _LeaderboardPeriod.quarterly,
    _LeaderboardPeriod.monthly,
    _LeaderboardPeriod.weekly,
    _LeaderboardPeriod.daily,
  ];

  final _LeaderboardPeriod selected;
  final bool enabled;
  final ValueChanged<_LeaderboardPeriod> onSelected;

  String _span(BuildContext context, _LeaderboardPeriod period) {
    final range = leaderboardPeriodRange(period.apiValue, DateTime.now());
    if (range == null) return '';
    final locale = Localizations.localeOf(context);
    final isChinese = locale.languageCode == 'zh';
    String format(DateTime date, {required bool withYear}) {
      if (isChinese) {
        return withYear
            ? DateFormat('yyyy年M月d日').format(date)
            : DateFormat('M月d日').format(date);
      }
      return withYear
          ? DateFormat.yMMMd(locale.toString()).format(date)
          : DateFormat.MMMd(locale.toString()).format(date);
    }

    final sameYear = range.start.year == range.end.year;
    final isSingleDay = range.start == range.end;
    final withYear = !sameYear;
    final first = format(range.start, withYear: withYear);
    if (isSingleDay) return first;
    return '$first – ' + format(range.end, withYear: withYear);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final span = _span(context, selected);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PopupMenuButton<_LeaderboardPeriod>(
            initialValue: selected,
            enabled: enabled,
            position: PopupMenuPosition.under,
            tooltip: selected.label(context),
            constraints: BoxConstraints(
              minWidth: 220,
              maxWidth: MediaQuery.sizeOf(context).width - 32,
            ),
            onSelected: onSelected,
            itemBuilder: (popupContext) => _periods.map((period) {
              final periodSpan = _span(popupContext, period);
              return PopupMenuItem<_LeaderboardPeriod>(
                value: period,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            period.label(popupContext),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: period == selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          if (periodSpan.isNotEmpty)
                            Text(
                              periodSpan,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (period == selected)
                      Icon(AppIcons.check, size: 18, color: colors.primary),
                  ],
                ),
              );
            }).toList(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  selected.label(context),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(AppIcons.expandMore),
              ],
            ),
          ),
          if (span.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              span,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LeaderboardPodium extends StatelessWidget {
  const _LeaderboardPodium({
    required this.winners,
    required this.onTap,
  });

  final List<_LeaderboardEntry> winners;
  final ValueChanged<_LeaderboardEntry> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // 与官方一致：视觉顺序为第二、第一、第三。
    final ordered = <_LeaderboardEntry?>[
      winners.length > 1 ? winners[1] : null,
      winners.first,
      winners.length > 2 ? winners[2] : null,
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 28),
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 22),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(24),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / 3;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var index = 0; index < ordered.length; index++)
                Expanded(
                  child: ordered[index] == null
                      ? const SizedBox.shrink()
                      : _LeaderboardWinner(
                          entry: ordered[index]!,
                          slotWidth: width,
                          onTap: () => onTap(ordered[index]!),
                        ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LeaderboardWinner extends StatelessWidget {
  const _LeaderboardWinner({
    required this.entry,
    required this.slotWidth,
    required this.onTap,
  });

  final _LeaderboardEntry entry;
  final double slotWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final first = entry.position == 1;
    final medal = switch (entry.position) {
      1 => const Color(0xffffce35),
      2 => const Color(0xffb9bdc7),
      _ => const Color(0xffcd8b4a),
    };
    final radius = (slotWidth * (first ? 0.43 : 0.39))
        .clamp(24.0, 56.0)
        .toDouble();
    final score = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    ).format(entry.totalScore);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (first)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Icon(AppIcons.crown, color: medal, size: 28),
              ),
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    border: Border.all(color: medal, width: 2),
                    shape: BoxShape.circle,
                  ),
                  child: SmartAvatar(
                    imageUrl: entry.avatarUrl,
                    radius: radius,
                    fallbackText: entry.username,
                  ),
                ),
                Positioned(
                  bottom: -13,
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: medal,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.surface, width: 2),
                    ),
                    child: Text(
                      '${entry.position}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xff1c1c1c),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 19),
            Text(
              entry.name?.isNotEmpty == true ? entry.name! : entry.username,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: first ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                score,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: (first
                        ? theme.textTheme.titleLarge
                        : theme.textTheme.titleMedium)
                    ?.copyWith(
                  color: colors.onSurface,
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

class _LeaderboardRankingHeading extends StatelessWidget {
  const _LeaderboardRankingHeading({required this.copy});

  final _LeaderboardCopy copy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(copy.rank, style: theme.textTheme.titleSmall),
          Row(
            children: [
              Icon(AppIcons.medal, size: 18, color: colors.primary),
              const SizedBox(width: 6),
              Text(copy.points, style: theme.textTheme.titleSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _PersonalLeaderboardRank extends StatelessWidget {
  const _PersonalLeaderboardRank({
    required this.entry,
    required this.onTap,
  });

  final _LeaderboardEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final score = NumberFormat.compact(
      locale: 'en_US',
    ).format(entry.totalScore).toLowerCase();

    return Material(
      color: colors.primary,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              SizedBox(
                width: 74,
                child: Text(
                  '${entry.position}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.onPrimary,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  _copy(context).you,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 90,
                child: Text(
                  score,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.onPrimary,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
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
    required this.name,
    required this.periodFilterDisabled,
    required this.nextPage,
    required this.hasMore,
    required this.updatedAt,
  });

  final List<_LeaderboardEntry> entries;
  final _LeaderboardEntry? personal;
  final String? name;
  final bool periodFilterDisabled;
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

  static int asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  _LeaderboardEntry withPosition(int rank) => _LeaderboardEntry(
    id: id,
    username: username,
    name: name,
    avatarTemplate: avatarTemplate,
    totalScore: totalScore,
    position: rank,
  );

  factory _LeaderboardEntry.fromJson(Map<String, dynamic> json) {
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
    required this.globalTitle,
    required this.rank,
    required this.about,
    required this.aboutBody,
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
  final String globalTitle;
  final String rank;
  final String about;
  final String aboutBody;
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
      globalTitle: 'Global leaderboard',
      rank: 'Rank',
      about: 'About the leaderboard',
      aboutBody: 'Community points are calculated by the Discourse gamification plugin. Each time period has its own ranking.',
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
      daily: 'Today',
      weekly: 'Week',
      monthly: 'Month',
      quarterly: 'Quarter',
      yearly: 'Year',
    );
  }

  final traditional =
      locale.scriptCode == 'Hant' ||
      locale.countryCode == 'TW' ||
      locale.countryCode == 'HK';
  if (traditional) {
    return const _LeaderboardCopy(
      title: '排行榜',
      globalTitle: '全域排行榜',
      rank: '排名',
      about: '關於排行榜',
      aboutBody: '社群點數由 Discourse 積分外掛計算，不同時間範圍的排名各自獨立。',
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
      allTime: '所有時間',
      daily: '今天',
      weekly: '週',
      monthly: '月',
      quarterly: '季度',
      yearly: '年',
    );
  }

  return const _LeaderboardCopy(
    title: '排行榜',
    globalTitle: '全局排行榜',
    rank: '排名',
    about: '关于排行榜',
    aboutBody: '社区点数由 Discourse 积分插件计算，各个时间范围采用独立的排名。',
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
    allTime: '所有时间',
    daily: '今天',
    weekly: '周',
    monthly: '月',
    quarterly: '季度',
    yearly: '年',
  );
}
