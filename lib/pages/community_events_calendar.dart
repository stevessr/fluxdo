import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/time_utils.dart';

enum EventCalendarScale { day, week, month, year }

/// The end of a visible period is exclusive.
class EventCalendarRange {
  const EventCalendarRange(this.start, this.end);
  final DateTime start;
  final DateTime end;
}

DateTime calendarDay(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime calendarWeekStart(DateTime date) {
  final day = calendarDay(date);
  return DateTime(day.year, day.month, day.day - day.weekday + 1);
}

EventCalendarRange calendarRange(DateTime date, EventCalendarScale scale) {
  final day = calendarDay(date);
  switch (scale) {
    case EventCalendarScale.day:
      return EventCalendarRange(day, DateTime(day.year, day.month, day.day + 1));
    case EventCalendarScale.week:
      final start = calendarWeekStart(day);
      return EventCalendarRange(start, DateTime(start.year, start.month, start.day + 7));
    case EventCalendarScale.month:
      final start = calendarWeekStart(DateTime(day.year, day.month));
      return EventCalendarRange(start, DateTime(start.year, start.month, start.day + 42));
    case EventCalendarScale.year:
      return EventCalendarRange(DateTime(day.year), DateTime(day.year + 1));
  }
}

/// Date-only all-day values must not be converted from UTC.
DateTime? parseCalendarEventDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  if (value.length == 10 && value[4] == '-' && value[7] == '-') {
    final year = int.tryParse(value.substring(0, 4));
    final month = int.tryParse(value.substring(5, 7));
    final day = int.tryParse(value.substring(8, 10));
    if (year == null || month == null || day == null) return null;
    final localDay = DateTime(year, month, day);
    if (localDay.year != year || localDay.month != month ||
        localDay.day != day) return null;
    return localDay;
  }
  return TimeUtils.parseUtcTime(value);
}

bool eventOnCalendarDay(Map<String, dynamic> event, DateTime date) {
  final start = parseCalendarEventDate(event['starts_at']);
  if (start == null) return false;
  final first = calendarDay(start);
  final day = calendarDay(date);
  final end = parseCalendarEventDate(event['ends_at']);
  var last = end == null ? first : calendarDay(end);
  // Timed events ending at 00:00 do not occupy the next calendar day.
  if (end != null && event['all_day'] != true &&
      end.hour == 0 && end.minute == 0 && end.second == 0 &&
      end.millisecond == 0 && end.microsecond == 0 &&
      last.isAfter(first)) {
    last = DateTime(last.year, last.month, last.day - 1);
  }
  return !day.isBefore(first) && !day.isAfter(last);
}

/// Discourse returns one event with an `occurrences` array for recurring
/// series. Treat each occurrence as a calendar entry while preserving its post
/// URL, name, RSVP information and original event id.
List<Map<String, dynamic>> expandCalendarEventOccurrences(
  List<Map<String, dynamic>> events,
) {
  final expanded = <Map<String, dynamic>>[];
  for (final event in events) {
    final occurrences = event['occurrences'];
    if (occurrences is List) {
      if (occurrences.isNotEmpty) {
        for (final occurrence in occurrences) {
          if (occurrence is! Map) continue;
          final start = occurrence['starts_at'];
          if (parseCalendarEventDate(start) == null) continue;
          expanded.add({
            ...event,
            'starts_at': start,
            'ends_at': occurrence['ends_at'],
          });
        }
        continue;
      }
      // An empty occurrence array for a recurring series means there is
      // nothing in the requested window. Don't display its original date.
      final recurrence = event['recurrence'];
      if (recurrence is String && recurrence.isNotEmpty &&
          recurrence != 'none') {
        continue;
      }
    }
    if (parseCalendarEventDate(event['starts_at']) != null) {
      expanded.add(event);
    }
  }
  return expanded;
}

