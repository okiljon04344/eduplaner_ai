import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/periods.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/clock_provider.dart';
import '../../core/services/functions_service.dart';
import '../../core/utils/date_helper.dart';
import 'models/school.dart';
import 'models/school_notice.dart';
import 'school_providers.dart';

// ============================================================================
// Pure models and functions (Firebase-independent for easy testing)
// ============================================================================

/// Represents a single lesson assigned to a teacher, binding calendar date, period,
/// class grade/course, and slot details.
///
/// UZ: Taqvim sanasi, dars soati, sinf bosqichi/kursi va katakcha tafsilotlarini
/// bog'lagan holda o'qituvchiga biriktirilgan bitta darsni ifodalaydi.
class TeacherLesson {
  final DateTime date;
  final SchoolPeriod period;
  final int grade;
  final String course;
  final SchoolSlot slot;

  const TeacherLesson({
    required this.date,
    required this.period,
    required this.grade,
    required this.course,
    required this.slot,
  });
}

bool isSlotMine(SchoolSlot slot, String teacherName) {
  if (teacherName.isEmpty) return false;
  return slot.teacher.contains(teacherName);
}

DateTime nextSchoolDay(DateTime date) {
  if (date.weekday == DateTime.friday) {
    return DateTime(date.year, date.month, date.day + 3);
  } else if (date.weekday == DateTime.saturday) {
    return DateTime(date.year, date.month, date.day + 2);
  } else {
    return DateTime(date.year, date.month, date.day + 1);
  }
}

DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

int hmToMinutes(Hm hm) => hm.$1 * 60 + hm.$2;

bool isCurrentLesson(TeacherLesson lesson, DateTime now) {
  if (lesson.date.year != now.year ||
      lesson.date.month != now.month ||
      lesson.date.day != now.day) {
    return false;
  }
  final nowMin = now.hour * 60 + now.minute;
  final startMin = hmToMinutes(lesson.period.start);
  final endMin = hmToMinutes(lesson.period.end);
  return startMin <= nowMin && nowMin < endMin;
}

bool isLessonDone(TeacherLesson lesson, DateTime now) {
  final lessonDateOnly = DateTime(lesson.date.year, lesson.date.month, lesson.date.day);
  final nowDateOnly = DateTime(now.year, now.month, now.day);
  if (lessonDateOnly.isBefore(nowDateOnly)) return true;
  if (lessonDateOnly.isAfter(nowDateOnly)) return false;
  final nowMin = now.hour * 60 + now.minute;
  final endMin = hmToMinutes(lesson.period.end);
  return endMin <= nowMin;
}

/// Associates a timetable schedule change with the targeted class grade and course.
///
/// UZ: Dars jadvalidagi o'zgarishni mo'ljallangan sinf bosqichi va kursi bilan bog'laydi.
class ClassChangeItem {
  final int grade;
  final String course;
  final SchoolChange change;

  const ClassChangeItem({
    required this.grade,
    required this.course,
    required this.change,
  });
}

/// Summarizes schedule adjustments across the current week, categorizing cancellations,
/// room changes, and makeup classes.
///
/// UZ: Joriy hafta davomidagi jadval o'zgarishlarini umumlashtiradi, bekor qilinganlar,
/// xona o'zgarishlari va qo'shimcha (makeup) darslarni toifalarga ajratadi.
class WeekChangesSummary {
  final int total;
  final int cancelledCount;
  final int roomChangeCount;
  final int makeupCount;
  final List<ClassChangeItem> recentItems;

  const WeekChangesSummary({
    this.total = 0,
    this.cancelledCount = 0,
    this.roomChangeCount = 0,
    this.makeupCount = 0,
    this.recentItems = const [],
  });
}

