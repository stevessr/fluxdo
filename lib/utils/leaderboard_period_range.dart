/// 与 Discourse 排行榜周期选择器一致的日期区间展示模型。
///
/// 区间只用于解释服务器提供的周期筛选，不参与客户端重新计算点数；
/// 真实排名始终来自 /leaderboard/:id.json 的 period 参数。
enum LeaderboardPeriod { allTime, yearly, quarterly, monthly, weekly, daily }

extension LeaderboardPeriodApi on LeaderboardPeriod {
  String get apiValue => switch (this) {
    LeaderboardPeriod.allTime => 'all_time',
    LeaderboardPeriod.yearly => 'yearly',
    LeaderboardPeriod.quarterly => 'quarterly',
    LeaderboardPeriod.monthly => 'monthly',
    LeaderboardPeriod.weekly => 'weekly',
    LeaderboardPeriod.daily => 'daily',
  };
}

class LeaderboardDateRange {
  const LeaderboardDateRange({this.start, this.end});

  final DateTime? start;
  final DateTime? end;

  /// 用 UTC 日期避免设备时区跨日使筛选范围随设备位置漂移。
  /// 周区间按官方选择器的本周一至今天展示；年月季为向前滚动周期。
  static LeaderboardDateRange forPeriod(
    LeaderboardPeriod period, {
    DateTime? now,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    final instant = (now ?? DateTime.now()).toUtc();
    final today = DateTime.utc(instant.year, instant.month, instant.day);
    DateTime? start;

    switch (period) {
      case LeaderboardPeriod.allTime:
        start = fromDate;
      case LeaderboardPeriod.yearly:
        start = _shiftMonths(today, 12);
      case LeaderboardPeriod.quarterly:
        start = _shiftMonths(today, 3);
      case LeaderboardPeriod.monthly:
        start = _shiftMonths(today, 1);
      case LeaderboardPeriod.weekly:
        start = today.subtract(Duration(days: today.weekday - DateTime.monday));
      case LeaderboardPeriod.daily:
        start = today;
    }

    if (fromDate != null && start != null && fromDate.isAfter(start)) {
      start = fromDate;
    }

    DateTime? end = period == LeaderboardPeriod.allTime ? toDate : today;
    if (end != null && toDate != null && toDate.isBefore(end)) {
      end = toDate;
    }

    return LeaderboardDateRange(start: start, end: end);
  }

  static DateTime _shiftMonths(DateTime date, int months) {
    final target = DateTime.utc(date.year, date.month - months, 1);
    final maxDay = DateTime.utc(target.year, target.month + 1, 0).day;
    return DateTime.utc(
      target.year,
      target.month,
      date.day < maxDay ? date.day : maxDay,
    );
  }
}
