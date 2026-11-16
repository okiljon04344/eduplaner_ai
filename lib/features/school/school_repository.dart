import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models/school.dart';
import 'models/school_assignment.dart';
import 'models/school_notice.dart';

/// Read-only access to the server-synced school timetable. Rules allow only
/// `get` on a doc, so every watch listens to single doc refs; a permission
/// error (missing or foreign doc) is treated as "no data", never a stream error.
///
/// UZ: Server bilan sinxronlangan maktab dars jadvaliga faqat o'qish uchun kirish. Qoidalar hujjatda
/// faqat `get` ga ruxsat beradi, shuning uchun har bir kuzatuv bitta hujjat havolalarini tinglaydi;
/// ruxsat xatosi (yetishmayotgan yoki begona hujjat) hech qachon oqim xatosi emas, "ma'lumot yo'q" deb qaraladi.
class SchoolRepository {
  SchoolRepository({FirebaseFirestore? firestore}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// True while at least one student-facing school stream is failing. The
  /// streams still yield an empty value so the app keeps working; this lets
  /// the UI say why the screen is empty.
  ///
  /// UZ: O'quvchiga ko'rinadigan maktab oqimlaridan kamida bittasi ishlamayotgan paytda true.
  /// Oqimlar baribir bo'sh qiymat beradi va ilova ishlashda davom etadi; bu esa ekran nega
  /// bo'shligini UI'da aytish imkonini beradi.
  final ValueNotifier<bool> loadFailed = ValueNotifier(false);

  // Failing sources by collection name, so one stream recovering does not
  // hide another that is still failing.
  // ponytail: a source that fails and is never listened to again (another
  // user signs in on the same run) stays set; clear on auth change if seen.
  // UZ: Ishlamayotgan manbalar kolleksiya nomi bo'yicha saqlanadi, shunda bitta oqim tiklanishi
  // hali ishlamayotgan boshqasini yashirib qo'ymaydi.
  // ponytail: xato bergan va qayta tinglanmagan manba (shu ishga tushirishda boshqa foydalanuvchi
  // kirsa) belgilanganicha qoladi; kuzatilsa, auth o'zgarganda tozalash kerak.
  final _failedSources = <String>{};

  void _track(String source, bool failed) {
    failed ? _failedSources.add(source) : _failedSources.remove(source);
    loadFailed.value = _failedSources.isNotEmpty;
  }

  // 既読 receipts: `school_reads/{domain}_{target}_{uid}`. Rules let a student
  // write and read only their own doc; teachers list a target's docs to count
  // them. Targets must match `readTarget`/`noticeReadTarget` in overrides.js.
  // UZ: 既読 kvitansiyalari: `school_reads/{domain}_{target}_{uid}`. Qoidalar talabaga faqat o'zining
  // hujjatini yozish va o'qishga ruxsat beradi; o'qituvchilar ularni sanash uchun nishon hujjatlarini
  // ro'yxatlaydi. Nishonlar overrides.js dagi `readTarget`/`noticeReadTarget` bilan mos kelishi kerak.
  static String _readKey(String s) => s.replaceAll('/', ',');

  /// Target of one announced lesson change ([date] is `YYYY-MM-DD`).
  ///
  /// UZ: E'lon qilingan bitta dars o'zgarishining nishoni ([date] - `YYYY-MM-DD`).
  static String readTarget(int grade, String course, String date, String period) =>
      _readKey('o_${grade}_${course}_${date}_$period');

  /// Target of one notice.
  ///
  /// UZ: Bitta bildirishnomaning nishoni.
  static String noticeReadTarget(String id) => _readKey('n_$id');

  Future<void> _markRead(String domain, String target, String uid) =>
      _db.collection('school_reads').doc('${domain}_${target}_$uid').set(
          {'domain': domain, 'target': target, 'uid': uid, 'at': FieldValue.serverTimestamp()});

  /// Number of distinct readers of [target]; 0 on error (e.g. not a teacher).
  ///
  /// UZ: [target] ning alohida o'quvchilari soni; xatolik yuz berganda 0 (masalan, o'qituvchi bo'lmaganda).
  Stream<int> _watchReadCount(String domain, String target) async* {
    try {
      await for (final s in _db
          .collection('school_reads')
          .where('domain', isEqualTo: domain)
          .where('target', isEqualTo: target)
          .snapshots()) {
        yield s.size;
      }
    } catch (e) {
      debugPrint('watchReadCount failed: $e');
      yield 0;
    }
  }

  /// Lowercase part after the last '@' when [emailVerified] and non-empty.
  ///
  /// UZ: [emailVerified] va bo'sh bo'lmaganda oxirgi '@' dan keyingi kichik harflardagi qism.
  static String? domainFrom(String? email, bool emailVerified) {
    if (!emailVerified || email == null) return null;
    final at = email.lastIndexOf('@');
    if (at < 0 || at == email.length - 1) return null;
    return email.substring(at + 1).toLowerCase();
  }

  static String? domainOf(User? user) =>
      domainFrom(user?.email, user?.emailVerified ?? false);

  static String _ymd(DateTime d, String sep) =>
      '${d.year.toString().padLeft(4, '0')}$sep'
      '${d.month.toString().padLeft(2, '0')}$sep'
      '${d.day.toString().padLeft(2, '0')}';

  static String dayId(String domain, int grade, String course, DateTime date) =>
      '${domain}_${grade}_${course}_${_ymd(date, '')}';

  /// Emits the mapped doc, or [empty] for a missing doc or any error.
  ///
  /// UZ: Hujjat xaritaga kiritilganini chiqaradi, yoki yetishmayotgan hujjat yoki har qanday xatolik uchun [empty] chiqaradi.
  Stream<T> _watchDoc<T>(
      DocumentReference<Map<String, dynamic>> ref, T Function(DocumentSnapshot) map, T empty,
      {bool trackFailure = false}) async* {
    try {
      await for (final s in ref.snapshots()) {
        if (trackFailure) _track(ref.parent.id, false);
        yield s.exists ? map(s) : empty;
      }
    } catch (e) {
      if (trackFailure) _track(ref.parent.id, true);
      debugPrint('School doc ${ref.path} unreadable: $e');
      yield empty;
    }
  }

  /// School domain a pilot test account (e.g. Gmail) was let into, or null.
  ///
  /// UZ: Pilot test hisobi (masalan, Gmail) kiritilgan maktab domeni, yoki null.
  Stream<String?> watchTesterDomain(String email) => _watchDoc<String?>(
      _db.collection('school_testers').doc(email.toLowerCase()),
      (s) => (s.data() as Map?)?['domain'] as String?,
      null);

  /// Pilot test accounts of [domain]. Admin-only doc: these are personal
  /// addresses, so they are kept out of the student-readable school doc.
  ///
  /// UZ: [domain] ning pilot test hisoblari. Faqat admin uchun hujjat: bular shaxsiy manzillar,
  /// shuning uchun ular talabalar o'qiy oladigan maktab hujjatidan tashqarida saqlanadi.
  Stream<List<String>> watchTesters(String domain) => _watchDoc<List<String>>(
      _db.collection('school_admin').doc(domain),
      (s) => (((s.data() as Map?)?['testers'] as List?) ?? const []).whereType<String>().toList(),
      const []);

  Stream<SchoolInfo?> watchSchool(String domain) => _watchDoc<SchoolInfo?>(
      _db.collection('schools').doc(domain), SchoolInfo.fromFirestore, null,
      trackFailure: true);

  Stream<List<SchoolChange>> watchChanges(
          {required String domain, required int grade, required String course}) =>
      _watchDoc<List<SchoolChange>>(
        _db.collection('school_changes').doc('${domain}_${grade}_$course'),
        (s) {
          final items = ((s.data() as Map?)?['items']);
          return items is List
              ? items.whereType<Map>().map(SchoolChange.fromMap).toList()
              : const <SchoolChange>[];
        },
        const [],
        trackFailure: true,
      );

  /// Records that [uid] opened these changes. Best effort: a failure only
  /// leaves the teacher's 既読 count low.
  ///
  /// UZ: [uid] ushbu o'zgarishlarni ochganini qayd qiladi. Imkon qadar urinish (best effort):
  /// nosozlik faqat o'qituvchining 既読 sonini past qilib qoldiradi.
  Future<void> markRead(
      {required String domain,
      required int grade,
      required String course,
      required String uid,
      required Iterable<SchoolChange> changes}) async {
    try {
      await Future.wait(
          changes.map((c) => _markRead(domain, readTarget(grade, course, c.date, c.period), uid)));
    } catch (e) {
      debugPrint('markRead failed: $e');
    }
  }

  /// How many students opened the announcement for [date] ([period]); 0 on error.
  ///
  /// UZ: [date] ([period]) uchun e'lonni qancha talaba ochgani; xatolik yuz berganda 0.
  Stream<int> watchReadCount(
      {required String domain,
      required int grade,
      required String course,
      required DateTime date,
      required String period}) =>
      _watchReadCount(domain, readTarget(grade, course, _ymd(date, '-'), period));

  /// The school's latest notices, newest first (rules check the domain of
  /// every doc, so the query must filter by it). Empty on error.
  ///
  /// UZ: Maktabning so'nggi bildirishnomalari, yangilari oldin (qoidalar har bir hujjatning domenini
  /// tekshiradi, shuning uchun so'rov u bo'yicha filtrlashi kerak). Xatolik yuz berganda bo'sh.
  Stream<List<SchoolNotice>> watchNotices(String domain, {int limit = 30}) async* {
    try {
      await for (final s in _db
          .collection('school_notices')
          .where('domain', isEqualTo: domain)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()) {
        _track('school_notices', false);
        yield s.docs.map(SchoolNotice.fromFirestore).toList();
      }
    } catch (e) {
      _track('school_notices', true);
      debugPrint('watchNotices failed: $e');
      yield const [];
    }
  }

  /// Records that [uid] opened notice [id]. Best effort, like [markRead].
  ///
  /// UZ: [uid] [id] bildirishnomasini ochganini qayd qiladi. [markRead] kabi imkon qadar urinish (best effort).
  Future<void> markNoticeRead({required String domain, required String id, required String uid}) async {
    try {
      await _markRead(domain, noticeReadTarget(id), uid);
    } catch (e) {
      debugPrint('markNoticeRead failed: $e');
    }
  }

  /// How many students opened notice [id]; 0 on error.
  ///
  /// UZ: [id] bildirishnomasini qancha talaba ochgani; xatolik yuz berganda 0.
  Stream<int> watchNoticeReadCount({required String domain, required String id}) =>
      _watchReadCount(domain, noticeReadTarget(id));

  /// Distributed assignments of the school, newest first. Empty on error.
  ///
  /// UZ: Maktabning tarqatilgan topshiriqlari, eng yangilari birinchi. Xatolik yuz berganda bo'sh.
  Stream<List<SchoolAssignment>> watchAssignments(String domain, {int limit = 30}) async* {
    try {
      await for (final s in _db
          .collection('school_assignments')
          .where('domain', isEqualTo: domain)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()) {
        _track('school_assignments', false);
        yield s.docs.map(SchoolAssignment.fromFirestore).toList();
      }
    } catch (e) {
      _track('school_assignments', true);
      debugPrint('watchAssignments failed: $e');
      yield const [];
    }
  }

  /// Student progress list for distributed assignment [sourceId]. Empty on error.
  /// Note: both 'domain' and 'sourceId' equality filters are strictly required
  /// by the security rules on `school_assignment_progress`.
  ///
  /// UZ: Tarqatilgan [sourceId] topshirig'i uchun talabalar progress ro'yxati. Xatolik yuz berganda bo'sh.
  /// Note: ham 'domain', ham 'sourceId' tenglik filtrlari `school_assignment_progress`
  /// xavfsizlik qoidalari tomonidan qat'iy talab qilinadi.
  Stream<List<AssignmentProgress>> watchAssignmentProgress(String domain, String sourceId) async* {
    try {
      await for (final s in _db
          .collection('school_assignment_progress')
          .where('domain', isEqualTo: domain)
          .where('sourceId', isEqualTo: sourceId)
          .snapshots()) {
        yield s.docs.map(AssignmentProgress.fromFirestore).toList();
      }
    } catch (e) {
      debugPrint('watchAssignmentProgress failed: $e');
      yield const [];
    }
  }

  /// Mon-Fri docs of the week starting [weekStart], keyed `YYYY-MM-DD`, with
  /// teacher inputs (`school_overrides`) applied; only days with lessons are
  /// present. Emits once every day doc and override doc has reported.
  ///
  /// UZ: [weekStart] dan boshlanadigan haftaning dushanba-juma hujjatlari, `YYYY-MM-DD` kaliti bilan,
  /// o'qituvchi kiritmalari (`school_overrides`) qo'llangan holda; faqat darslari bor kunlar mavjud.
  /// Har bir kun hujjati va override hujjati xabar bergandan keyin bir marta chiqaradi.
  Stream<Map<String, SchoolDay>> watchWeek({
    required String domain,
    required int grade,
    required String course,
    required DateTime weekStart,
  }) {
    final days = [
      for (var i = 0; i < 5; i++)
        DateTime(weekStart.year, weekStart.month, weekStart.day + i)
    ];
    final latest = <String, SchoolDay?>{};
    final overrides = <String, Map<String, SchoolOverride>>{};
    final subs = <StreamSubscription>[];
    late final StreamController<Map<String, SchoolDay>> ctrl;
    void emit() {
      if (latest.length < days.length || overrides.length < days.length) return;
      ctrl.add({
        for (final e in latest.entries)
          if (applyOverrides(e.value, overrides[e.key] ?? const {}, e.key) case final day?)
            e.key: day
      });
    }

    ctrl = StreamController<Map<String, SchoolDay>>(
      onListen: () {
        for (final d in days) {
          final key = _ymd(d, '-');
          final id = dayId(domain, grade, course, d);
          subs.add(_watchDoc<SchoolDay?>(
            _db.collection('school_days').doc(id),
            SchoolDay.fromFirestore,
            null,
            trackFailure: true,
          ).listen((day) {
            latest[key] = day;
            emit();
          }));
          subs.add(_watchDoc<Map<String, SchoolOverride>>(
            _db.collection('school_overrides').doc(id),
            SchoolOverride.itemsFromFirestore,
            const {},
            trackFailure: true,
          ).listen((items) {
            overrides[key] = items;
            emit();
          }));
        }
      },
      onCancel: () async {
        await Future.wait(subs.map((s) => s.cancel()));
        await ctrl.close();
      },
    );
    return ctrl.stream;
  }
}
