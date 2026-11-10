import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:app_icons/app_icons.dart';

import '../services/discourse/discourse_service.dart';
import '../services/auth_session.dart';
import 'community_events_calendar.dart';
import '../utils/link_launcher.dart';
import '../utils/url_helper.dart';
import '../widgets/common/smart_avatar.dart';

/// Discourse 站点级活动入口。
///
/// - [CommunityEventsView.upcoming] 对齐 discourse-events 的 Upcoming Events
/// - [CommunityEventsView.anniversaries] / [CommunityEventsView.birthdays]
///   对齐 discourse-cakeday
///
/// 这些页面故意直接消费插件公开 JSON 接口，而不是复制插件业务规则到客户端：
/// 过滤隐藏资料、时区、闰日和「注册当年不算周年」都仍由 Discourse 服务端决定。
enum CommunityEventsView { upcoming, anniversaries, birthdays }

class CommunityEventsPage extends StatefulWidget {
  const CommunityEventsPage({
    super.key,
    required this.view,
    this.initialFilter,
    this.initialMonth,
    this.client,
  });

  final CommunityEventsView view;

  /// 来自 `/cakeday/.../:filter` 的初始过滤器。
  /// 支持 today / tomorrow / upcoming / all（兼容旧 month）。
  final String? initialFilter;

  /// 官方 all 路由使用的月筛选参数。
  final int? initialMonth;

  /// 测试注入客户端；线上默认复用已有 Discourse 网络链。
  final Dio? client;

  @override
  State<CommunityEventsPage> createState() => _CommunityEventsPageState();
}

class _CommunityEventsPageState extends State<CommunityEventsPage> {
  static const _cakedayFilters = <String>[
    'today',
    'tomorrow',
    'upcoming',
    'all',
  ];

  final _service = DiscourseService();
  Dio get _dio => widget.client ?? _service.dio;

  bool _loading = true;
  Object? _error;
  Object? _loadMoreError;
  List<Map<String, dynamic>> _items = const [];
  String _filter = 'today';
  late CommunityEventsView _activeCakedayView;
  late int _month;
  int _loadGeneration = 0;
  String? _loadMorePath;
  bool _loadingMore = false;

  DateTime _calendarDate = calendarDay(DateTime.now());
  EventCalendarScale _calendarScale = EventCalendarScale.month;
  bool _myEvents = false;
  int _eventRequestId = 0;

  bool get _isCakeday => widget.view != CommunityEventsView.upcoming;

  @override
  void initState() {
    super.initState();
    _activeCakedayView = widget.view == CommunityEventsView.birthdays
        ? CommunityEventsView.birthdays
        : CommunityEventsView.anniversaries;
    _filter = _normalizeFilter(widget.initialFilter);
    _month = _normalizeMonth(widget.initialMonth);
    _load();
  }

