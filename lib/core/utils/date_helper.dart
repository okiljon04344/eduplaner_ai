import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';

abstract class DateHelper {
  static const _weekdayKanji = ['月', '火', '水', '木', '金', '土', '日'];

  static String formatJapaneseDate(DateTime dt) {
    return '${dt.year}年${dt.month}月${dt.day}日（${_weekdayKanji[dt.weekday - 1]}）';
  }

  static String formatTime(DateTime dt) {
    return DateFormat('HH:mm').format(dt);
  }

  static String getDayOfWeekJP(DateTime dt) {
    return _weekdayKanji[dt.weekday - 1];
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
    if (diff < 0) return '期限切れ';
    if (diff == 0) return '今日';
    if (diff == 1) return '1日後';
    if (diff < 7) return '$diff日後';
    return '1週間後';
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
