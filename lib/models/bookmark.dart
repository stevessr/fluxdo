import '../l10n/s.dart';

/// 书签提醒的快捷选项
enum BookmarkReminderOption {
  twoHours, // 2小时后
  tomorrow, // 明天
  threeDays, // 3天后
  nextWeek, // 下周
  custom, // 自定义
}

/// 书签自动删除偏好
enum BookmarkAutoDeletePreference {
  never(0),
  whenReminderSent(1),
  onOwnerReply(2),
  clearReminder(3);

  final int value;
  const BookmarkAutoDeletePreference(this.value);
}

/// BookmarkReminderOption 的扩展方法
extension BookmarkReminderOptionExt on BookmarkReminderOption {
  String get label {
    switch (this) {
      case BookmarkReminderOption.twoHours:
        return S.current.bookmark_reminderTwoHours;
      case BookmarkReminderOption.tomorrow:
        return S.current.bookmark_reminderTomorrow;
      case BookmarkReminderOption.threeDays:
        return S.current.bookmark_reminderThreeDays;
      case BookmarkReminderOption.nextWeek:
        return S.current.bookmark_reminderNextWeek;
      case BookmarkReminderOption.custom:
        return S.current.bookmark_reminderCustom;
    }
  }

  /// 根据选项计算提醒时间。
  ///
  /// `tomorrow` / `threeDays` / `nextWeek` are calendar reminders: construct a
  /// new local [DateTime] at 08:00 instead of adding a fixed 24-hour duration.
  /// That preserves the intended wall-clock time when the device timezone
  /// crosses a DST boundary. `twoHours` intentionally remains elapsed-time
  /// semantics. The service converts the resulting instant to UTC before it is
  /// sent to Discourse.
  DateTime? toReminderAt({DateTime? now}) {
    final base = now ?? DateTime.now();
    switch (this) {
      case BookmarkReminderOption.twoHours:
        return base.add(const Duration(hours: 2));
      case BookmarkReminderOption.tomorrow:
        return DateTime(base.year, base.month, base.day + 1, 8);
      case BookmarkReminderOption.threeDays:
        return DateTime(base.year, base.month, base.day + 3, 8);
      case BookmarkReminderOption.nextWeek:
        final daysUntilMonday = (DateTime.monday - base.weekday + 7) % 7;
        final nextMonday = daysUntilMonday == 0 ? 7 : daysUntilMonday;
        return DateTime(base.year, base.month, base.day + nextMonday, 8);
      case BookmarkReminderOption.custom:
        return null;
    }
  }
}