List<Map<String, dynamic>> calendarEventsForDay(
    List<Map<String, dynamic>> events, DateTime day) {
  return events.where((event) => eventOnCalendarDay(event, day)).toList();
}

/// 某一天时间轴上的活动占位。重叠活动分别占用独立列，避免遮挡。
class CalendarTimedPlacement {
  CalendarTimedPlacement({
    required this.event,
    required this.start,
    required this.end,
  });

  final Map<String, dynamic> event;
  final DateTime start;
  final DateTime end;
  int lane = 0;
  int laneCount = 1;
}

bool calendarEventIsAllDay(Map<String, dynamic> event) =>
    event['all_day'] == true ||
    (event['starts_at'] is String &&
        (event['starts_at'] as String).length == 10);

/// 为全天时间网格分配不重叠的列，事件的起止时间会裁切到本日。
List<CalendarTimedPlacement> layoutTimedCalendarEvents(
  List<Map<String, dynamic>> events,
  DateTime day,
) {
  final startOfDay = calendarDay(day);
  final endOfDay =
      DateTime(startOfDay.year, startOfDay.month, startOfDay.day + 1);
  final placements = <CalendarTimedPlacement>[];
  for (final event in events) {
    if (calendarEventIsAllDay(event) || !eventOnCalendarDay(event, day)) {
      continue;
    }
    final start = parseCalendarEventDate(event['starts_at']);
    if (start == null) continue;
    final suppliedEnd = parseCalendarEventDate(event['ends_at']);
    final end = suppliedEnd != null && suppliedEnd.isAfter(start)
        ? suppliedEnd
        : start.add(const Duration(hours: 1));
    final clippedStart = start.isBefore(startOfDay) ? startOfDay : start;
    final clippedEnd = end.isAfter(endOfDay) ? endOfDay : end;
    if (!clippedEnd.isAfter(clippedStart)) continue;
    placements.add(CalendarTimedPlacement(
      event: event,
      start: clippedStart,
      end: clippedEnd,
    ));
  }

  placements.sort((a, b) {
    final order = a.start.compareTo(b.start);
    return order != 0 ? order : a.end.compareTo(b.end);
  });

  final laneEnds = <DateTime>[];
  final group = <CalendarTimedPlacement>[];
  DateTime? groupEnd;

  void finishGroup() {
    for (final entry in group) {
      entry.laneCount = laneEnds.length;
    }
    group.clear();
    laneEnds.clear();
  }

  for (final placement in placements) {
    if (groupEnd != null && !placement.start.isBefore(groupEnd)) {
      finishGroup();
      groupEnd = null;
    }
    final available =
        laneEnds.indexWhere((ending) => !ending.isAfter(placement.start));
    if (available == -1) {
      placement.lane = laneEnds.length;
      laneEnds.add(placement.end);
    } else {
      placement.lane = available;
      laneEnds[available] = placement.end;
    }
    group.add(placement);
    if (groupEnd == null || placement.end.isAfter(groupEnd)) {
      groupEnd = placement.end;
    }
  }
  if (group.isNotEmpty) finishGroup();
  return placements;
}

/// 对齐 Discourse 官方 Upcoming Events 的四种视图。
class CommunityEventsCalendar extends StatelessWidget {
  const CommunityEventsCalendar({
    super.key,
    required this.date,
    required this.scale,
    required this.events,
    required this.onSelectDate,
    required this.onSelectMonth,
    required this.onTapEvent,
  });

  final DateTime date;
  final EventCalendarScale scale;
  final List<Map<String, dynamic>> events;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<DateTime> onSelectMonth;
  final ValueChanged<Map<String, dynamic>> onTapEvent;

