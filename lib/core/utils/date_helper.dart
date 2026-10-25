import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';

abstract class DateHelper {
  static List<String> get _weekdayLabels => [
        AppStrings.t('day_mon'),
        AppStrings.t('day_tue'),
        AppStrings.t('day_wed'),
        AppStrings.t('day_thu'),
        AppStrings.t('day_fri'),
        AppStrings.t('day_sat'),
        AppStrings.t('day_sun'),
      ];

  static String formatJapaneseDate(DateTime dt) {
    if (AppStrings.currentLocale == 'ja') {
      return AppStrings.t('date_format_jp', {
        'y': dt.year,
        'm': dt.month,
        'd': dt.day,
        'w': _weekdayLabels[dt.weekday - 1],
      });
    }
    // Other locales use the intl full date format.
    return DateFormat.yMMMMEEEEd(AppStrings.currentLocale).format(dt);
  }

  /// Localized label for a kanji weekday key ('月'..'日') as stored in
  /// `ClassModel.dayOfWeek`; unknown input is returned unchanged.
  static String localizedWeekday(String kanjiDay) {
    const kanjiOrder = ['月', '火', '水', '木', '金', '土', '日'];
    final i = kanjiOrder.indexOf(kanjiDay);
    return i == -1 ? kanjiDay : _weekdayLabels[i];
  }

  /// `yyyy-MM-dd` key for once-per-day logic (streaks, cached AI results).
  static String dayKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  /// Whole calendar days from [b] to [a] (positive when [a] is later), ignoring
  /// time of day. Both dates go through UTC midnight so a DST change can't make
  /// `inDays` one day short (23h) or long (25h).
  static int daysBetween(DateTime a, DateTime b) =>
      DateTime.utc(a.year, a.month, a.day)
          .difference(DateTime.utc(b.year, b.month, b.day))
          .inDays;

  static int daysUntil(DateTime dt) => daysBetween(dt, DateTime.now());

  static String dueDateLabel(DateTime dt) {
    final diff = daysUntil(dt);
    if (diff < 0) return AppStrings.t('due_overdue');
    if (diff == 0) return AppStrings.t('due_today');
    if (diff < 7) return AppStrings.t('due_days_later', {'n': diff});
    if (diff < 14) return AppStrings.t('due_week_later');
    // Far-off dates show the date itself; "1 week later" would be wrong.
    return DateFormat.MMMd(AppStrings.currentLocale).format(dt);
  }

  static Color dueDateColor(DateTime dt) {
    final diff = daysUntil(dt);
    if (diff <= 1) return AppColors.danger;
    if (diff <= 3) return AppColors.warning;
    return AppColors.success;
  }

  static Color dueDateBgColor(DateTime dt) {
    final diff = daysUntil(dt);
    if (diff <= 1) return AppColors.dangerLight;
    if (diff <= 3) return AppColors.warningLight;
    return AppColors.successLight;
  }
}
