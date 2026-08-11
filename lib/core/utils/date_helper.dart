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
    // Fallback for other locales if date_format_jp is not suitable
    return DateFormat.yMMMMEEEEd(AppStrings.currentLocale).format(dt);
  }

  static String formatTime(DateTime dt) {
    return DateFormat('HH:mm').format(dt);
  }

  static String getDayOfWeek(DateTime dt) {
    return _weekdayLabels[dt.weekday - 1];
  }

  static int getWeekNumber(DateTime dt) {
    final firstDayOfYear = DateTime(dt.year, 1, 1);
    final daysOffset = firstDayOfYear.weekday - 1;
    final firstMonday = firstDayOfYear.subtract(Duration(days: daysOffset));
    final diff = dt.difference(firstMonday).inDays;
    return (diff / 7).floor() + 1;
  }

  static bool isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  static int daysUntil(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    return target.difference(today).inDays;
  }

  static String dueDateLabel(DateTime dt) {
    final diff = daysUntil(dt);
    if (diff < 0) return AppStrings.t('due_overdue');
    if (diff == 0) return AppStrings.t('due_today');
    if (diff == 1) return AppStrings.t('due_days_later', {'n': 1});
    if (diff < 7) return AppStrings.t('due_days_later', {'n': diff});
    return AppStrings.t('due_week_later');
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