  bool _zh(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'zh';

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _name(BuildContext context, Map<String, dynamic> event) {
    final post = event['post'];
    final topic = post is Map ? post['topic'] : null;
    final title = topic is Map ? topic['title'] : null;
    final name = event['name'];
    if (name is String && name.isNotEmpty) return name;
    if (title is String && title.isNotEmpty) return title;
    return _zh(context) ? '未命名活动' : 'Untitled event';
  }

  @override
  Widget build(BuildContext context) => switch (scale) {
    EventCalendarScale.day => _timeline(context, false),
    EventCalendarScale.week => _timeline(context, true),
    EventCalendarScale.month => _monthView(context),
    EventCalendarScale.year => _yearView(context),
  };

  Widget _weekdays(BuildContext context) {
    final labels = _zh(context)
        ? const ['周一', '周二', '周三', '周四', '周五', '周六', '周日']
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return SizedBox(
      height: 30,
      child: Row(children: [
        for (final label in labels)
          Expanded(
            child: Center(child: Text(label,
              style: Theme.of(context).textTheme.labelSmall)),
          ),
      ]),
    );
  }

  Widget _monthView(BuildContext context) {
    final first = calendarRange(date, EventCalendarScale.month).start;
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 550;
      final height = constraints.maxHeight.isFinite
          ? math.max(constraints.maxHeight, compact ? 440.0 : 530.0)
          : 560.0;
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: height,
          child: Column(children: [
            _weekdays(context),
            for (var week = 0; week < 6; week++)
              Expanded(
                child: Row(children: [
                  for (var weekday = 0; weekday < 7; weekday++)
                    Expanded(child: _monthCell(
                      context,
                      DateTime(first.year, first.month,
                          first.day + week * 7 + weekday),
                      compact,
                    )),
                ]),
              ),
          ]),
        ),
      );
    });
  }

  Widget _monthCell(BuildContext context, DateTime day, bool compact) {
    final scheme = Theme.of(context).colorScheme;
    final today = _isSameDay(day, DateTime.now());
    final selected = _isSameDay(day, date);
    final outside = day.month != date.month;
    final items = calendarEventsForDay(events, day);
    final visible = compact ? 1 : 3;
    return Semantics(
      button: true,
      selected: selected,
      label: day.toString() + ', ' + items.length.toString() + ' events',
      child: InkWell(
        onTap: () => onSelectDate(day),
        child: Container(
          height: double.infinity,
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 2 : 5, vertical: 3),
          decoration: BoxDecoration(
            color: today
                ? scheme.primaryContainer.withValues(alpha: .75)
                : selected
                    ? scheme.secondaryContainer.withValues(alpha: .65)
                    : null,
            border: Border(
              right: BorderSide(color: scheme.outlineVariant, width: .5),
              bottom: BorderSide(color: scheme.outlineVariant, width: .5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                day.day.toString() + (_zh(context) ? '日' : ''),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: today || selected ? FontWeight.bold : null,
                  color: outside
                      ? scheme.onSurfaceVariant.withValues(alpha: .42)
                      : scheme.onSurface,
                ),
              ),
              const SizedBox(height: 3),
              for (final event in items.take(visible))
                Flexible(
                  fit: FlexFit.loose,
                  child: InkWell(
                    onTap: () => onTapEvent(event),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        compact ? '•' : _name(context, event),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: compact ? 11 : 12,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              if (items.length > visible)
                Text('+' + (items.length - visible).toString(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeline(BuildContext context, bool week) {
    final first = week ? calendarWeekStart(date) : calendarDay(date);
    final days = [
      for (var i = 0; i < (week ? 7 : 1); i++)
        DateTime(first.year, first.month, first.day + i),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final grid = _CalendarTimeline(
        days: days,
        events: events,
        titleFor: _name,
        onSelectDate: onSelectDate,
        onTapEvent: onTapEvent,
        zh: _zh(context),
      );
      if (week && constraints.maxWidth < 650) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: 740, height: constraints.maxHeight, child: grid),
        );
      }
      return grid;
    });
  }

  /// 年视图按活动所在日期分组，不渲染十二个月的迷你日历。
  Widget _yearView(BuildContext context) {
    final first = DateTime(date.year);
    final last = DateTime(date.year, 12, 31);
    final grouped = <DateTime, List<Map<String, dynamic>>>{};
    for (final event in events) {
      final start = parseCalendarEventDate(event['starts_at']);
      if (start == null) continue;
      final end = parseCalendarEventDate(event['ends_at']) ?? start;
      var day = calendarDay(start);
      if (day.isBefore(first)) day = first;
      final lastDay = calendarDay(end).isAfter(last) ? last : calendarDay(end);
      while (!day.isAfter(lastDay)) {
        if (eventOnCalendarDay(event, day)) {
          grouped.putIfAbsent(day, () => []).add(event);
        }
        day = DateTime(day.year, day.month, day.day + 1);
      }
    }
    final days = grouped.keys.toList()..sort();
    if (days.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text(
              _zh(context) ? '本年没有活动' : 'No events this year',
              style: Theme.of(context).textTheme.bodyMedium)),
          ),
        ],
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final weekdays = _zh(context)
        ? const ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日']
        : const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        final items = grouped[day]!;
        final today = _isSameDay(day, DateTime.now());
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => onSelectDate(day),
            child: Container(
              color: today ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                Expanded(child: Text(
                  _zh(context)
                      ? day.year.toString() + '年' + day.month.toString() +
                          '月' + day.day.toString() + '日'
                      : MaterialLocalizations.of(context).formatMediumDate(day),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary, fontWeight: FontWeight.w600),
                )),
                Text(weekdays[day.weekday - 1],
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.primary)),
              ]),
            ),
          ),
          for (final event in items)
            InkWell(
              onTap: () => onTapEvent(event),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  SizedBox(width: 76,
                    child: Text(_time(context, event),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall)),
                  Icon(Icons.circle, size: 8, color: scheme.primary),
                  const SizedBox(width: 14),
                  Expanded(child: Text(_name(context, event),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium)),
                ]),
              ),
            ),
        ]);
      },
    );
  }

  String _time(BuildContext context, Map<String, dynamic> event) {
    final start = parseCalendarEventDate(event['starts_at']);
    final end = parseCalendarEventDate(event['ends_at']);
    if (start == null) return _zh(context) ? '待定' : 'TBD';
    if (event['all_day'] == true ||
        (event['starts_at'] is String &&
         (event['starts_at'] as String).length == 10)) {
      return _zh(context) ? '全天' : 'All day';
    }
    final first = TimeOfDay.fromDateTime(start).format(context);
    return end == null ? first : first + ' – ' +
        TimeOfDay.fromDateTime(end).format(context);
  }
}

