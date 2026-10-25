import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/ai_chat/repositories/chat_repository.dart';
import '../../features/assignments/repositories/assignments_repository.dart';
import '../../features/auth/repositories/auth_repository.dart';
import '../../features/groups/repositories/groups_repository.dart';
import '../../features/quiz/repositories/quiz_repository.dart';
import '../../features/timetable/repositories/timetable_repository.dart';

/// Index of the visible bottom-nav / rail tab. Set before `context.go()` so
/// [AppShell] can slide the new screen in from the correct side.
final shellTabIndexProvider = StateProvider<int>((ref) => 0);

// Repositories are plain Dart objects; providing them lets tests override them.
final authRepositoryProvider =
    Provider<AuthRepository>((_) => AuthRepository());

final timetableRepositoryProvider =
    Provider<TimetableRepository>((_) => TimetableRepository());

final assignmentsRepositoryProvider =
    Provider<AssignmentsRepository>((_) => AssignmentsRepository());

final chatRepositoryProvider =
    Provider<ChatRepository>((_) => ChatRepository());

final groupsRepositoryProvider =
    Provider<GroupsRepository>((_) => GroupsRepository());

final quizRepositoryProvider =
    Provider<QuizRepository>((_) => QuizRepository());
