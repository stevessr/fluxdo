import 'package:flutter/material.dart';

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
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  if (value.length == 10 && value[4] == '-' && value[7] == '-') {
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
  return parsed.toLocal();
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

/// Responsive Discourse-style calendar: compact cells on phones, named event
/// summaries on tablets, and a tappable agenda for the selected day.
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
  Widget build(BuildContext context) {
    return switch (scale) {
      EventCalendarScale.day => _dayView(context),
      EventCalendarScale.week => _weekView(context),
      EventCalendarScale.month => _monthView(context),
      EventCalendarScale.year => _yearView(context),
    };
  }

  Widget _weekdays(BuildContext context) {
    final labels = _zh(context)
        ? const ['周一', '周二', '周三', '周四', '周五', '周六', '周日']
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Row(children: [
      for (final label in labels)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(label, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall),
          ),
        ),
    ]);
  }

  Widget _monthView(BuildContext context) {
    final first = calendarRange(date, EventCalendarScale.month).start;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _weekdays(context),
        LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          return Column(
            children: [
              for (var week = 0; week < 6; week++)
                Row(
                  children: [
                    for (var weekday = 0; weekday < 7; weekday++)
                      Expanded(
                        child: _monthCell(
                          context,
                          DateTime(first.year, first.month, first.day + week * 7 + weekday),
                          compact,
                        ),
                      ),
                  ],
                ),
            ],
          );
        }),
        const SizedBox(height: 16),
        _agenda(context, date),
      ],
    );
  }

  Widget _monthCell(BuildContext context, DateTime day, bool compact) {
    final scheme = Theme.of(context).colorScheme;
    final today = _isSameDay(day, DateTime.now());
    final selected = _isSameDay(day, date);
    final outside = day.month != date.month;
    final items = calendarEventsForDay(events, day);
    return Semantics(
      button: true,
      selected: selected,
      label: '${day.year}-${day.month}-${day.day}, ${items.length} events',
      child: InkWell(
        onTap: () => onSelectDate(day),
        child: Container(
          height: compact ? 74 : 100,
          padding: EdgeInsets.all(compact ? 2 : 5),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer.withValues(alpha: .5) : null,
            border: Border.all(color: scheme.outlineVariant, width: .5),
          ),
          child: Column(
            children: [
              Container(
                width: 27,
                height: 27,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: today ? scheme.primary : null,
                ),
                child: Text('${day.day}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: today ? scheme.onPrimary : outside
                        ? scheme.onSurfaceVariant.withValues(alpha: .5) : null,
                    fontWeight: selected || today ? FontWeight.bold : null,
                  ),
                ),
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 4),
                if (compact)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: scheme.secondaryContainer,
                    ),
                    child: Text('${items.length}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10)),
                  )
                else
                  for (final event in items.take(2))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('• ${_name(context, event)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _weekView(BuildContext context) {
    final first = calendarWeekStart(date);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _weekdays(context),
        Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(child: _weekCell(context, DateTime(first.year, first.month, first.day + i))),
        ]),
        const SizedBox(height: 20),
        _agenda(context, date),
      ],
    );
  }

  Widget _weekCell(BuildContext context, DateTime day) {
    final selected = _isSameDay(date, day);
    final count = calendarEventsForDay(events, day).length;
    return InkWell(
      onTap: () => onSelectDate(day),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          Text('${day.day}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 5),
          Text(count == 0 ? '·' : '$count',
              style: Theme.of(context).textTheme.labelSmall),
        ]),
      ),
    );
  }

  Widget _dayView(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(12, 20, 12, 24),
    children: [_agenda(context, date)],
  );

  Widget _yearView(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth > 800 ? 4
          : constraints.maxWidth > 520 ? 3 : 2;
      return GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: 12,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.02,
        ),
        itemBuilder: (context, index) => _yearMonth(context,
          DateTime(date.year, index + 1)),
      );
    });
  }

  Widget _yearMonth(BuildContext context, DateTime month) {
    final scheme = Theme.of(context).colorScheme;
    final monday = calendarWeekStart(month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    var eventCount = 0;
    for (final event in events) {
      for (var d = 1; d <= days; d++) {
        if (eventOnCalendarDay(event, DateTime(month.year, month.month, d))) {
          eventCount++;
          break;
        }
      }
    }
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onSelectMonth(month),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _zh(context) ? '${month.month}月 · $eventCount'
                    : '${MaterialLocalizations.of(context).formatMonthYear(month)} · $eventCount',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Expanded(child: Column(children: [
                for (var week = 0; week < 6; week++)
                  Expanded(child: Row(children: [
                    for (var weekday = 0; weekday < 7; weekday++)
                      Expanded(child: Builder(builder: (context) {
                        final day = DateTime(monday.year, monday.month, monday.day + week * 7 + weekday);
                        final inside = day.month == month.month;
                        final marked = inside &&
                            calendarEventsForDay(events, day).isNotEmpty;
                        return Center(child: Text('${day.day}',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: marked ? FontWeight.bold : null,
                            color: !inside ? scheme.onSurfaceVariant.withValues(alpha: .3)
                                : marked ? scheme.primary : scheme.onSurfaceVariant,
                          )));
                      })),
                  ])),
              ])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _agenda(BuildContext context, DateTime date) {
    final items = calendarEventsForDay(events, date);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(MaterialLocalizations.of(context).formatMediumDate(date),
          style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(_zh(context) ? '当天没有活动' : 'No events on this day',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant)),
          ),
        for (final event in items)
          Card(child: ListTile(
            leading: const Icon(Icons.event_outlined),
            title: Text(_name(context, event),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(_time(context, event)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onTapEvent(event),
          )),
      ],
    );
  }

  String _time(BuildContext context, Map<String, dynamic> event) {
    final start = parseCalendarEventDate(event['starts_at']);
    final end = parseCalendarEventDate(event['ends_at']);
    if (start == null) return _zh(context) ? '时间待定' : 'Time TBD';
    if (event['all_day'] == true) return _zh(context) ? '全天' : 'All day';
    final first = TimeOfDay.fromDateTime(start).format(context);
    if (end == null) return first;
    return '$first – ${TimeOfDay.fromDateTime(end).format(context)}';
  }
}
