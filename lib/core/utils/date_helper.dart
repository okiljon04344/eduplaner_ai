import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';

/// Utility class offering date formatting, weekday localization, day key generation,
/// and relative time calculations.
///
/// UZ: Sana formatlash, hafta kunlarini mahalliylashtirish, kun kalitini yaratish
/// va nisbiy vaqt hisob-kitoblarini taqdim etuvchi yordamchi sinf.
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
    // UZ: date_format_jp mos kelmasa, boshqa lokallar uchun zaxira (fallback)
    return DateFormat.yMMMMEEEEd(AppStrings.currentLocale).format(dt);
  }

  static String getDayOfWeek(DateTime dt) {
    return _weekdayLabels[dt.weekday - 1];
  }

  /// Localized label for a canonical kanji weekday key ('月'..'金') as stored
  /// in Firestore (`ClassModel.dayOfWeek`). Returns the input unchanged for
  /// anything outside the known keys.
  ///
  /// UZ: Firestore'da (`ClassModel.dayOfWeek`) saqlanadigan kanonik kanji hafta kuni kaliti
  /// ('月'..'金') uchun mahalliylashtirilgan yorliq. Ma'lum kalitlardan tashqaridagi har qanday
  /// narsa uchun kiritilgan qiymatni o'zgarishsiz qaytaradi.
  static String localizedWeekday(String kanjiDay) {
    const kanjiOrder = ['月', '火', '水', '木', '金', '土', '日'];
    final i = kanjiOrder.indexOf(kanjiDay);
    return i == -1 ? kanjiDay : _weekdayLabels[i];
  }

  /// Stable `yyyy-MM-dd` cache key for "once per calendar day" logic
  /// (streaks, cached AI tips/weak-area analysis).
  ///
  /// UZ: "Har bir taqvim kunida bir marta" mantiqi (streak'lar, keshdagi AI maslahatlari/zaif sohalar
  /// tahlili) uchun barqaror `yyyy-MM-dd` kesh kaliti.
  static String dayKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static bool isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  /// Whole calendar days from [b] to [a] (positive when [a] is later),
  /// ignoring time of day. Both dates are projected onto UTC midnight first,
  /// so a DST change between them can't make a 24h-based `inDays` come out
  /// one day short (23h) or long (25h).
  ///
  /// UZ: Kun vaqtini hisobga olmagan holda, [b] dan [a] gacha bo'lgan to'liq taqvim kunlari ([a] keyinroq
  /// bo'lsa musbat). Ikkala sana ham avval UTC yarim kechasiga proyeksiyalanadi, shuning uchun ular
  /// orasidagi DST o'zgarishi 24 soatga asoslangan `inDays` ni bir kunga qisqa (23 soat) yoki uzun
  /// (25 soat) qilib qo'ya olmaydi.
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
    // Far-off dates show the date itself — "1 week later" would be wrong.
    // UZ: Uzoq sanalar sananing o'zini ko'rsatadi — "1 week later" noto'g'ri bo'lardi.
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
