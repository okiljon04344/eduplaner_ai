import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/ai_chat/repositories/chat_repository.dart';
import '../../features/assignments/repositories/assignments_repository.dart';
import '../../features/auth/repositories/auth_repository.dart';
import '../../features/groups/repositories/groups_repository.dart';
import '../../features/quiz/repositories/quiz_repository.dart';
import '../../features/timetable/repositories/timetable_repository.dart';

/// Tracks which bottom-nav / rail tab is currently visible.
///
/// Updated by [AppBottomNav] and [AppNavRail] before calling `context.go()`,
/// so [AppShell]'s [_DirectionalTab] can determine whether the new screen is
/// to the left or to the right and animate accordingly.
final shellTabIndexProvider = StateProvider<int>((ref) => 0);

// ── Repository providers ────────────────────────────────────────────────────
// Each repository is a plain Dart object with no Flutter dependencies.
// Wrapping them in Provider lets Riverpod inject them into feature providers
// and makes them easily mockable in tests.

/// Provides the singleton [AuthRepository] that handles Firebase Auth
/// sign-in, sign-out, and user-profile operations.
final authRepositoryProvider = Provider<AuthRepository>((_) => AuthRepository());

/// Provides the singleton [TimetableRepository] that reads/writes the
/// `timetables` Firestore collection.
final timetableRepositoryProvider = Provider<TimetableRepository>((_) => TimetableRepository());

/// Provides the singleton [AssignmentsRepository] that manages the
/// `assignments` Firestore collection.
final assignmentsRepositoryProvider = Provider<AssignmentsRepository>((_) => AssignmentsRepository());

/// Provides the singleton [ChatRepository] that proxies AI chat requests
/// through the `chatWithTutor` Cloud Function.
final chatRepositoryProvider = Provider<ChatRepository>((_) => ChatRepository());

/// Provides the singleton [GroupsRepository] that manages `study_groups`
/// documents and the server-side `joinGroupByCode` Cloud Function.
final groupsRepositoryProvider = Provider<GroupsRepository>((_) => GroupsRepository());

/// Provides the singleton [QuizRepository] that calls the `generateQuiz`
/// Cloud Function and returns typed [QuizQuestion] objects.
final quizRepositoryProvider = Provider<QuizRepository>((_) => QuizRepository());