WeekChangesSummary summarizeWeekChanges({
  required List<ClassChangeItem> allChanges,
  required DateTime monday,
}) {
  final monDate = DateTime(monday.year, monday.month, monday.day);
  final friDate = DateTime(monDate.year, monDate.month, monDate.day + 4);

  final weekItems = <ClassChangeItem>[];
  int cancelled = 0;
  int roomChanges = 0;
  int makeups = 0;

  for (final item in allChanges) {
    final parts = item.change.date.split('-');
    if (parts.length != 3) continue;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) continue;
    final cDate = DateTime(y, m, d);
    if (cDate.isBefore(monDate) || cDate.isAfter(friDate)) continue;

    weekItems.add(item);
    final what = item.change.what;
    if (what == '休講') {
      cancelled++;
    } else if (what.startsWith('教室')) {
      roomChanges++;
    } else if (what == '補講') {
      makeups++;
    }
  }

  weekItems.sort((a, b) {
    if (a.change.at != null && b.change.at != null) {
      return b.change.at!.compareTo(a.change.at!);
    }
    if (a.change.at != null) return -1;
    if (b.change.at != null) return 1;
    return b.change.date.compareTo(a.change.date);
  });

  final recent = weekItems.take(2).toList();

  return WeekChangesSummary(
    total: weekItems.length,
    cancelledCount: cancelled,
    roomChangeCount: roomChanges,
    makeupCount: makeups,
    recentItems: recent,
  );
}

/// Tracks individual notice read reception alongside recipient group size and unread counts.
///
/// UZ: Qabul qiluvchilar guruhi hajmi va o'qilmaganlar soni bilan birga alohida e'lonning o'qilishini kuzatib boradi.
class NoticeReadItem {
  final SchoolNotice notice;
  final int reads;
  final int? size;

  const NoticeReadItem({
    required this.notice,
    required this.reads,
    this.size,
  });

  int get unread => (size != null && size! > reads) ? size! - reads : 0;
  double? get percent => (size != null && size! > 0) ? (reads / size!).clamp(0.0, 1.0) : null;
}

/// Aggregates notice readership metrics including overall read percentages and highest unread items.
///
/// UZ: Umumiy o'qilish foizlari va eng ko'p o'qilmagan elementlarni o'z ichiga olgan e'lonlar o'qilishi ko'rsatkichlarini jamlaydi.
class NoticesReadSummary {
  final List<NoticeReadItem> items;
  final int totalReads;
  final int? totalSize;
  final int? overallPercent;
  final NoticeReadItem? mostUnreadNotice;

  const NoticesReadSummary({
    this.items = const [],
    this.totalReads = 0,
    this.totalSize,
    this.overallPercent,
    this.mostUnreadNotice,
  });
}

int? calculateNoticeClassSize({
  required SchoolNotice notice,
  required Map<String, int> classSizes,
  required List<String> allCourses,
}) {
  if (classSizes.isEmpty) return null;
  if (notice.course != null) {
    return classSizes['${notice.grade}_${notice.course}'];
  }
  // course == null (whole grade): sum of that grade's courses
  // UZ: course == null (butun bosqich): ushbu bosqich kurslarining yig'indisi
  int sum = 0;
  bool foundAny = false;
  for (final c in allCourses) {
    final sz = classSizes['${notice.grade}_$c'];
    if (sz != null) {
      sum += sz;
      foundAny = true;
    }
  }
  return foundAny ? sum : null;
}

NoticesReadSummary calculateNoticesReadSummary(List<NoticeReadItem> items) {
  if (items.isEmpty) return const NoticesReadSummary();
  int totalReads = 0;
  int sizeSum = 0;
  bool hasSize = false;
  NoticeReadItem? maxUnreadNotice;
  int maxUnreadCount = 0;

  for (final item in items) {
    totalReads += item.reads;
    if (item.size != null && item.size! > 0) {
      hasSize = true;
      sizeSum += item.size!;
      final unread = item.size! - item.reads;
      if (unread > 0 && unread > maxUnreadCount) {
        maxUnreadCount = unread;
        maxUnreadNotice = item;
      }
    }
  }

  if (hasSize && sizeSum > 0) {
    final pct = ((totalReads / sizeSum) * 100).round();
    return NoticesReadSummary(
      items: items,
      totalReads: totalReads,
      totalSize: sizeSum,
      overallPercent: pct,
      mostUnreadNotice: maxUnreadNotice,
    );
  }

  return NoticesReadSummary(
    items: items,
    totalReads: totalReads,
    totalSize: null,
    overallPercent: null,
    mostUnreadNotice: maxUnreadNotice,
  );
}

// ============================================================================
// Riverpod Providers
// ============================================================================

