import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/ai_chat/repositories/chat_repository.dart';
import '../../features/assignments/repositories/assignments_repository.dart';
import '../../features/auth/repositories/auth_repository.dart';
import '../../features/timetable/repositories/timetable_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((_) => AuthRepository());
final timetableRepositoryProvider = Provider<TimetableRepository>((_) => TimetableRepository());
final assignmentsRepositoryProvider = Provider<AssignmentsRepository>((_) => AssignmentsRepository());
final chatRepositoryProvider = Provider<ChatRepository>((_) => ChatRepository());
