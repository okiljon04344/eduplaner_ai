import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/clock_provider.dart';
import '../../core/services/notification_service.dart';
import '../auth/models/school_type.dart';
import '../auth/providers/auth_provider.dart';
import 'models/school.dart';
import 'models/school_assignment.dart';
import 'models/school_notice.dart';
import 'school_repository.dart';

/// School a pilot test account was let into by the admin (setSchoolTester).
///
/// UZ: Administrator tomonidan tajriba-sinov hisobi kiritilgan maktab (setSchoolTester).
final testerDomainProvider = StreamProvider<String?>((ref) {
  ref.watch(authStateProvider);
  final user = FirebaseAuth.instance.currentUser;
  final email = user?.email;
  if (email == null || !user!.emailVerified) return Stream.value(null);
  return ref.watch(schoolRepositoryProvider).watchTesterDomain(email);
});

/// The signed-in user's school domain: the test-account school if the admin
/// listed them, else their verified email domain. Null when unknown.
///
/// UZ: Tizimga kirgan foydalanuvchining maktab domeni: agar administrator ularni ro'yxatga olgan
/// bo'lsa, test hisobi maktabi, aks holda tasdiqlangan email domeni. Noma'lum bo'lsa null.
final schoolDomainProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(testerDomainProvider).valueOrNull ??
      SchoolRepository.domainOf(FirebaseAuth.instance.currentUser);
});

/// Pilot test accounts of the school (admin screen only).
///
/// UZ: Maktabning tajriba-sinov hisoblari (faqat administrator ekrani).
final schoolTestersProvider = StreamProvider<List<String>>((ref) {
  final domain = ref.watch(schoolDomainProvider);
  if (domain == null || !ref.watch(schoolRoleProvider).admin) return Stream.value(const []);
  return ref.watch(schoolRepositoryProvider).watchTesters(domain);
});

/// Streams [SchoolInfo] configuration for the authenticated user's school domain.
///
/// UZ: Autentifikatsiyadan o'tgan foydalanuvchining maktab domeni uchun [SchoolInfo]
/// konfiguratsiyasini oqim sifatida uzatadi.
final schoolInfoProvider = StreamProvider<SchoolInfo?>((ref) {
  final domain = ref.watch(schoolDomainProvider);
  if (domain == null) return Stream.value(null);
  return ref.watch(schoolRepositoryProvider).watchSchool(domain);
});

/// The user's grade/course, only when it matches the synced school.
///
/// UZ: Foydalanuvchining sinfi/kursi, faqat sinxronlangan maktabga mos kelganda.
final schoolClassProvider = Provider<({int grade, String course})?>((ref) {
  final info = ref.watch(schoolInfoProvider).valueOrNull;
  final user = ref.watch(currentUserProvider);
  if (info == null || user == null) return null;
  final grade = SchoolType.parseGrade(user.grade);
  final course = user.course;
  if (grade == null || course == null || !info.courses.contains(course)) {
    return null;
  }
  return (grade: grade, course: course);
});

/// Streams schedule changes and cancellations affecting the current student's enrolled grade and course.
///
/// UZ: Hozirgi o'quvchi o'qiydigan sinf va kursga taalluqli dars jadvali o'zgarishlari va
/// bekor qilishlarni oqim sifatida uzatadi.
final schoolChangesProvider = StreamProvider.autoDispose<List<SchoolChange>>((ref) {
  final domain = ref.watch(schoolDomainProvider);
  final cls = ref.watch(schoolClassProvider);
  if (domain == null || cls == null) return Stream.value(const []);
  return ref
      .watch(schoolRepositoryProvider)
      .watchChanges(domain: domain, grade: cls.grade, course: cls.course);
});

