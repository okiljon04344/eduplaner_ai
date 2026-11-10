// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edu_planner_ai/features/assignments/models/assignment_model.dart';
import 'package:edu_planner_ai/features/assignments/repositories/assignments_repository.dart';
import 'package:edu_planner_ai/features/auth/models/user_model.dart';
import 'package:edu_planner_ai/features/auth/repositories/auth_repository.dart';
import 'package:edu_planner_ai/features/groups/models/study_group_model.dart';
import 'package:edu_planner_ai/features/groups/repositories/groups_repository.dart';
import 'package:edu_planner_ai/features/quiz/models/quiz_question.dart';
import 'package:edu_planner_ai/features/quiz/repositories/quiz_repository.dart';

/// Fake AssignmentsRepository for widget/unit tests. Uses `implements` (not
/// `extends`) so the real `FirebaseFirestore.instance` field initializer on
/// [AssignmentsRepository] is never touched — Firebase is never initialized
/// in the test harness.
class FakeAssignmentsRepository implements AssignmentsRepository {
  final List<AssignmentModel> initial;
  final List<({String id, AssignmentStatus status, double progress})> statusProgressCalls = [];
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
  Future<void> updateStatusAndProgress(String id, AssignmentStatus status, double progress) async {
    statusProgressCalls.add((id: id, status: status, progress: progress));
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

/// Fake GroupsRepository for tests.
class FakeGroupsRepository implements GroupsRepository {
  StudyGroupModel? currentGroup;
  Object? createGroupError;
  String? joinGroupByCodeError;
  Object? joinGroupByCodeThrows;
  Object? leaveGroupError;

  final List<({String name, String ownerId})> createGroupCalls = [];
  final List<String> joinCalls = [];
  final List<({StudyGroupModel group, String uid})> leaveCalls = [];

  FakeGroupsRepository({
    this.currentGroup,
    this.createGroupError,
    this.joinGroupByCodeError,
    this.joinGroupByCodeThrows,
    this.leaveGroupError,
  });

  @override
  Stream<StudyGroupModel?> watchMyGroup(String uid) => Stream.value(currentGroup);

  @override
  Future<StudyGroupModel> createGroup(String name, String ownerId) async {
    createGroupCalls.add((name: name, ownerId: ownerId));
    if (createGroupError != null) throw createGroupError!;
    final group = buildStudyGroup(name: name, ownerId: ownerId, memberIds: [ownerId]);
    currentGroup = group;
    return group;
  }

  @override
  Future<String?> joinGroupByCode(String code) async {
    joinCalls.add(code);
    if (joinGroupByCodeThrows != null) throw joinGroupByCodeThrows!;
    return joinGroupByCodeError;
  }

  @override
  Future<void> leaveGroup(StudyGroupModel group, String uid) async {
    leaveCalls.add((group: group, uid: uid));
    if (leaveGroupError != null) throw leaveGroupError!;
    currentGroup = null;
  }
}

/// Convenience builder for [StudyGroupModel].
StudyGroupModel buildStudyGroup({
  String id = 'g1',
  String name = 'グループA',
  String code = 'ABC123',
  String ownerId = 'u1',
  List<String> memberIds = const ['u1'],
  DateTime? createdAt,
}) {
  return StudyGroupModel(
    id: id,
    name: name,
    code: code,
    ownerId: ownerId,
    memberIds: memberIds,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
  );
}

/// Fake QuizRepository for tests.
class FakeQuizRepository implements QuizRepository {
  List<QuizQuestion> questions;
  Object? error;
  final List<({String subject, String topic, bool useSearch})> generateCalls = [];

  FakeQuizRepository({this.questions = const [], this.error});

  @override
  Future<List<QuizQuestion>> generateQuiz({
    required String subject,
    String topic = '',
    bool useSearch = false,
  }) async {
    generateCalls.add((subject: subject, topic: topic, useSearch: useSearch));
    if (error != null) throw error!;
    return questions;
  }
}

/// Convenience builder for [QuizQuestion].
QuizQuestion buildQuizQuestion({
  String question = '問題1',
  List<String> choices = const ['選択肢A', '選択肢B', '選択肢C', '選択肢D'],
  int answerIndex = 0,
  String explanation = '解説文です',
}) {
  return QuizQuestion(
    question: question,
    choices: choices,
    answerIndex: answerIndex,
    explanation: explanation,
  );
}

/// Fake AuthRepository for testing auth actions without Firebase.
class FakeAuthRepository implements AuthRepository {
  UserModel? currentUser;
  bool signedOut = false;

  FakeAuthRepository({this.currentUser});

  @override
  String? get currentUid => currentUser?.uid;

  @override
  Stream<UserModel?> get authStateStream => Stream.value(currentUser);

  @override
  Future<void> ensureGoogleSignInReady() async {}

  @override
  Future<UserModel> signInWithGoogle() async => currentUser ?? buildUser();

  @override
  Future<UserModel> signUpWithEmail(String email, String password, String name) async =>
      currentUser ?? buildUser(email: email, name: name);

  @override
  Future<UserModel> signInWithEmail(String email, String password) async =>
      currentUser ?? buildUser(email: email);

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<String> verifyPasswordResetCode(String code) async => 'test@example.com';

  @override
  Future<void> confirmPasswordReset(String code, String newPassword) async {}

  @override
  Future<void> signOut() async {
    signedOut = true;
    currentUser = null;
  }

  @override
  Future<void> saveSchoolProfile({
    required String schoolType,
    required String schoolName,
    String? grade,
    String? program,
    String? faculty,
    String? department,
    String? course,
    String? schoolDomain,
  }) async {}
}

/// Minimal FakeDocumentSnapshot for testing `fromFirestore` factory constructors.
class FakeDocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  final String id;
  final Map<String, dynamic>? _data;

  FakeDocumentSnapshot(this.id, [this._data]);

  @override
  Map<String, dynamic>? data() => _data;

  @override
  bool get exists => _data != null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
