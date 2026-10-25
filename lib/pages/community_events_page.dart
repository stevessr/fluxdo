import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:app_icons/app_icons.dart';

import '../services/discourse/discourse_service.dart';
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

  /// Discourse `/cakeday/{type}/all?month=N` 的月份参数。
  final int? initialMonth;

  /// 允许测试注入 Dio；实际请求默认走全局 Discourse 网络链。
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

  Dio get _dio => widget.client ?? DiscourseService().dio;

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
      if (widget.view == CommunityEventsView.upcoming) {
        final now = DateTime.now();
        final response = await _dio.get<dynamic>(
          '/discourse-post-event/events',
          queryParameters: {
            // 官方 upcoming-events-list 默认向后看 180 天；原生页提高上限，
            // 仍让服务端按权限过滤可见事件。
            'limit': 100,
            'after': now.toUtc().toIso8601String(),
            'before': now
                .add(const Duration(days: 180))
                .toUtc()
                .toIso8601String(),
            'include_ongoing': true,
          },
        );
        final data = _asMap(response.data);
        final events = _asMapList(data['events']);
        events.sort((a, b) {
          final da = _parseEventDate(a['starts_at']) ?? DateTime(9999);
          final db = _parseEventDate(b['starts_at']) ?? DateTime(9999);
          return da.compareTo(db);
        });
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _items = events;
          _loading = false;
        });
        return;
      }

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
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  /// 和 Discourse 官方一样：事件类型是第一层，时间是第二层。
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
                _zh(context) ? '加载失败' : 'Failed to load',
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
    if (_items.isEmpty) {
      return Center(
        child: Text(
          _emptyLabel(context),
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    if (widget.view == CommunityEventsView.upcoming) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          itemCount: _items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 4),
          itemBuilder: (context, index) =>
              _buildEventTile(context, _items[index]),
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

  Widget _buildEventTile(BuildContext context, Map<String, dynamic> event) {
    final post = _asMap(event['post']);
    final topic = _asMap(post['topic']);
    final name =
        _string(event['name']) ??
        _string(topic['title']) ??
        (_zh(context) ? '未命名活动' : 'Untitled event');
    final url = _string(post['url']);
    final startsAt = _parseEventDate(event['starts_at']);
    final endsAt = _parseEventDate(event['ends_at']);
    final allDay = event['all_day'] == true;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: _eventDateBadge(context, startsAt),
        title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(_eventTimeLabel(context, startsAt, endsAt, allDay)),
        trailing: const Icon(Symbols.chevron_right_rounded),
        onTap: url == null ? null : () => launchContentLink(context, url),
      ),
    );
  }

  Widget _eventDateBadge(BuildContext context, DateTime? date) {
    if (date == null) return const Icon(Symbols.calendar_today_rounded);
    final local = date.toLocal();
    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${local.month}', style: Theme.of(context).textTheme.labelSmall),
          Text(
            '${local.day}',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
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

  String _eventTimeLabel(
    BuildContext context,
    DateTime? start,
    DateTime? end,
    bool allDay,
  ) {
    if (start == null) return _zh(context) ? '时间待定' : 'Time TBD';
    if (allDay) {
      if (end != null && !_sameLocalDay(start, end)) {
        return '${_dateLabel(context, start)} – ${_dateLabel(context, end)}';
      }
      return '${_dateLabel(context, start)} · ${_zh(context) ? '全天' : 'All day'}';
    }
    final localStart = start.toLocal();
    final startTime = TimeOfDay.fromDateTime(localStart).format(context);
    if (end == null) return '${_dateLabel(context, start)} · $startTime';
    final localEnd = end.toLocal();
    if (_sameLocalDay(start, end)) {
      return '${_dateLabel(context, start)} · $startTime – ${TimeOfDay.fromDateTime(localEnd).format(context)}';
    }
    return '${_dateLabel(context, start)} $startTime – ${_dateLabel(context, end)} ${TimeOfDay.fromDateTime(localEnd).format(context)}';
  }

  String _dateLabel(BuildContext context, DateTime value) =>
      MaterialLocalizations.of(context).formatMediumDate(value.toLocal());

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

  static bool _sameLocalDay(DateTime a, DateTime b) {
    final x = a.toLocal();
    final y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

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