/// Keyed by the week's Monday; callers should pass a date-only `DateTime(y, m, d)`
/// so equal weeks share one provider. autoDispose drops the 5 doc listeners
/// when the week leaves the screen.
///
/// UZ: Haftaning dushanbasi bo'yicha kalitlanadi; teng haftalar bitta provayderdan foydalanishi
/// uchun chaqiruvchilar faqat sanani o'z ichiga olgan `DateTime(y, m, d)` uzatishi lozim. Hafta
/// ekrandan chiqqanda autoDispose 5 ta hujjat tinglovchisini to'xtatadi.
final schoolWeekProvider = StreamProvider.autoDispose
    .family<Map<String, SchoolDay>, DateTime>((ref, weekStart) {
  final domain = ref.watch(schoolDomainProvider);
  final cls = ref.watch(schoolClassProvider);
  if (domain == null || cls == null) return Stream.value(const {});
  return ref.watch(schoolRepositoryProvider).watchWeek(
      domain: domain, grade: cls.grade,
      course: cls.course,
      weekStart: DateTime(weekStart.year, weekStart.month, weekStart.day));
});

/// Every recent notice of the school (teacher screen).
///
/// UZ: Maktabning barcha so'nggi bildirishnomalari (o'qituvchi ekrani).
final schoolNoticesProvider = StreamProvider.autoDispose<List<SchoolNotice>>((ref) {
  final domain = ref.watch(schoolDomainProvider);
  if (domain == null) return Stream.value(const []);
  return ref.watch(schoolRepositoryProvider).watchNotices(domain);
});

/// Notices addressed to the student's own class or whole grade.
///
/// UZ: O'quvchining o'z sinfiga yoki butun bosqichiga yo'naltirilgan bildirishnomalar.
final myNoticesProvider = Provider.autoDispose<List<SchoolNotice>>((ref) {
  final cls = ref.watch(schoolClassProvider);
  if (cls == null) return const [];
  final all = ref.watch(schoolNoticesProvider).valueOrNull ?? const [];
  return [for (final n in all) if (n.appliesTo(cls.grade, cls.course)) n];
});

/// 既読 count of one notice (teacher screen).
///
/// UZ: Bitta bildirishnomaning 既読 soni (o'qituvchi ekrani).
final noticeReadCountProvider = StreamProvider.autoDispose.family<int, String>((ref, id) {
  final domain = ref.watch(schoolDomainProvider);
  if (domain == null) return Stream.value(0);
  return ref.watch(schoolRepositoryProvider).watchNoticeReadCount(domain: domain, id: id);
});

/// Every recent distributed assignment of the school (teacher screen).
///
/// UZ: Maktabning barcha so'nggi tarqatilgan topshiriqlari (o'qituvchi ekrani).
final schoolAssignmentsProvider = StreamProvider.autoDispose<List<SchoolAssignment>>((ref) {
  final domain = ref.watch(schoolDomainProvider);
  if (domain == null) return Stream.value(const []);
  return ref.watch(schoolRepositoryProvider).watchAssignments(domain);
});

/// Student progress list for distributed assignment [sourceId] (teacher screen).
///
/// UZ: Tarqatilgan [sourceId] topshirig'i uchun o'quvchilar progress ro'yxati (o'qituvchi ekrani).
final assignmentProgressProvider = StreamProvider.autoDispose
    .family<List<AssignmentProgress>, String>((ref, sourceId) {
  final domain = ref.watch(schoolDomainProvider);
  if (domain == null) return Stream.value(const []);
  return ref.watch(schoolRepositoryProvider).watchAssignmentProgress(domain, sourceId);
});

/// Ids of notices this device has opened (unread dot). Local only: the
/// teacher-side 既読 count lives in RTDB.
///
/// UZ: Ushbu qurilma ochgan bildirishnomalar identifikatorlari (o'qilmaganlik nuqtasi).
/// Faqat lokal: o'qituvchi tomonidagi 既読 hisobi RTDB da saqlanadi.
class SeenNoticesNotifier extends Notifier<Set<String>> {
  static const _key = 'seen_notice_ids';
  static const _max = 100;

