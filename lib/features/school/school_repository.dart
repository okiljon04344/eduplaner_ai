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
class SchoolRepository {
  SchoolRepository({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // 既読 receipts: `school_reads/{domain}_{target}_{uid}`. Rules let a student
  // write and read only their own doc; teachers list a target's docs to count
  // them. Targets must match `readTarget`/`noticeReadTarget` in overrides.js.
  static String _readKey(String s) => s.replaceAll('/', ',');

  /// Target of one announced lesson change ([date] is `YYYY-MM-DD`).
  static String readTarget(int grade, String course, String date, String period) =>
      _readKey('o_${grade}_${course}_${date}_$period');

  /// Target of one notice.
  static String noticeReadTarget(String id) => _readKey('n_$id');

  Future<void> _markRead(String domain, String target, String uid) =>
      _db.collection('school_reads').doc('${domain}_${target}_$uid').set(
          {'domain': domain, 'target': target, 'uid': uid, 'at': FieldValue.serverTimestamp()});

  /// Number of distinct readers of [target]; 0 on error (e.g. not a teacher).
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
  Stream<T> _watchDoc<T>(
      DocumentReference<Map<String, dynamic>> ref, T Function(DocumentSnapshot) map, T empty) async* {
    try {
      await for (final s in ref.snapshots()) {
        yield s.exists ? map(s) : empty;
      }
    } catch (e) {
      debugPrint('School doc ${ref.path} unreadable: $e');
      yield empty;
    }
  }

  /// School domain a pilot test account (e.g. Gmail) was let into, or null.
  Stream<String?> watchTesterDomain(String email) => _watchDoc<String?>(
      _db.collection('school_testers').doc(email.toLowerCase()),
      (s) => (s.data() as Map?)?['domain'] as String?,
      null);

  /// Pilot test accounts of [domain]. Admin-only doc: these are personal
  /// addresses, so they are kept out of the student-readable school doc.
  Stream<List<String>> watchTesters(String domain) => _watchDoc<List<String>>(
      _db.collection('school_admin').doc(domain),
      (s) => (((s.data() as Map?)?['testers'] as List?) ?? const []).whereType<String>().toList(),
      const []);

  Stream<SchoolInfo?> watchSchool(String domain) => _watchDoc<SchoolInfo?>(
      _db.collection('schools').doc(domain), SchoolInfo.fromFirestore, null);

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
      );

  /// Records that [uid] opened these changes. Best effort: a failure only
  /// leaves the teacher's 既読 count low.
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
  Stream<int> watchReadCount(
      {required String domain,
      required int grade,
      required String course,
      required DateTime date,
      required String period}) =>
      _watchReadCount(domain, readTarget(grade, course, _ymd(date, '-'), period));

  /// The school's latest notices, newest first (rules check the domain of
  /// every doc, so the query must filter by it). Empty on error.
  Stream<List<SchoolNotice>> watchNotices(String domain, {int limit = 30}) async* {
    try {
      await for (final s in _db
          .collection('school_notices')
          .where('domain', isEqualTo: domain)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()) {
        yield s.docs.map(SchoolNotice.fromFirestore).toList();
      }
    } catch (e) {
      debugPrint('watchNotices failed: $e');
      yield const [];
    }
  }

  /// Records that [uid] opened notice [id]. Best effort, like [markRead].
  Future<void> markNoticeRead({required String domain, required String id, required String uid}) async {
    try {
      await _markRead(domain, noticeReadTarget(id), uid);
    } catch (e) {
      debugPrint('markNoticeRead failed: $e');
    }
  }

  /// How many students opened notice [id]; 0 on error.
  Stream<int> watchNoticeReadCount({required String domain, required String id}) =>
      _watchReadCount(domain, noticeReadTarget(id));

  /// Distributed assignments of the school, newest first. Empty on error.
  Stream<List<SchoolAssignment>> watchAssignments(String domain, {int limit = 30}) async* {
    try {
      await for (final s in _db
          .collection('school_assignments')
          .where('domain', isEqualTo: domain)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()) {
        yield s.docs.map(SchoolAssignment.fromFirestore).toList();
      }
    } catch (e) {
      debugPrint('watchAssignments failed: $e');
      yield const [];
    }
  }

  /// Student progress list for distributed assignment [sourceId]. Empty on error.
  /// Note: both 'domain' and 'sourceId' equality filters are strictly required
  /// by the security rules on `school_assignment_progress`.
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
          ).listen((day) {
            latest[key] = day;
            emit();
          }));
          subs.add(_watchDoc<Map<String, SchoolOverride>>(
            _db.collection('school_overrides').doc(id),
            SchoolOverride.itemsFromFirestore,
            const {},
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
