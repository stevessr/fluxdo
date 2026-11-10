import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/pages/community_events_calendar.dart';

void main() {
  group('Discourse calendar ranges', () {
    test('week starts on Monday and includes Sunday', () {
      final range = calendarRange(DateTime(2026, 10, 25),
          EventCalendarScale.week);
      expect(range.start, DateTime(2026, 10, 19));
      expect(range.end, DateTime(2026, 10, 26));
    });

    test('month has 42 day cells, including adjacent months', () {
      final range = calendarRange(DateTime(2026, 10, 25),
          EventCalendarScale.month);
      expect(range.start, DateTime(2026, 9, 28));
      expect(range.end, DateTime(2026, 11, 9));
    });

    test('year is a half-open period', () {
      final range = calendarRange(DateTime(2026, 10, 25),
          EventCalendarScale.year);
      expect(range.start, DateTime(2026, 1, 1));
      expect(range.end, DateTime(2027, 1, 1));
    });

    test('day scale crosses month and year boundaries', () {
      final range = calendarRange(DateTime(2026, 12, 31),
          EventCalendarScale.day);
      expect(range.end, DateTime(2027, 1, 1));
    });
  });

  group('Discourse event placement', () {
    test('date-only all-day values preserve the local calendar day', () {
      final date = parseCalendarEventDate('2026-10-25');
      expect(date, DateTime(2026, 10, 25));
    });

    test('multi-day all-day events appear on every included date', () {
      final event = <String, dynamic>{
        'starts_at': '2026-10-24',
        'ends_at': '2026-10-26',
        'all_day': true,
      };
      expect(eventOnCalendarDay(event, DateTime(2026, 10, 23)), isFalse);
      for (final day in [24, 25, 26]) {
        expect(eventOnCalendarDay(event, DateTime(2026, 10, day)), isTrue);
      }
      expect(eventOnCalendarDay(event, DateTime(2026, 10, 27)), isFalse);
    });

    test('timed events ending at midnight do not spill to the next day', () {
      final event = <String, dynamic>{
        'starts_at': '2026-10-24T20:00:00',
        'ends_at': '2026-10-25T00:00:00',
        'all_day': false,
      };
      expect(eventOnCalendarDay(event, DateTime(2026, 10, 24)), isTrue);
      expect(eventOnCalendarDay(event, DateTime(2026, 10, 25)), isFalse);
    });

    test('recurring events expose all server-provided occurrence dates', () {
      final master = <String, dynamic>{
        'id': 17,
        'name': 'Weekly standup',
        'starts_at': '2026-09-01T10:00:00Z',
        'ends_at': '2026-09-01T11:00:00Z',
        'recurrence': 'every_week',
        'post': {'url': '/t/standup/4'},
        'occurrences': [
          {
            'starts_at': '2026-10-20T10:00:00',
            'ends_at': '2026-10-20T11:00:00',
          },
          {
            'starts_at': '2026-10-27T10:00:00',
            'ends_at': '2026-10-27T11:00:00',
          },
        ],
      };
      final occurrences = expandCalendarEventOccurrences([master]);
      expect(occurrences, hasLength(2));
      expect(occurrences[0]['post'], master['post']);
      expect(occurrences[1]['id'], 17);
      expect(calendarEventsForDay(occurrences, DateTime(2026, 10, 27)),
          hasLength(1));
      expect(calendarEventsForDay(occurrences, DateTime(2026, 9, 1)),
          isEmpty);
    });

    test('empty recurring occurrence list does not restore obsolete date', () {
      final events = expandCalendarEventOccurrences([
        <String, dynamic>{
          'id': 23,
          'starts_at': '2026-01-01',
          'recurrence': 'every_month',
          'occurrences': <Map<String, dynamic>>[],
        }
      ]);
      expect(events, isEmpty);
    });

    test('non-recurring legacy responses without occurrences still display', () {
      final original = <String, dynamic>{
        'id': 24,
        'starts_at': '2026-10-25',
        'all_day': true,
      };
      expect(expandCalendarEventOccurrences([original]), [original]);
    });

    test('events without a valid start date are ignored', () {
      final event = <String, dynamic>{'name': 'Undated'};
      expect(eventOnCalendarDay(event, DateTime(2026, 10, 25)), isFalse);
    });
  });

  testWidgets('年视图按日期排列并展示跨日全天活动', (tester) async {
    final event = <String, dynamic>{
      'name': '连续社区活动',
      'starts_at': '2026-02-13',
      'ends_at': '2026-02-15',
      'all_day': true,
    };
    DateTime? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CommunityEventsCalendar(
          date: DateTime(2026, 2, 14),
          scale: EventCalendarScale.year,
          events: [event],
          onSelectDate: (day) => picked = day,
          onSelectMonth: (_) {},
          onTapEvent: (_) {},
        ),
      ),
    ));
    expect(find.text('连续社区活动'), findsNWidgets(3));
    expect(find.textContaining('Feb 13'), findsOneWidget);
    expect(find.textContaining('Feb 14'), findsOneWidget);
    expect(find.textContaining('Feb 15'), findsOneWidget);
    await tester.tap(find.textContaining('Feb 14'));
    expect(picked, DateTime(2026, 2, 14));
  });

  testWidgets('日视图同时展示全天与定时活动，并能打开活动', (tester) async {
    final allDay = <String, dynamic>{
      'name': '全天活动',
      'starts_at': '2026-11-10',
      'all_day': true,
    };
    final timed = <String, dynamic>{
      'name': '上午会议',
      'starts_at': '2026-11-10T09:00:00',
      'ends_at': '2026-11-10T10:00:00',
      'all_day': false,
    };
    Map<String, dynamic>? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CommunityEventsCalendar(
        date: DateTime(2026, 11, 10),
        scale: EventCalendarScale.day,
        events: [allDay, timed],
        onSelectDate: (_) {},
        onSelectMonth: (_) {},
        onTapEvent: (event) => tapped = event,
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('All day'), findsOneWidget);
    expect(find.text('全天活动'), findsOneWidget);
    expect(find.text('上午会议'), findsOneWidget);
    await tester.tap(find.text('上午会议'));
    expect(tapped, same(timed));
  });

  testWidgets('周视图显示七列并允许选择其中一天', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CommunityEventsCalendar(
        date: DateTime(2026, 11, 10),
        scale: EventCalendarScale.week,
        events: const [],
        onSelectDate: (day) => picked = day,
        onSelectMonth: (_) {},
        onTapEvent: (_) {},
      )),
    ));
    expect(find.textContaining('11/9'), findsOneWidget);
    expect(find.textContaining('11/15'), findsOneWidget);
    await tester.tap(find.textContaining('11/15'));
    expect(picked, DateTime(2026, 11, 15));
  });

  testWidgets('month view includes navigation and selected-day agenda',
      (tester) async {
    final sample = <String, dynamic>{
      'name': 'Discourse meetup',
      'starts_at': '2026-10-25',
      'all_day': true,
    };
    DateTime? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CommunityEventsCalendar(
          date: DateTime(2026, 10, 25),
          scale: EventCalendarScale.month,
          events: [sample],
          onSelectDate: (date) => selected = date,
          onSelectMonth: (_) {},
          onTapEvent: (_) {},
        ),
      ),
    ));
    expect(find.textContaining('Discourse meetup'), findsWidgets);
    await tester.tap(find.byType(InkWell).first);
    expect(selected, isNotNull);
  });
}