/// Fetches a map of student enrollment totals keyed by class identifier via Cloud Functions.
///
/// UZ: Cloud Functions orqali sinf identifikatori bo'yicha kalitlangan talabalar soni xaritasini oladi.
final classSizesProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  try {
    final callable = FunctionsService.callable('getSchoolClassSizes');
    final res = await callable();
    final data = res.data;
    if (data is Map && data['sizes'] is Map) {
      final sizes = data['sizes'] as Map;
      return {
        for (final e in sizes.entries)
          if (e.key is String && e.value is num)
            e.key as String: (e.value as num).toInt(),
      };
    }
    return const {};
  } catch (e) {
    debugPrint('classSizesProvider error: $e');
    return const {};
  }
});

/// Provides sorted lessons scheduled for the authenticated teacher across today and the next school day.
///
/// UZ: Autentifikatsiyadan o'tgan o'qituvchi uchun bugun va keyingi o'quv kuniga rejalashtirilgan saralangan darslarni taqdim etadi.
final myTeacherLessonsProvider = Provider.autoDispose<List<TeacherLesson>>((ref) {
  final info = ref.watch(schoolInfoProvider).valueOrNull;
  final user = FirebaseAuth.instance.currentUser;
  if (info == null || user == null) return const [];
  final profile = info.profileOf(user.email);
  if (profile == null || profile.name.isEmpty) return const [];
  final teacherName = profile.name;

  final now = ref.watch(todayProvider).valueOrNull ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final nextDay = nextSchoolDay(today);

  final mondayToday = mondayOf(today);
  final mondayNext = mondayOf(nextDay);

  final weeksToWatch = {mondayToday, mondayNext};

  final todayKey = DateHelper.dayKey(today);
  final nextKey = DateHelper.dayKey(nextDay);

  final lessons = <TeacherLesson>[];

  for (final grade in info.grades) {
    for (final course in info.courses) {
      for (final wStart in weeksToWatch) {
        final week = ref.watch(
          schoolClassWeekProvider((grade: grade, course: course, weekStart: wStart)),
        ).valueOrNull;
        if (week == null) continue;

        for (final targetEntry in [(date: today, key: todayKey), (date: nextDay, key: nextKey)]) {
          final day = week[targetEntry.key];
          if (day == null) continue;

          for (final slot in day.slots) {
            if (isSlotMine(slot, teacherName)) {
              final period = info.periods.firstWhere(
                (p) => p.key == slot.period || p.label == slot.period,
                orElse: () => SchoolPeriod(
                  key: slot.period,
                  label: slot.period,
                  start: (0, 0),
                  end: (0, 0),
                ),
              );
              lessons.add(TeacherLesson(
                date: targetEntry.date,
                period: period,
                grade: grade,
                course: course,
                slot: slot,
              ));
            }
          }
        }
      }
    }
  }

  // Deduplicate
  // UZ: Takrorlanishlarni olib tashlash
  final seen = <String>{};
  final uniqueLessons = <TeacherLesson>[];
  for (final l in lessons) {
    final id = '${DateHelper.dayKey(l.date)}_${l.grade}_${l.course}_${l.period.key}_${l.slot.subject}';
    if (seen.add(id)) {
      uniqueLessons.add(l);
    }
  }

  uniqueLessons.sort((a, b) {
    final dateComp = a.date.compareTo(b.date);
    if (dateComp != 0) return dateComp;
    return hmToMinutes(a.period.start).compareTo(hmToMinutes(b.period.start));
  });

  return uniqueLessons;
});

/// Filters the teacher's lessons to only those scheduled for the current calendar day.
///
/// UZ: O'qituvchining darslarini faqat joriy taqvim kuniga rejalashtirilganlariga qarab filtrlaydi.
final todayTeacherLessonsProvider = Provider.autoDispose<List<TeacherLesson>>((ref) {
  final lessons = ref.watch(myTeacherLessonsProvider);
  final now = ref.watch(todayProvider).valueOrNull ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return [
    for (final l in lessons)
      if (l.date.year == today.year && l.date.month == today.month && l.date.day == today.day)
        l
  ];
});

/// Filters the teacher's lessons to only those occurring on the next instructional school day.
///
/// UZ: O'qituvchining darslarini faqat keyingi o'quv kunida bo'ladigan darslar bo'yicha filtrlaydi.
final nextDayTeacherLessonsProvider = Provider.autoDispose<List<TeacherLesson>>((ref) {
  final lessons = ref.watch(myTeacherLessonsProvider);
  final now = ref.watch(todayProvider).valueOrNull ?? DateTime.now();
  final nextDay = nextSchoolDay(DateTime(now.year, now.month, now.day));
  return [
    for (final l in lessons)
      if (l.date.year == nextDay.year && l.date.month == nextDay.month && l.date.day == nextDay.day)
        l
  ];
});

