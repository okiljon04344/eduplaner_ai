import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'models/school.dart';
import 'models/school_notice.dart';

/// Read-only access to the server-synced school timetable. Rules allow only
/// `get` on a doc, so every watch listens to single doc refs; a permission
/// error (missing or foreign doc) is treated as "no data", never a stream error.
class SchoolRepository {
  SchoolRepository({FirebaseFirestore? firestore, FirebaseDatabase? database})
      : _db = firestore ?? FirebaseFirestore.instance,
        _rtdbOverride = database;

  final FirebaseFirestore _db;
  final FirebaseDatabase? _rtdbOverride;

  /// Lazy so tests that only touch Firestore never need an RTDB instance.
  FirebaseDatabase get _rtdb => _rtdbOverride ?? FirebaseDatabase.instance;

  /// RTDB keys can't hold `. $ # [ ] /`; must match `rtdbKey` in overrides.js.
  static String rtdbKey(String s) => s.replaceAll(RegExp(r'[.$#\[\]/]'), ',');

  /// 既読 receipts of one announced slot: `{uid: serverTime}`; must match
  /// `readsPath` in overrides.js, which clears it on every new announcement.
  static String readsPath(String domain, int grade, String course, String date, String period) =>
      'reads/${rtdbKey(domain)}/${rtdbKey('${grade}_$course')}/${rtdbKey('${date}_$period')}';

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
      await Future.wait(changes.map((c) => _rtdb
          .ref('${readsPath(domain, grade, course, c.date, c.period)}/$uid')
          .set(ServerValue.timestamp)));
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
      required String period}) async* {
    try {
      await for (final e
          in _rtdb.ref(readsPath(domain, grade, course, _ymd(date, '-'), period)).onValue) {
        yield e.snapshot.children.length;
      }
    } catch (e) {
      debugPrint('watchReadCount failed: $e');
      yield 0;
    }
  }

  /// `reads/{domain}/notices/{id}`; must match `noticeReadsPath` in notices.js.
  static String noticeReadsPath(String domain, String id) =>
      'reads/${rtdbKey(domain)}/notices/${rtdbKey(id)}';

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
      await _rtdb.ref('${noticeReadsPath(domain, id)}/$uid').set(ServerValue.timestamp);
    } catch (e) {
      debugPrint('markNoticeRead failed: $e');
    }
  }

  /// How many students opened notice [id]; 0 on error.
  Stream<int> watchNoticeReadCount({required String domain, required String id}) async* {
    try {
      await for (final e in _rtdb.ref(noticeReadsPath(domain, id)).onValue) {
        yield e.snapshot.children.length;
      }
    } catch (e) {
      debugPrint('watchNoticeReadCount failed: $e');
      yield 0;
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
