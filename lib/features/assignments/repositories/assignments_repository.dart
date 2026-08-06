import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/assignment_model.dart';

class AssignmentsRepository {
  final _db = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;
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

  /// 課題の自動チェック — sends the submitted file (never stored, only
  /// forwarded) to `analyzeAssignmentSubmission` for a Gemini-based review.
  Future<Map<String, dynamic>> analyzeSubmission({
    required String subject,
    required String title,
    String? description,
    required String fileBase64,
    required String mimeType,
  }) async {
    try {
      final callable = _functions.httpsCallable(
        'analyzeAssignmentSubmission',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
      );
      final result = await callable.call<Map<String, dynamic>>({
        'subject': subject,
        'title': title,
        'description': description ?? '',
        'fileBase64': fileBase64,
        'mimeType': mimeType,
      });
      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unauthenticated') throw Exception('ログインが必要です。');
      if (e.code == 'invalid-argument') throw Exception(e.message ?? 'ファイルを確認してください。');
      throw Exception('課題のチェックに失敗しました。もう一度お試しください。');
    }
  }

  Future<void> saveAiAnalysis(
    String id, {
    required double completionPercent,
    required List<String> missingParts,
    required String advice,
    required DateTime analyzedAt,
  }) async {
    await _col.doc(id).update({
      'aiCompletionPercent': completionPercent,
      'aiMissingParts': missingParts,
      'aiAdvice': advice,
      'aiAnalyzedAt': Timestamp.fromDate(analyzedAt),
    });
  }
}
