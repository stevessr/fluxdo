import 'package:flutter/material.dart';
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
  });

  final CommunityEventsView view;

  /// 来自 `/cakeday/.../:filter` 的初始过滤器。
  /// 只接受 today / tomorrow / upcoming；其它值按 today 处理。
  final String? initialFilter;

  @override
  State<CommunityEventsPage> createState() => _CommunityEventsPageState();
}

class _CommunityEventsPageState extends State<CommunityEventsPage> {
  static const _cakedayFilters = <String>[
    'today',
    'tomorrow',
    'upcoming',
    'month',
  ];

  final _service = DiscourseService();

  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _items = const [];
  String _filter = 'today';
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
    _filter = _normalizeFilter(widget.initialFilter);
    _load();
  }

  @override
  void didUpdateWidget(covariant CommunityEventsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view ||
        oldWidget.initialFilter != widget.initialFilter) {
      _filter = _normalizeFilter(widget.initialFilter);
      _load();
    }
  }

  Future<void> _load({bool append = false}) async {
    if (widget.view == CommunityEventsView.upcoming) {
      await _loadCalendarEvents();
      return;
    }
    // The widget can be reused for cakeday views: discard old calendar responses.
    ++_eventRequestId;
    if (!append) {
      setState(() {
        _loading = true;
        _error = null;
        _loadMorePath = null;
      });
    } else {
      if (_loadingMore || _loadMorePath == null) return;
      setState(() => _loadingMore = true);
    }

    try {
      final segment = widget.view == CommunityEventsView.birthdays
          ? 'birthdays'
          : 'anniversaries';
      final path = append
          ? _loadMorePath!
          : _filter == 'month'
          ? '/cakeday/$segment'
          : '/cakeday/$segment/$_filter';
      final response = await _service.dio.get<dynamic>(
        path,
        queryParameters: append
            ? null
            : {
                'page': 0,
                if (_filter == 'month') 'month': DateTime.now().month,
              },
      );
      final data = _asMap(response.data);
      final listKey = widget.view == CommunityEventsView.birthdays
          ? 'birthdays'
          : 'anniversaries';
      final moreKey = widget.view == CommunityEventsView.birthdays
          ? 'load_more_birthdays'
          : 'load_more_anniversaries';
      final loaded = _asMapList(data[listKey]);
      if (!mounted) return;
      setState(() {
        _items = append ? [..._items, ...loaded] : loaded;
        _loadMorePath = data[moreKey] as String?;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
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
          periods.add(EventCalendarRange(
            DateTime(_calendarDate.year, month),
            DateTime(_calendarDate.year, month + 3),
          ));
        }
      } else {
        periods.add(visible);
      }

      final responses = await Future.wait(periods.map((period) =>
        _service.dio.get<dynamic>(
          '/discourse-post-event/events',
          queryParameters: {
            'limit': 200,
            // Include events starting at exactly the first instant.
            'after': period.start.subtract(const Duration(seconds: 1))
                .toUtc().toIso8601String(),
            'before': period.end.toUtc().toIso8601String(),
            'include_ongoing': true,
            if (username != null && username.isNotEmpty)
              'attending_user': username,
          },
        ),
      ));
      final found = <String, Map<String, dynamic>>{};
      for (final response in responses) {
        final entries = _asMapList(_asMap(response.data)['events']);
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
      if (!mounted || request != _eventRequestId ||
          !AuthSession().isValid(generation)) {
        return;
      }
      setState(() {
        _items = ordered;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _eventRequestId ||
          !AuthSession().isValid(generation)) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _setCalendarDate(DateTime date, {EventCalendarScale? scale}) {
    final nextScale = scale ?? _calendarScale;
    final oldRange = calendarRange(_calendarDate, _calendarScale);
    final newRange = calendarRange(date, nextScale);
    setState(() {
      _calendarDate = calendarDay(date);
      _calendarScale = nextScale;
    });
    if (oldRange.start != newRange.start ||
        oldRange.end != newRange.end) {
      _loadCalendarEvents();
    }
  }

  void _moveCalendar(int direction) {
    final day = _calendarDate;
    final next = switch (_calendarScale) {
      EventCalendarScale.day => DateTime(day.year, day.month, day.day + direction),
      EventCalendarScale.week => DateTime(day.year, day.month, day.day + direction * 7),
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

  Widget _buildCalendarControls(BuildContext context) {
    final zh = _zh(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: Text(zh ? '所有活动' : 'All events'),
              selected: !_myEvents,
              onSelected: (value) {
                if (!value || !_myEvents) return;
                setState(() => _myEvents = false);
                _loadCalendarEvents();
              },
            ),
            ChoiceChip(
              label: Text(zh ? '我的活动' : 'My events'),
              selected: _myEvents,
              onSelected: (value) {
                if (!value || _myEvents) return;
                setState(() => _myEvents = true);
                _loadCalendarEvents();
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(children: [
          IconButton(
            tooltip: zh ? '上一时间段' : 'Previous period',
            onPressed: () => _moveCalendar(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(child: Text(_calendarPeriodLabel(context),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium)),
          IconButton(
            tooltip: zh ? '下一时间段' : 'Next period',
            onPressed: () => _moveCalendar(1),
            icon: const Icon(Icons.chevron_right),
          ),
          TextButton(
            onPressed: () => _setCalendarDate(DateTime.now()),
            child: Text(zh ? '今天' : 'Today'),
          ),
        ]),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final scale in EventCalendarScale.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(switch (scale) {
                    EventCalendarScale.day => zh ? '天' : 'Day',
                    EventCalendarScale.week => zh ? '周' : 'Week',
                    EventCalendarScale.month => zh ? '月' : 'Month',
                    EventCalendarScale.year => zh ? '年' : 'Year',
                  }),
                  selected: _calendarScale == scale,
                  onSelected: (selected) {
                    if (!selected || _calendarScale == scale) return;
                    _setCalendarDate(_calendarDate, scale: scale);
                  },
                ),
              ),
          ]),
        ),
      ]),
    );
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
          if (_isCakeday) _buildCakedayFilter(context),
          if (!_isCakeday) _buildCalendarControls(context),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildCakedayFilter(BuildContext context) {
    final labels = _zh(context)
        ? const ['今天', '明天', '即将到来', '本月']
        : const ['Today', 'Tomorrow', 'Upcoming', 'This month'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          for (var i = 0; i < _cakedayFilters.length; i++) ...[
            ChoiceChip(
              label: Text(labels[i]),
              selected: _filter == _cakedayFilters[i],
              onSelected: (selected) {
                if (!selected || _filter == _cakedayFilters[i]) return;
                setState(() => _filter = _cakedayFilters[i]);
                _load();
              },
            ),
            if (i != _cakedayFilters.length - 1) const SizedBox(width: 8),
          ],
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
                _error is StateError ? _error.toString().replaceFirst('Bad state: ', '') :
                (_zh(context) ? '加载失败' : 'Failed to load'),
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
      return CommunityEventsCalendar(
        date: _calendarDate,
        scale: _calendarScale,
        events: _items,
        onSelectDate: _setCalendarDate,
        onSelectMonth: (month) => _setCalendarDate(
          month, scale: EventCalendarScale.month),
        onTapEvent: (event) {
          final post = _asMap(event['post']);
          final url = _string(post['url']) ?? _string(event['url']);
          if (url != null) launchContentLink(context, url);
        },
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
                        child: Text(_zh(context) ? '加载更多' : 'Load more'),
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
        widget.view == CommunityEventsView.birthdays
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
      CommunityEventsView.anniversaries => zh ? '周年纪念日' : 'Anniversaries',
      CommunityEventsView.birthdays => zh ? '生日' : 'Birthdays',
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

  static DateTime? _parseEventDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    // discourse-events 的全天事件可能返回 YYYY-MM-DD；显式按本地日历构造，
    // 避免把 date-only 当 UTC 导致西半球日期前移一天。
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      final parts = value.split('-');
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);
      if (year == null || month == null || day == null) return null;
      return DateTime(year, month, day);
    }
    return DateTime.tryParse(value);
  }

  static String _normalizeFilter(String? value) {
    if (value == 'today' || value == 'tomorrow' || value == 'upcoming') {
      return value!;
    }
    return 'today';
  }

  static bool _zh(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'zh';
}
