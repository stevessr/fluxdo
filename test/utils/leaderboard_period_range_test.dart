import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/leaderboard_period_range.dart';

void main() {
  final now = DateTime.utc(2026, 10, 25, 12);

  test('周期跨度与官方展示一致', () {
    final yearly = LeaderboardDateRange.forPeriod(
      LeaderboardPeriod.yearly,
      now: now,
    );
    expect(yearly.start, DateTime.utc(2025, 10, 25));
    expect(yearly.end, DateTime.utc(2026, 10, 25));

    final quarter = LeaderboardDateRange.forPeriod(
      LeaderboardPeriod.quarterly,
      now: now,
    );
    expect(quarter.start, DateTime.utc(2026, 7, 25));

    final monthly = LeaderboardDateRange.forPeriod(
      LeaderboardPeriod.monthly,
      now: now,
    );
    expect(monthly.start, DateTime.utc(2026, 9, 25));

    final weekly = LeaderboardDateRange.forPeriod(
      LeaderboardPeriod.weekly,
      now: now,
    );
    expect(weekly.start, DateTime.utc(2026, 10, 19));
    expect(weekly.end, DateTime.utc(2026, 10, 25));

    final daily = LeaderboardDateRange.forPeriod(
      LeaderboardPeriod.daily,
      now: now,
    );
    expect(daily.start, DateTime.utc(2026, 10, 25));
  });

  test('月份位移按目标月最后一天截断，避免跨月', () {
    final leap = LeaderboardDateRange.forPeriod(
      LeaderboardPeriod.yearly,
      now: DateTime.utc(2024, 2, 29),
    );
    expect(leap.start, DateTime.utc(2023, 2, 28));

    final month = LeaderboardDateRange.forPeriod(
      LeaderboardPeriod.monthly,
      now: DateTime.utc(2026, 3, 31),
    );
    expect(month.start, DateTime.utc(2026, 2, 28));
  });

  test('总榜未配置日期时不虚构起点；站点边界会限制展示区间', () {
    final unlimited = LeaderboardDateRange.forPeriod(
      LeaderboardPeriod.allTime,
      now: now,
    );
    expect(unlimited.start, isNull);
    expect(unlimited.end, isNull);

    final bounded = LeaderboardDateRange.forPeriod(
      LeaderboardPeriod.yearly,
      now: now,
      fromDate: DateTime.utc(2026, 1, 1),
      toDate: DateTime.utc(2026, 9, 30),
    );
    expect(bounded.start, DateTime.utc(2026, 1, 1));
    expect(bounded.end, DateTime.utc(2026, 9, 30));
  });

  test('周期参数与 Discourse API 对应', () {
    expect(LeaderboardPeriod.allTime.apiValue, 'all_time');
    expect(LeaderboardPeriod.weekly.apiValue, 'weekly');
    expect(LeaderboardPeriod.daily.apiValue, 'daily');
  });
}