typedef _EventTitle = String Function(
    BuildContext context, Map<String, dynamic> event);

/// 时间轴独立持有滚动控制器，初次进入定位 06:00。
class _CalendarTimeline extends StatefulWidget {
  const _CalendarTimeline({
    required this.days,
    required this.events,
    required this.titleFor,
    required this.onSelectDate,
    required this.onTapEvent,
    required this.zh,
  });

  final List<DateTime> days;
  final List<Map<String, dynamic>> events;
  final _EventTitle titleFor;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<Map<String, dynamic>> onTapEvent;
  final bool zh;

  @override
  State<_CalendarTimeline> createState() => _CalendarTimelineState();
}

class _CalendarTimelineState extends State<_CalendarTimeline> {
  static const double _hourHeight = 54;
  static const double _gutter = 46;
  late final ScrollController _scrollController =
      ScrollController(initialScrollOffset: 6 * _hourHeight);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _isAllDay(Map<String, dynamic> event) =>
      calendarEventIsAllDay(event);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = BorderSide(color: scheme.outlineVariant, width: .5);
    final today = calendarDay(DateTime.now());
    return Column(children: [
      SizedBox(
        height: 38,
        child: Row(children: [
          const SizedBox(width: _gutter),
          for (final day in widget.days)
            Expanded(
              child: InkWell(
                onTap: () => widget.onSelectDate(day),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border(
                    left: border, bottom: border)),
                  child: Text(
                    widget.days.length == 1
                        ? (widget.zh ? '星期' + _weekName(day.weekday)
                            : _weekName(day.weekday))
                        : (day.month.toString() + '/' + day.day.toString() +
                            ' ' + (widget.zh ? '周' : '') + _weekName(day.weekday)),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: calendarDay(day) == today ? FontWeight.bold : null),
                  ),
                ),
              ),
            ),
        ]),
      ),
      SizedBox(
        height: 62,
        child: Row(children: [
          SizedBox(width: _gutter,
            child: Center(child: Text(widget.zh ? '全天' : 'All day',
              style: Theme.of(context).textTheme.labelSmall))),
          for (final day in widget.days)
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: calendarDay(day) == today
                      ? scheme.primaryContainer.withValues(alpha: .65)
                      : null,
                  border: Border(left: border, bottom: border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final event in calendarEventsForDay(widget.events, day)
                        .where(_isAllDay).take(2))
                      Flexible(child: InkWell(
                        onTap: () => widget.onTapEvent(event),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          color: scheme.secondaryContainer,
                          child: Text(widget.titleFor(context, event),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall),
                        ),
                      )),
                    if (calendarEventsForDay(widget.events, day)
                            .where(_isAllDay).length > 2)
                      Text(
                        '+' + (calendarEventsForDay(widget.events, day)
                            .where(_isAllDay).length - 2).toString(),
                        style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
            ),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          child: LayoutBuilder(builder: (context, constraints) {
            final cellWidth = (constraints.maxWidth - _gutter) /
                widget.days.length;
            return SizedBox(
              height: 24 * _hourHeight,
              child: Stack(children: [
                Column(children: [
                  for (var hour = 0; hour < 24; hour++)
                    SizedBox(
                      height: _hourHeight,
                      child: Row(children: [
                        SizedBox(
                          width: _gutter,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Text(widget.zh
                              ? hour.toString() + '时'
                              : hour.toString().padLeft(2, '0') + ':00',
                              style: Theme.of(context).textTheme.labelSmall),
                          ),
                        ),
                        for (final day in widget.days)
                          Expanded(child: Container(
                            decoration: BoxDecoration(
                              color: calendarDay(day) == today
                                  ? scheme.primaryContainer.withValues(alpha: .4)
                                  : null,
                              border: Border(left: border, top: border),
                            ),
                          )),
                      ]),
                    ),
                ]),
                for (var index = 0; index < widget.days.length; index++)
                  for (final placement in layoutTimedCalendarEvents(
                      widget.events, widget.days[index]))
                    _eventBlock(context, placement, widget.days[index],
                        index, cellWidth),
              ]),
            );
          }),
        ),
      ),
    ]);
  }

  String _weekName(int day) {
    if (widget.zh) {
      return const ['一', '二', '三', '四', '五', '六', '日'][day - 1];
    }
    return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day - 1];
  }

  Widget _eventBlock(BuildContext context, CalendarTimedPlacement placement,
      DateTime day, int column, double width) {
    final dayStart = calendarDay(day);
    final minuteOffset = placement.start.difference(dayStart).inMinutes;
    final minutes = placement.end.difference(placement.start).inMinutes;
    final scheme = Theme.of(context).colorScheme;
    final laneWidth = width / placement.laneCount;
    return Positioned(
      left: _gutter + column * width + placement.lane * laneWidth + 2,
      top: minuteOffset / 60 * _hourHeight,
      width: math.max(1.0, laneWidth - 4),
      height: math.min(
        24 * _hourHeight - minuteOffset / 60 * _hourHeight,
        math.max(24.0, minutes / 60 * _hourHeight),
      ),
      child: Material(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.onTapEvent(placement.event),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              widget.titleFor(context, placement.event),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onPrimaryContainer),
            ),
          ),
        ),
      ),
    );
  }
}
