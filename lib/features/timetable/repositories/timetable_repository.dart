import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/class_model.dart';

class TimetableRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference get _col => _db.collection('timetables');

  List<ClassModel> _classes(QuerySnapshot s) =>
      s.docs.map(ClassModel.fromFirestore).toList();

  /// The user's classes ordered by period. In a group the group's shared classes
  /// are merged in by doc id; personal rows stay visible because they keep their
  /// own reminders. Two snapshot streams merged by hand, no rxdart.
  Stream<List<ClassModel>> watch(String userId, {String? groupId}) {
    final own = _col
        .where('userId', isEqualTo: userId)
        .orderBy('period')
        .snapshots()
        .map(_classes);
    if (groupId == null) return own;
    final shared = _col
        .where('groupId', isEqualTo: groupId)
        .orderBy('period')
        .snapshots()
        .map(_classes);

    late final StreamController<List<ClassModel>> controller;
    final subs = <StreamSubscription<List<ClassModel>>>[];
    List<ClassModel>? ownLatest;
    List<ClassModel>? sharedLatest;
    void emit() {
      // Wait for both sides so the list never flashes with half its rows.
      if (ownLatest == null || sharedLatest == null) return;
      final byId = <String, ClassModel>{
        for (final c in sharedLatest!) c.id: c,
        for (final c in ownLatest!) c.id: c,
      };
      controller.add(
          byId.values.toList()..sort((a, b) => a.period.compareTo(b.period)));
    }

    controller = StreamController<List<ClassModel>>(
      onListen: () {
        subs.add(own.listen((v) {
          ownLatest = v;
          emit();
        }, onError: controller.addError));
        subs.add(shared.listen((v) {
          sharedLatest = v;
          emit();
        }, onError: controller.addError));
      },
      onCancel: () async {
        await Future.wait(subs.map((s) => s.cancel()));
        subs.clear();
        unawaited(controller.close());
      },
    );
    return controller.stream;
  }

  Future<void> setStatus(String id,
      {required ClassStatus status,
      String? statusNote,
      DateTime? statusDate,
      String? reportedBy}) async {
    await _col.doc(id).update({
      'status': status.firestoreValue,
      'statusNote': statusNote,
      'statusDate': statusDate == null ? null : Timestamp.fromDate(statusDate),
      if (reportedBy != null)
        'statusReportedBy': status == ClassStatus.normal ? null : reportedBy,
    });
  }

  Future<void> add(ClassModel model) async {
    await _col.doc(model.id).set(model.toFirestore());
  }

  Future<void> update(ClassModel model) async {
    await _col.doc(model.id).update(model.toFirestore());
  }

  Future<void> delete(String id) async {
    await _col.doc(id).delete();
  }

  /// Whether [day]/[period] is taken, ignoring [excludeId]. In a group, the
  /// user's own and the group's classes both count (the sets [watch] shows).
  Future<bool> slotOccupied(String userId, String day, int period,
      {String? excludeId, String? groupId}) async {
    Future<bool> taken(String field, String value) async {
      final q = await _col
          .where(field, isEqualTo: value)
          .where('dayOfWeek', isEqualTo: day)
          .where('period', isEqualTo: period)
          .get();
      return q.docs.any((d) => d.id != excludeId);
    }

    final results = await Future.wait([
      taken('userId', userId),
      if (groupId != null) taken('groupId', groupId),
    ]);
    return results.any((occupied) => occupied);
  }
}
