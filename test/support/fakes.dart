import 'package:edu_planner_ai/features/assignments/models/assignment_model.dart';
import 'package:edu_planner_ai/features/assignments/repositories/assignments_repository.dart';
import 'package:edu_planner_ai/features/auth/models/user_model.dart';

/// Fake AssignmentsRepository for widget/unit tests. Uses `implements` (not
/// `extends`) so the real `FirebaseFirestore.instance` field initializer on
/// [AssignmentsRepository] is never touched — Firebase is never initialized
/// in the test harness.
class FakeAssignmentsRepository implements AssignmentsRepository {
  final List<AssignmentModel> initial;
  final List<({String id, AssignmentStatus status})> statusCalls = [];
  final List<({String id, double progress})> progressCalls = [];
  final List<AssignmentModel> addedModels = [];
  final List<AssignmentModel> updatedModels = [];
  final List<String> deletedIds = [];

  FakeAssignmentsRepository({this.initial = const []});

  @override
  Stream<List<AssignmentModel>> watch(String userId) => Stream.value(initial);

  @override
  Future<void> add(AssignmentModel model) async => addedModels.add(model);

  @override
  Future<void> update(AssignmentModel model) async => updatedModels.add(model);

  @override
  Future<void> delete(String id) async => deletedIds.add(id);

  @override
  Future<void> updateStatus(String id, AssignmentStatus status) async {
    statusCalls.add((id: id, status: status));
  }

  @override
  Future<void> updateProgress(String id, double progress) async {
    progressCalls.add((id: id, progress: progress));
  }

  @override
  Future<Map<String, dynamic>> analyzeSubmission({
    required String subject,
    required String title,
    String? description,
    required String fileBase64,
    required String mimeType,
  }) async {
    return const {'completionPercent': 0.0, 'missingParts': <String>[], 'advice': ''};
  }

  @override
  Future<void> saveAiAnalysis(
    String id, {
    required double completionPercent,
    required List<String> missingParts,
    required String advice,
    required DateTime analyzedAt,
  }) async {}
}

/// Convenience builder for a fully-populated [AssignmentModel].
AssignmentModel buildAssignment({
  String? id,
  String userId = 'u1',
  String title = '課題',
  String subject = '数学',
  DateTime? dueDate,
  AssignmentStatus status = AssignmentStatus.notStarted,
  double progress = 0.0,
  int difficulty = 1,
  DateTime? createdAt,
}) {
  final now = DateTime.now();
  return AssignmentModel(
    id: id ?? 'a-${now.microsecondsSinceEpoch}',
    userId: userId,
    title: title,
    subject: subject,
    dueDate: dueDate ?? now.add(const Duration(days: 5)),
    status: status,
    progress: progress,
    difficulty: difficulty,
    createdAt: createdAt ?? now,
  );
}

/// Convenience builder for a fake logged-in [UserModel].
UserModel buildUser({
  String uid = 'u1',
  String name = 'テストユーザー',
  String email = 'test@example.com',
  String? school,
}) {
  return UserModel(
    uid: uid,
    name: name,
    email: email,
    school: school,
    createdAt: DateTime(2026, 1, 1),
  );
}
