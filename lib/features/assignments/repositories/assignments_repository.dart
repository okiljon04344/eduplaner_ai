import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/assignment_model.dart';

class AssignmentsRepository {
  final _db = FirebaseFirestore.instance;
  CollectionReference get _col => _db.collection('assignments');

  Stream<List<AssignmentModel>> watch(String userId) =>
      _col.where('userId', isEqualTo: userId).snapshots().map((s) {
        final assignments = s.docs.map(AssignmentModel.fromFirestore).toList();
        assignments.sort((a, b) => a.dueDate.compareTo(b.dueDate));
        return assignments;
      });

  Future<void> add(AssignmentModel model) async =>
      _col.doc(model.id).set(model.toFirestore());
  Future<void> update(AssignmentModel model) async =>
      _col.doc(model.id).update(model.toFirestore());
  Future<void> delete(String id) async => _col.doc(id).delete();
  Future<void> updateStatus(String id, AssignmentStatus status) async =>
      _col.doc(id).update({'status': status.firestoreValue});
  Future<void> updateProgress(String id, double progress) async =>
      _col.doc(id).update({'progress': progress});
}
