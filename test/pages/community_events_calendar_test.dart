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

    test('events without a valid start date are ignored', () {
      final event = <String, dynamic>{'name': 'Undated'};
      expect(eventOnCalendarDay(event, DateTime(2026, 10, 25)), isFalse);
    });
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
    expect(find.text('Discourse meetup'), findsOneWidget);
    await tester.tap(find.byType(InkWell).first);
    expect(selected, isNotNull);
  });
}
