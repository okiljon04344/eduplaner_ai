import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/class_model.dart';

class TimetableRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference get _col => _db.collection('timetables');

  Stream<List<ClassModel>> watch(String userId, {String? groupId}) {
    final query = groupId != null
        ? _col.where('groupId', isEqualTo: groupId).orderBy('period')
        : _col.where('userId', isEqualTo: userId).orderBy('period');
    return query.snapshots().map((s) => s.docs.map(ClassModel.fromFirestore).toList());
  }

  Future<void> setStatus(String id, {required ClassStatus status, String? statusNote, DateTime? statusDate}) async {
    await _col.doc(id).update({
      'status': status.firestoreValue,
      'statusNote': statusNote,
      'statusDate': statusDate == null ? null : Timestamp.fromDate(statusDate),
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

  Future<bool> slotOccupied(String userId, String day, int period, {String? excludeId, String? groupId}) async {
    final base = groupId != null ? _col.where('groupId', isEqualTo: groupId) : _col.where('userId', isEqualTo: userId);
    final q = await base.where('dayOfWeek', isEqualTo: day).where('period', isEqualTo: period).get();
    if (excludeId != null) return q.docs.any((d) => d.id != excludeId);
    return q.docs.isNotEmpty;
  }
}
