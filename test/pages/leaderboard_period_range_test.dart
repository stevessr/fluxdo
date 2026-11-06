import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/leaderboard_period_range.dart';

void main() {
  final today = DateTime(2026, 10, 25);

  test('周期范围与官方的 2026-10-25 示例一致', () {
    expect(leaderboardPeriodRange('all_time', today), isNull);

    final year = leaderboardPeriodRange('yearly', today)!;
    expect(year.start, DateTime(2025, 10, 25));
    expect(year.end, today);

    final quarter = leaderboardPeriodRange('quarterly', today)!;
    expect(quarter.start, DateTime(2026, 7, 25));
    expect(quarter.end, today);

    final month = leaderboardPeriodRange('monthly', today)!;
    expect(month.start, DateTime(2026, 9, 25));
    expect(month.end, today);

    final week = leaderboardPeriodRange('weekly', today)!;
    expect(week.start, DateTime(2026, 10, 19));
    expect(week.end, DateTime(2026, 10, 25));

    final day = leaderboardPeriodRange('daily', today)!;
    expect(day.start, today);
    expect(day.end, today);
  });

  test('跨年周榜正确归入同一自然周', () {
    final week = leaderboardPeriodRange('weekly', DateTime(2027, 1, 1))!;
    expect(week.start, DateTime(2026, 12, 28));
    expect(week.end, DateTime(2027, 1, 3));
  });

  test('31 日及闰年转换不发生月份溢出', () {
    expect(
      leaderboardPeriodRange('monthly', DateTime(2026, 3, 31))!.start,
      DateTime(2026, 2, 28),
    );
    expect(
      leaderboardPeriodRange('yearly', DateTime(2024, 2, 29))!.start,
      DateTime(2023, 2, 28),
    );
  });
}
