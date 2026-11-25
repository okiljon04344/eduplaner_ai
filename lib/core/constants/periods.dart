/// An (hour, minute) wall-clock time.
///
/// UZ: (soat, daqiqa) ko'rinishidagi devor soati vaqti.
typedef Hm = (int hour, int minute);

/// Single source of truth for class period clock times (periods 1-6, 90-minute
/// blocks). [ClassModel] only stores the period index; the timetable cards,
/// the home cards, the status date logic and the local reminders all read the
/// times from here so they can never drift apart.
///
/// UZ: Dars juftligi (period) vaqtlari uchun yagona haqiqat manbai (1-6 juftliklar, 90 daqiqalik
/// bloklar). [ClassModel] faqat juftlik indeksini saqlaydi; dars jadvali kartalari, asosiy ekran
/// kartalari, holat sanasi mantiqi va mahalliy eslatmalarning barchasi vaqtlarni shu yerdan o'qiydi,
/// shuning uchun ular hech qachon bir-biridan farq qilmaydi.
const Map<int, ({Hm start, Hm end})> kPeriodTimes = {
  1: (start: (9, 0), end: (10, 30)),
  2: (start: (10, 40), end: (12, 10)),
  3: (start: (13, 0), end: (14, 30)),
  4: (start: (14, 40), end: (16, 10)),
  5: (start: (16, 20), end: (17, 50)),
  6: (start: (18, 0), end: (19, 30)),
};

/// Zero-padded `HH:MM` string for [t].
///
/// UZ: [t] uchun nollar bilan to'ldirilgan `HH:MM` satri.
String formatHm(Hm t) =>
    '${t.$1.toString().padLeft(2, '0')}:${t.$2.toString().padLeft(2, '0')}';

/// Display `HH:MM` strings for [period], or `--:--` for an unknown period.
///
/// UZ: [period] uchun `HH:MM` ko'rinishidagi ko'rsatish satrlari, yoki noma'lum juftlik uchun `--:--`.
({String start, String end}) periodTimeLabels(int period) {
  final t = kPeriodTimes[period];
  if (t == null) return (start: '--:--', end: '--:--');
  return (start: formatHm(t.start), end: formatHm(t.end));
}

/// Local start of [period] on the calendar day of [day], or null if unknown.
///
/// UZ: [day] taqvim kunida [period] ning mahalliy boshlanish vaqti, yoki noma'lum bo'lsa null.
DateTime? periodStartOn(DateTime day, int period) {
  final t = kPeriodTimes[period]?.start;
  return t == null ? null : DateTime(day.year, day.month, day.day, t.$1, t.$2);
}

/// Local end of [period] on the calendar day of [day], or null if unknown.
///
/// UZ: [day] taqvim kunida [period] ning mahalliy tugash vaqti, yoki noma'lum bo'lsa null.
DateTime? periodEndOn(DateTime day, int period) {
  final t = kPeriodTimes[period]?.end;
  return t == null ? null : DateTime(day.year, day.month, day.day, t.$1, t.$2);
}
