import 'package:edu_planner_ai/core/l10n/app_strings.dart';
import 'package:edu_planner_ai/core/utils/date_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  group('DateHelper.daysBetween (a − b, calendar days)', () {
    test('across a month end', () {
      expect(DateHelper.daysBetween(DateTime(2026, 2, 1), DateTime(2026, 1, 31)), 1);
      expect(DateHelper.daysBetween(DateTime(2026, 5, 1), DateTime(2026, 4, 30)), 1);
    });

    test('across a year end', () {
      expect(DateHelper.daysBetween(DateTime(2027, 1, 1), DateTime(2026, 12, 31)), 1);
      expect(DateHelper.daysBetween(DateTime(2027, 12, 31), DateTime(2026, 12, 31)), 365);
    });

    test('February: 28 days in 2027, 29 in 2028', () {
      expect(DateHelper.daysBetween(DateTime(2027, 3, 1), DateTime(2027, 2, 1)), 28);
      expect(DateHelper.daysBetween(DateTime(2028, 3, 1), DateTime(2028, 2, 1)), 29);
    });

    test('ignores time of day, and is negative when a is earlier', () {
      expect(DateHelper.daysBetween(DateTime(2026, 6, 2, 0, 30), DateTime(2026, 6, 1, 23, 30)), 1);
      expect(DateHelper.daysBetween(DateTime(2026, 6, 1, 23, 59), DateTime(2026, 6, 1, 0, 1)), 0);
      expect(DateHelper.daysBetween(DateTime(2026, 6, 1, 23, 30), DateTime(2026, 6, 2, 0, 30)), -1);
    });

    test('is exactly 1 around common DST changeover dates', () {
      // Local-time DateTimes: on a machine in a DST zone these days are 23h/25h long.
      for (final (m, d) in [(3, 8), (3, 29), (10, 25), (11, 1)]) {
        expect(DateHelper.daysBetween(DateTime(2026, m, d + 1, 0, 30), DateTime(2026, m, d, 23, 30)), 1);
        expect(DateHelper.daysBetween(DateTime(2026, m, d + 1), DateTime(2026, m, d)), 1);
      }
    });
  });

  test('daysUntil is 0 for today and 1 for tomorrow', () {
    final now = DateTime.now();
    expect(DateHelper.daysUntil(now), 0);
    expect(DateHelper.daysUntil(DateTime(now.year, now.month, now.day + 1, 12)), 1);
    expect(DateHelper.daysUntil(DateTime(now.year, now.month, now.day - 3, 12)), -3);
  });

  group('DateHelper.dueDateLabel', () {
    setUpAll(() => initializeDateFormatting(null));

    /// Noon, [offset] calendar days from today (calendar arithmetic, DST-safe).
    DateTime day(int offset) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day + offset, 12);
    }

    test('overdue, today and 1..6 days away', () {
      expect(DateHelper.dueDateLabel(day(-1)), AppStrings.t('due_overdue'));
      expect(DateHelper.dueDateLabel(day(0)), AppStrings.t('due_today'));
      expect(DateHelper.dueDateLabel(day(1)), AppStrings.t('due_days_later', {'n': 1}));
      expect(DateHelper.dueDateLabel(day(6)), AppStrings.t('due_days_later', {'n': 6}));
    });

    test('7..13 days away is "a week later"', () {
      expect(DateHelper.dueDateLabel(day(7)), AppStrings.t('due_week_later'));
      expect(DateHelper.dueDateLabel(day(13)), AppStrings.t('due_week_later'));
    });

    test('14+ days away shows the actual date', () {
      final far = day(14);
      expect(DateHelper.dueDateLabel(far), DateFormat.MMMd(AppStrings.currentLocale).format(far));
      expect(DateHelper.dueDateLabel(far), isNot(AppStrings.t('due_week_later')));
    });
  });
}
