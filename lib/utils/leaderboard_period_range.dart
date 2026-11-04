/// 与 Discourse period-chooser 一致的日历日期显示范围。
/// 仅用于 UI；排行榜分数仍由服务器通过 period 参数计算。
class LeaderboardPeriodRange {
  const LeaderboardPeriodRange(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

DateTime _shiftMonthsClamped(DateTime value, int months) {
  final first = DateTime(value.year, value.month + months);
  final lastDay = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(
    first.year,
    first.month,
    value.day > lastDay ? lastDay : value.day,
  );
}

/// [now] 使用终端本地时间；周榜按周一至周日展示，其他榜单为滚动窗口。
/// all_time 没有固定起点，因此返回 null。
LeaderboardPeriodRange? leaderboardPeriodRange(String period, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  switch (period) {
    case 'all_time':
    case 'all':
      return null;
    case 'daily':
      return LeaderboardPeriodRange(today, today);
    case 'weekly':
      final monday = today.subtract(Duration(days: today.weekday - 1));
      return LeaderboardPeriodRange(
        monday,
        monday.add(const Duration(days: 6)),
      );
    case 'monthly':
      return LeaderboardPeriodRange(_shiftMonthsClamped(today, -1), today);
    case 'quarterly':
      return LeaderboardPeriodRange(_shiftMonthsClamped(today, -3), today);
    case 'yearly':
      return LeaderboardPeriodRange(_shiftMonthsClamped(today, -12), today);
    default:
      return null;
  }
}