  @override
  Set<String> build() {
    unawaited(_load());
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = {...state, ...prefs.getStringList(_key) ?? const []};
    } catch (e) {
      debugPrint('Seen notices load failed: $e');
    }
  }

  Future<void> markSeen(String id) async {
    if (state.contains(id)) return;
    final next = [...state, id];
    // ponytail: drops the oldest-inserted ids past 100; notices list is 30.
    // UZ: ponytail: 100 tadan oshganda eng eski kiritilgan id larni tashlaydi; bildirishnomalar ro'yxati 30 ta.
    state = next.skip(next.length > _max ? next.length - _max : 0).toSet();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, state.toList());
    } catch (e) {
      debugPrint('Seen notices save failed: $e');
    }
  }
}

/// Provides and persists the set of school notice IDs marked as read by the user.
///
/// UZ: Foydalanuvchi tomonidan o'qilgan deb belgilangan maktab bildirishnomalari id lari
/// to'plamini taqdim etadi va saqlaydi.
final seenNoticesProvider = NotifierProvider<SeenNoticesNotifier, Set<String>>(SeenNoticesNotifier.new);

/// Teacher/admin role of the signed-in user in their school (§5.3).
///
/// UZ: Tizimga kirgan foydalanuvchining o'z maktabidagi o'qituvchi/admin roli (§5.3).
final schoolRoleProvider = Provider<({bool teacher, bool admin})>((ref) {
  final info = ref.watch(schoolInfoProvider).valueOrNull;
  ref.watch(authStateProvider);
  final user = FirebaseAuth.instance.currentUser;
  if (info == null || user == null) return (teacher: false, admin: false);
  return (teacher: info.isTeacher(user.uid, user.email), admin: info.isAdmin(user.uid));
});

typedef SchoolClassWeek = ({int grade, String course, DateTime weekStart});

/// Any class's week, for the teacher screen. Pass a date-only Monday.
///
/// UZ: O'qituvchi ekrani uchun har qanday sinfning haftasi. Faqat sanali dushanba kunini uzating.
final schoolClassWeekProvider = StreamProvider.autoDispose
    .family<Map<String, SchoolDay>, SchoolClassWeek>((ref, k) {
  final domain = ref.watch(schoolDomainProvider);
  if (domain == null) return Stream.value(const {});
  return ref.watch(schoolRepositoryProvider).watchWeek(
      domain: domain, grade: k.grade, course: k.course, weekStart: k.weekStart);
});

/// Automatically schedules local reminders for the current week's school
/// lessons when school timetable data is available and notifications are enabled.
///
/// UZ: Maktab dars jadvali mavjud bo'lganda va bildirishnomalar yoqilganida joriy haftaning
/// maktab darslari uchun mahalliy eslatmalarni avtomatik tarzda rejalashtiradi.
final schoolReminderSyncProvider = Provider<void>((ref) {
  if (!NotificationService.isEnabled) return;
  final today = ref.watch(todayProvider).valueOrNull ?? DateTime.now();
  final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
  final periods = ref.watch(schoolInfoProvider).valueOrNull?.periods ?? const [];

  ref.listen<AsyncValue<Map<String, SchoolDay>>>(
    schoolWeekProvider(monday),
    (prev, next) {
      if (!NotificationService.isEnabled) return;
      final week = next.valueOrNull;
      if (week != null && periods.isNotEmpty) {
        unawaited(NotificationService.scheduleSchoolReminders(week, periods));
      }
    },
    fireImmediately: true,
  );
});

/// True while a student-facing school stream is failing to load; drives
/// [SchoolLoadErrorBanner].
///
/// UZ: O'quvchiga ko'rinadigan maktab oqimlaridan biri yuklanmayotgan paytda true;
/// [SchoolLoadErrorBanner] shunga qarab ko'rinadi.
final schoolLoadFailedProvider = Provider<bool>((ref) {
  final repo = ref.watch(schoolRepositoryProvider);
  void listener() => ref.invalidateSelf();
  repo.loadFailed.addListener(listener);
  ref.onDispose(() => repo.loadFailed.removeListener(listener));
  return repo.loadFailed.value;
});