/// Resolves the teacher's lesson currently underway based on the active clock time.
///
/// UZ: Faol soat vaqtiga asoslanib hozirda o'tilayotgan o'qituvchining darsini aniqlaydi.
final currentTeacherLessonProvider = Provider.autoDispose<TeacherLesson?>((ref) {
  final todayLessons = ref.watch(todayTeacherLessonsProvider);
  final now = ref.watch(minuteTickProvider).valueOrNull ?? DateTime.now();
  for (final l in todayLessons) {
    if (isCurrentLesson(l, now)) return l;
  }
  return null;
});

/// Calculates daily lesson completion metrics and percentage progress for the teacher.
///
/// UZ: O'qituvchi uchun kunlik darslarni yakunlash ko'rsatkichlari va progress foizini hisoblaydi.
final todayTeacherLessonsProgressProvider =
    Provider.autoDispose<({int total, int done, double progress})>((ref) {
  final todayLessons = ref.watch(todayTeacherLessonsProvider);
  final now = ref.watch(minuteTickProvider).valueOrNull ?? DateTime.now();
  final total = todayLessons.length;
  int done = 0;
  for (final l in todayLessons) {
    if (isLessonDone(l, now)) done++;
  }
  final progress = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
  return (total: total, done: done, progress: progress);
});

/// Family stream provider watching schedule modifications for a specific grade and course.
///
/// UZ: Muayyan bosqich va kurs uchun jadval o'zgarishlarini kuzatuvchi family stream provayderi.
final classChangesStreamProvider = StreamProvider.autoDispose
    .family<List<SchoolChange>, ({int grade, String course})>((ref, arg) {
  final domain = ref.watch(schoolDomainProvider);
  if (domain == null) return Stream.value(const []);
  return ref
      .watch(schoolRepositoryProvider)
      .watchChanges(domain: domain, grade: arg.grade, course: arg.course);
});

/// Aggregates schedule changes across all grades and courses for the current school week.
///
/// UZ: Joriy o'quv haftasi uchun barcha bosqichlar va kurslar bo'yicha jadval o'zgarishlarini jamlaydi.
final weekChangesProvider = Provider.autoDispose<WeekChangesSummary>((ref) {
  final info = ref.watch(schoolInfoProvider).valueOrNull;
  if (info == null) return const WeekChangesSummary();
  final now = ref.watch(todayProvider).valueOrNull ?? DateTime.now();
  final monday = mondayOf(now);

  final allChanges = <ClassChangeItem>[];
  for (final grade in info.grades) {
    for (final course in info.courses) {
      final changes = ref
              .watch(classChangesStreamProvider((grade: grade, course: course)))
              .valueOrNull ??
          const [];
      for (final c in changes) {
        allChanges.add(ClassChangeItem(grade: grade, course: course, change: c));
      }
    }
  }

  return summarizeWeekChanges(allChanges: allChanges, monday: monday);
});

/// Computes read count summaries and student coverage for recent notices authored by the teacher.
///
/// UZ: O'qituvchi tomonidan yaratilgan so'nggi e'lonlar uchun o'qilganlar soni xulosalari va talabalar qamrovini hisoblaydi.
final myNoticesReadSummaryProvider = Provider.autoDispose<NoticesReadSummary>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  final info = ref.watch(schoolInfoProvider).valueOrNull;
  final allNotices = ref.watch(schoolNoticesProvider).valueOrNull ?? const [];
  final classSizes = ref.watch(classSizesProvider).valueOrNull ?? const {};

  if (user == null || info == null) return const NoticesReadSummary();

  final myNotices = [for (final n in allNotices) if (n.createdBy == user.uid) n];
  myNotices.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
  final latest3 = myNotices.take(3).toList();

  final items = <NoticeReadItem>[];
  for (final notice in latest3) {
    final reads = ref.watch(noticeReadCountProvider(notice.id)).valueOrNull ?? 0;
    final size = calculateNoticeClassSize(
      notice: notice,
      classSizes: classSizes,
      allCourses: info.courses,
    );
    items.add(NoticeReadItem(notice: notice, reads: reads, size: size));
  }

  return calculateNoticesReadSummary(items);
});
