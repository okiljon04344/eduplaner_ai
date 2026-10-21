import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/functions_service.dart';
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

  /// Writes every editable field but never the `ai*` result fields — those
  /// are owned by [saveAiAnalysis], so a stale model passed here can't erase
  /// a fresher AI check.
  Future<void> update(AssignmentModel model) async =>
      _col.doc(model.id).update(model.toFirestore()..removeWhere((k, _) => k.startsWith('ai')));
  Future<void> delete(String id) async => _col.doc(id).delete();

  /// Writes status and progress together in one update so the two fields
  /// can never be observed out of sync.
  Future<void> updateStatusAndProgress(String id, AssignmentStatus status, double progress) async =>
      _col.doc(id).update({'status': status.firestoreValue, 'progress': progress});

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
      final callable = FunctionsService.callable('analyzeAssignmentSubmission');
      final result = await callable.call<Map<String, dynamic>>({
        'subject': subject,
        'title': title,
        'description': description ?? '',
        'fileBase64': fileBase64,
        'mimeType': mimeType,
        'language': AppStrings.currentLocale,
      });
      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'invalid-argument') throw Exception(e.message ?? AppStrings.t('err_invalid_file'));
      if (e.code == 'unauthenticated' || e.code == 'deadline-exceeded' || e.code == 'unavailable' || e.code == 'resource-exhausted') {
        throw Exception(FunctionsService.describeError(e));
      }
      throw Exception(AppStrings.t('err_assignment_check_failed'));
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