  @override
  void didUpdateWidget(covariant CommunityEventsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view ||
        oldWidget.initialFilter != widget.initialFilter ||
        oldWidget.initialMonth != widget.initialMonth ||
        oldWidget.client != widget.client) {
      _activeCakedayView = widget.view == CommunityEventsView.birthdays
          ? CommunityEventsView.birthdays
          : CommunityEventsView.anniversaries;
      _filter = _normalizeFilter(widget.initialFilter);
      _month = _normalizeMonth(widget.initialMonth);
      _load();
    }
  }

  void _selectCakedayView(CommunityEventsView view) {
    if (_activeCakedayView == view) return;
    setState(() {
      _activeCakedayView = view;
      // 官方切换周年 / 生日时进入该分类的「今天」。
      _filter = 'today';
    });
    _load();
  }

  Future<void> _load({bool append = false}) async {
    if (widget.view == CommunityEventsView.upcoming) {
      // Prevent in-flight cakeday requests from replacing calendar results.
      ++_loadGeneration;
      await _loadCalendarEvents();
      return;
    }
    // The new cakeday view also invalidates outstanding calendar requests.
    ++_eventRequestId;
    if (append && (_loadingMore || _loadMorePath == null || _loading)) {
      return;
    }
    // 用户在请求中切换分类 / 筛选时，忽略过期结果。
    final generation = append ? _loadGeneration : ++_loadGeneration;
    if (!append) {
      setState(() {
        _loading = true;
        _error = null;
        _loadMoreError = null;
        _loadMorePath = null;
        _loadingMore = false;
        _items = const [];
      });
    } else {
      setState(() {
        _loadingMore = true;
        _loadMoreError = null;
      });
    }

    try {
      final segment = _activeCakedayView == CommunityEventsView.birthdays
          ? 'birthdays'
          : 'anniversaries';
      final path = append
          ? _loadMorePath!
          : _filter == 'all'
          ? '/cakeday/$segment/all'
          : '/cakeday/$segment/$_filter';
      final response = await _dio.get<dynamic>(
        path,
        queryParameters: append
            ? null
            : {'page': 0, if (_filter == 'all') 'month': _month},
      );
      final data = _asMap(response.data);
      final listKey = _activeCakedayView == CommunityEventsView.birthdays
          ? 'birthdays'
          : 'anniversaries';
      final moreKey = _activeCakedayView == CommunityEventsView.birthdays
          ? 'load_more_birthdays'
          : 'load_more_anniversaries';
      final loaded = _asMapList(data[listKey]);
      if (!mounted || generation != _loadGeneration) return;
      final combined = append ? [..._items, ...loaded] : loaded;
      // 官方接口即使到了最后一页也可能返回下一页 URL；
      // 应根据 total_rows 判断是否继续展示「加载更多」。
      final totalValue = data['total_rows_$segment'];
      final total = totalValue is num
          ? totalValue.toInt()
          : int.tryParse(totalValue?.toString() ?? '');
      final morePath = _string(data[moreKey]);
      final hasMore = total != null
          ? combined.length < total
          : loaded.isNotEmpty && morePath != null;
      setState(() {
        _items = combined;
        _loadMoreError = null;
        _loadMorePath = hasMore ? morePath : null;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (append) {
          // 下一页失败保留已加载的用户及重试入口。
          _loadMoreError = e;
        } else {
          _error = e;
        }
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadCalendarEvents() async {
    final request = ++_eventRequestId;
    final generation = AuthSession().generation;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      String? username;
      if (_myEvents) {
        username = await _service.getUsername();
        if (username == null || username.isEmpty) {
          throw StateError('请先登录以查看我的活动');
        }
      }

      final visible = calendarRange(_calendarDate, _calendarScale);
      // A full year can exceed the endpoint's 200-event limit.
      // Fetch quarters independently to avoid truncating the year view.
      final periods = <EventCalendarRange>[];
      if (_calendarScale == EventCalendarScale.year) {
        for (var month = 1; month <= 12; month += 3) {
          periods.add(
            EventCalendarRange(
              DateTime(_calendarDate.year, month),
              DateTime(_calendarDate.year, month + 3),
            ),
          );
        }
      } else {
        periods.add(visible);
      }

      final batches = await Future.wait(
        periods.map((period) => _fetchCalendarPeriod(period, username)),
      );
      final found = <String, Map<String, dynamic>>{};
      for (final entries in batches) {
        for (final event in entries) {
          final key = '${event['id']}:${event['starts_at']}';
          found[key] = event;
        }
      }
      final ordered = found.values.toList()
        ..sort((a, b) {
          final first = _parseEventDate(a['starts_at']) ?? DateTime(9999);
          final second = _parseEventDate(b['starts_at']) ?? DateTime(9999);
          return first.compareTo(second);
        });
      if (!mounted ||
          request != _eventRequestId ||
          !AuthSession().isValid(generation)) {
        return;
      }
      setState(() {
        _items = ordered;
        _loading = false;
      });
    } catch (error) {
      if (!mounted ||
          request != _eventRequestId ||
          !AuthSession().isValid(generation)) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// Discourse limits one response to 200 event series. Split saturated
  /// windows so a busy site doesn't silently lose events in month/year view.
  /// A one-day window is the smallest useful partition.
  Future<List<Map<String, dynamic>>> _fetchCalendarPeriod(
    EventCalendarRange period,
    String? username,
  ) async {
    final response = await _dio.get<dynamic>(
      '/discourse-post-event/events',
      queryParameters: {
        'limit': 200,
        'after': period.start
            .subtract(const Duration(seconds: 1))
            .toUtc()
            .toIso8601String(),
        'before': period.end.toUtc().toIso8601String(),
        'include_ongoing': true,
        if (username != null) 'include_interested': true,
        if (username != null && username.isNotEmpty) 'attending_user': username,
      },
    );
    final events = _asMapList(_asMap(response.data)['events']);
    final days = DateTime.utc(period.end.year, period.end.month, period.end.day)
        .difference(
          DateTime.utc(period.start.year, period.start.month, period.start.day),
        )
        .inDays;
    if (events.length < 200 || days <= 1) {
      return expandCalendarEventOccurrences(events);
    }
    final midpoint = DateTime(
      period.start.year,
      period.start.month,
      period.start.day + days ~/ 2,
    );
    final halves = await Future.wait([
      _fetchCalendarPeriod(
        EventCalendarRange(period.start, midpoint),
        username,
      ),
      _fetchCalendarPeriod(EventCalendarRange(midpoint, period.end), username),
    ]);
    return [...halves[0], ...halves[1]];
  }

  void _setCalendarDate(DateTime date, {EventCalendarScale? scale}) {
    final nextScale = scale ?? _calendarScale;
    final oldRange = calendarRange(_calendarDate, _calendarScale);
    final newRange = calendarRange(date, nextScale);
    setState(() {
      _calendarDate = calendarDay(date);
      _calendarScale = nextScale;
    });
    if (oldRange.start != newRange.start || oldRange.end != newRange.end) {
      _loadCalendarEvents();
    }
  }

  void _moveCalendar(int direction) {
    final day = _calendarDate;
    final next = switch (_calendarScale) {
      EventCalendarScale.day => DateTime(
        day.year,
        day.month,
        day.day + direction,
      ),
      EventCalendarScale.week => DateTime(
        day.year,
        day.month,
        day.day + direction * 7,
      ),
      EventCalendarScale.month => DateTime(day.year, day.month + direction, 1),
      EventCalendarScale.year => DateTime(day.year + direction, day.month, 1),
    };
    _setCalendarDate(next);
  }

  String _calendarPeriodLabel(BuildContext context) {
    final date = _calendarDate;
    final localizations = MaterialLocalizations.of(context);
    return switch (_calendarScale) {
      EventCalendarScale.day => localizations.formatMediumDate(date),
      EventCalendarScale.week =>
        '${localizations.formatMediumDate(calendarWeekStart(date))} – '
            '${localizations.formatMediumDate(DateTime(date.year, date.month, date.day - date.weekday + 7))}',
      EventCalendarScale.month => localizations.formatMonthYear(date),
      EventCalendarScale.year => date.year.toString(),
    };
  }

  /// 官方式分段选择器，避免 ChoiceChip 分散占用三行。
  Widget _calendarFilters(BuildContext context) {
    final zh = _zh(context);
    final scheme = Theme.of(context).colorScheme;
    return ToggleButtons(
      isSelected: [!_myEvents, _myEvents],
      onPressed: (index) {
        final next = index == 1;
        if (_myEvents == next) return;
        setState(() => _myEvents = next);
        _loadCalendarEvents();
      },
      fillColor: scheme.primary,
      selectedColor: scheme.onPrimary,
      color: scheme.onSurface,
      selectedBorderColor: scheme.primary,
      borderRadius: BorderRadius.circular(5),
      constraints: const BoxConstraints(minHeight: 36, minWidth: 56),
      children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Text(zh ? '所有活动' : 'All events')),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Text(zh ? '我的活动' : 'My events')),
      ],
    );
  }

  Widget _calendarNavigation(BuildContext context) {
    final zh = _zh(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        tooltip: zh ? '上一时间段' : 'Previous period',
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        onPressed: () => _moveCalendar(-1),
        icon: const Icon(Icons.chevron_left),
      ),
      IconButton(
        tooltip: zh ? '下一时间段' : 'Next period',
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        onPressed: () => _moveCalendar(1),
        icon: const Icon(Icons.chevron_right),
      ),
      OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: () => _setCalendarDate(DateTime.now()),
        child: Text(zh ? '今天' : 'Today'),
      ),
    ]);
  }

  Widget _calendarScales(BuildContext context) {
    final zh = _zh(context);
    final scheme = Theme.of(context).colorScheme;
    return ToggleButtons(
      isSelected: [
        for (final scale in EventCalendarScale.values)
          _calendarScale == scale,
      ],
      onPressed: (index) {
        final scale = EventCalendarScale.values[index];
        if (scale != _calendarScale) {
          _setCalendarDate(_calendarDate, scale: scale);
        }
      },
      fillColor: scheme.primary,
      selectedColor: scheme.onPrimary,
      color: scheme.onSurface,
      selectedBorderColor: scheme.primary,
      borderRadius: BorderRadius.circular(5),
      constraints: const BoxConstraints(minHeight: 36, minWidth: 32),
      children: [
        for (final scale in EventCalendarScale.values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text(switch (scale) {
              EventCalendarScale.day => zh ? '天' : 'Day',
              EventCalendarScale.week => zh ? '周' : 'Week',
              EventCalendarScale.month => zh ? '月' : 'Month',
              EventCalendarScale.year => zh ? '年' : 'Year',
            }),
          ),
      ],
    );
  }

  Widget _calendarGuidelines(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final zh = _zh(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: scheme.secondaryContainer.withValues(alpha: .7),
        child: InkWell(
          onTap: () => launchContentLink(context, '/guidelines'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: zh
                      ? '真诚、友善、团结、专业，'
                      : 'Sincere, friendly, united, professional. ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: zh
                    ? '共建你我引以为荣之社区。 '
                    : 'Build a community we are proud of. '),
                TextSpan(
                  text: zh ? '《社区准则》' : 'Guidelines',
                  style: TextStyle(color: scheme.primary),
                ),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarControls(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final label = Text(
        _calendarPeriodLabel(context),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600),
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: constraints.maxWidth >= 840
            ? Row(children: [
                _calendarFilters(context),
                const SizedBox(width: 12),
                _calendarNavigation(context),
                Expanded(child: label),
                _calendarScales(context),
              ])
            : constraints.maxWidth >= 440
                ? Column(children: [
                    Row(children: [
                      _calendarFilters(context),
                      const Spacer(),
                      _calendarNavigation(context),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: label),
                      const SizedBox(width: 8),
                      _calendarScales(context),
                    ]),
                  ])
                : Column(children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _calendarFilters(context),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      _calendarNavigation(context),
                      const Spacer(),
                      _calendarScales(context),
                    ]),
                    const SizedBox(height: 8),
                    label,
                  ]),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title(context)),
        actions: [
          IconButton(
            tooltip: _zh(context) ? '刷新' : 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Symbols.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isCakeday) _buildCakedayTypeTabs(context),
          if (_isCakeday) _buildCakedayFilter(context),
          if (_isCakeday && _filter == 'all') _buildMonthSelector(context),
          if (!_isCakeday) _calendarGuidelines(context),
          if (!_isCakeday) _buildCalendarControls(context),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildCakedayTypeTabs(BuildContext context) {
    final zh = _zh(context);
    return Row(
      children: [
        for (final view in const [
          CommunityEventsView.anniversaries,
          CommunityEventsView.birthdays,
        ])
          _cakedayTab(
            context,
            label: view == CommunityEventsView.anniversaries
                ? (zh ? '周年纪念日' : 'Anniversaries')
                : (zh ? '生日' : 'Birthdays'),
            selected: _activeCakedayView == view,
            onTap: () => _selectCakedayView(view),
          ),
      ],
    );
  }

  Widget _buildCakedayFilter(BuildContext context) {
    final labels = _zh(context)
        ? const ['今天', '明天', '即将到来', '所有']
        : const ['Today', 'Tomorrow', 'Upcoming', 'All'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _cakedayFilters.length; i++)
            _cakedayTab(
              context,
              label: labels[i],
              selected: _filter == _cakedayFilters[i],
              onTap: () {
                if (_filter == _cakedayFilters[i]) return;
                setState(() => _filter = _cakedayFilters[i]);
                _load();
              },
            ),
        ],
      ),
    );
  }

  Widget _cakedayTab(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? colorScheme.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? colorScheme.primary : colorScheme.onSurface,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthSelector(BuildContext context) {
    final zh = _zh(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      child: Row(
        children: [
          Text(zh ? '选择月份' : 'Month'),
          const SizedBox(width: 16),
          DropdownButton<int>(
            value: _month,
            items: [
              for (var month = 1; month <= 12; month++)
                DropdownMenuItem(
                  value: month,
                  child: Text(
                    // 此处按每年的「月份」筛选，不能显示某个特定年份。
                    DateFormat.MMMM(Localizations.localeOf(context).toString())
                        .format(DateTime(2000, month)),
                  ),
                ),
            ],
            onChanged: (month) {
              if (month == null || month == _month) return;
              setState(() => _month = month);
              _load();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Symbols.error_outline_rounded, size: 40),
              const SizedBox(height: 12),
              Text(
                _error is StateError
                    ? _error.toString().replaceFirst('Bad state: ', '')
                    : (_zh(context) ? '加载失败' : 'Failed to load'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: _load,
                child: Text(_zh(context) ? '重试' : 'Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (widget.view == CommunityEventsView.upcoming) {
      return RefreshIndicator(
        onRefresh: _loadCalendarEvents,
        child: CommunityEventsCalendar(
          date: _calendarDate,
          scale: _calendarScale,
          events: _items,
          onSelectDate: (day) =>
              _setCalendarDate(day, scale: EventCalendarScale.day),
          onSelectMonth: (month) =>
              _setCalendarDate(month, scale: EventCalendarScale.month),
          onTapEvent: (event) {
            final post = _asMap(event['post']);
            final url = _string(post['url']) ?? _string(event['url']);
            if (url != null) launchContentLink(context, url);
          },
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          _emptyLabel(context),
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
        itemCount: _items.length + (_loadMorePath != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : FilledButton.tonal(
                        onPressed: () => _load(append: true),
                        child: Text(
                          _loadMoreError != null
                              ? (_zh(context) ? '加载失败，重试' : 'Retry loading')
                              : (_zh(context) ? '加载更多' : 'Load more'),
                        ),
                      ),
              ),
            );
          }
          return _buildCakedayUserTile(context, _items[index]);
        },
      ),
    );
  }

  Widget _buildCakedayUserTile(
    BuildContext context,
    Map<String, dynamic> user,
  ) {
    final username = _string(user['username']) ?? '';
    final name = _string(user['name']);
    final title = _string(user['title']);
    final cakedate = _string(user['cakedate']);
    final avatarTemplate = _string(user['avatar_template']);
    final avatar = avatarTemplate == null
        ? null
        : UrlHelper.resolveUrlWithCdn(
            avatarTemplate.replaceAll('{size}', '96'),
          );

    return ListTile(
      leading: SmartAvatar(
        imageUrl: avatar,
        radius: 22,
        fallbackText: username,
      ),
      title: Text(
        name?.isNotEmpty == true ? name! : username,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          '@$username',
          if (title?.isNotEmpty == true) title!,
          if (cakedate != null) _formatCakedate(context, cakedate),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        _activeCakedayView == CommunityEventsView.birthdays
            ? Symbols.cake_rounded
            : Symbols.celebration_rounded,
      ),
      onTap: username.isEmpty
          ? null
          : () => launchContentLink(
              context,
              '/u/${Uri.encodeComponent(username)}',
            ),
    );
  }

  String _formatCakedate(BuildContext context, String value) {
    // anniversaries 的 cakedate 来自 users.created_at，序列化时可能是
    // `YYYY-MM-DDTHH:mm:ss...`；birthdays 则通常是纯 `YYYY-MM-DD`。
    // 两者都只显示服务端已按用户时区筛选后的月/日，不把周年时间戳再次
    // 转时区，避免跨日。
    if (value.length < 10) return value;
    final month = int.tryParse(value.substring(5, 7));
    final day = int.tryParse(value.substring(8, 10));
    if (month == null || day == null) return value;
    return _zh(context) ? '$month月$day日' : '$month/$day';
  }

  String _title(BuildContext context) {
    final zh = _zh(context);
    return switch (widget.view) {
      CommunityEventsView.upcoming => zh ? '近期活动' : 'Upcoming events',
      CommunityEventsView.anniversaries || CommunityEventsView.birthdays =>
        zh ? '纪念日与生日' : 'Anniversaries & Birthdays',
    };
  }

  String _emptyLabel(BuildContext context) {
    final zh = _zh(context);
    if (widget.view == CommunityEventsView.upcoming) {
      return zh ? '近期没有活动' : 'No upcoming events';
    }
    return switch (_filter) {
      'today' => zh ? '今天没有用户庆祝' : 'Nobody to celebrate today',
      'tomorrow' => zh ? '明天没有用户庆祝' : 'Nobody to celebrate tomorrow',
      'upcoming' =>
        zh ? '接下来 7 天没有用户庆祝' : 'Nobody to celebrate in the next 7 days',
      _ => zh ? '本月没有用户庆祝' : 'Nobody to celebrate this month',
    };
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  static List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static String? _string(dynamic value) =>
      value is String && value.isNotEmpty ? value : null;

  static DateTime? _parseEventDate(dynamic value) =>
      parseCalendarEventDate(value);

  static String _normalizeFilter(String? value) {
    if (value == 'today' ||
        value == 'tomorrow' ||
        value == 'upcoming' ||
        value == 'all') {
      return value!;
    }
    if (value == 'month') return 'all';
    return 'today';
  }

  static int _normalizeMonth(int? value) =>
      value != null && value >= 1 && value <= 12 ? value : DateTime.now().month;

  static bool _zh(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'zh';
}
