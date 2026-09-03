import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/bookmark.dart';

void main() {
  test('two hours uses elapsed-time semantics', () {
    final now = DateTime(2026, 3, 7, 23, 30);
    final reminder = BookmarkReminderOption.twoHours.toReminderAt(now: now)!;

    expect(reminder.difference(now), const Duration(hours: 2));
  });

  test('tomorrow and three days preserve local 08:00 wall clock', () {
    final now = DateTime(2026, 3, 7, 23, 30);

    final tomorrow = BookmarkReminderOption.tomorrow.toReminderAt(now: now)!;
    final threeDays = BookmarkReminderOption.threeDays.toReminderAt(now: now)!;

    expect(tomorrow, DateTime(2026, 3, 8, 8));
    expect(threeDays, DateTime(2026, 3, 10, 8));
    expect(tomorrow.isUtc, isFalse);
    expect(threeDays.isUtc, isFalse);
  });

  test('next week means the next Monday at local 08:00', () {
    final monday = DateTime(2026, 3, 9, 12);
    final sunday = DateTime(2026, 3, 8, 12);

    expect(
      BookmarkReminderOption.nextWeek.toReminderAt(now: monday),
      DateTime(2026, 3, 16, 8),
    );
    expect(
      BookmarkReminderOption.nextWeek.toReminderAt(now: sunday),
      DateTime(2026, 3, 9, 8),
    );
  });

  test('custom reminder remains caller supplied', () {
    expect(
      BookmarkReminderOption.custom.toReminderAt(
        now: DateTime(2026, 3, 7, 12),
      ),
      isNull,
    );
  });
}
