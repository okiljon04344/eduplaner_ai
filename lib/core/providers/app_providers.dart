import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/ai_chat/repositories/chat_repository.dart';
import '../../features/assignments/repositories/assignments_repository.dart';
import '../../features/auth/repositories/auth_repository.dart';
import '../../features/groups/repositories/groups_repository.dart';
import '../../features/quiz/repositories/quiz_repository.dart';
import '../../features/school/school_repository.dart';
import '../../features/timetable/repositories/timetable_repository.dart';

/// Tracks which bottom-nav / rail tab is currently visible.
///
/// Updated by [AppBottomNav] and [AppNavRail] before calling `context.go()`,
/// so [AppShell]'s [_DirectionalTab] can determine whether the new screen is
/// to the left or to the right and animate accordingly.
///
/// UZ: Hozirda qaysi pastki navigatsiya / rels tab ko'rinib turganini kuzatib boradi.
///
/// `context.go()` chaqirilishidan oldin [AppBottomNav] va [AppNavRail] tomonidan yangilanadi,
/// shunda [AppShell]'ning [_DirectionalTab] vidjeti yangi ekran chapda yoki o'ngda ekanligini
/// aniqlay oladi va shunga mos ravishda animatsiyalaydi.
final shellTabIndexProvider = StateProvider<int>((ref) => 0);

// ── Repository providers ────────────────────────────────────────────────────
// Each repository is a plain Dart object with no Flutter dependencies.
// Wrapping them in Provider lets Riverpod inject them into feature providers
// and makes them easily mockable in tests.
// UZ: Har bir repozitoriy Flutter bog'liqliklariga ega bo'lmagan oddiy Dart obyekti hisoblanadi.
// Ularni Provider ichiga o'rash Riverpod'ga ularni funksional provider'larga inyeksiya qilish
// imkonini beradi va ularni testlarda osongina mock qilish imkonini beradi.

/// Provides the singleton [AuthRepository] that handles Firebase Auth
/// sign-in, sign-out, and user-profile operations.
///
/// UZ: Firebase Auth tizimiga kirish, chiqish va foydalanuvchi profili amallarini
/// boshqaradigan singleton [AuthRepository] ni taqdim etadi.
final authRepositoryProvider = Provider<AuthRepository>((_) => AuthRepository());

/// Provides the singleton [TimetableRepository] that reads/writes the
/// `timetables` Firestore collection.
///
/// UZ: `timetables` Firestore kolleksiyasini o'qiydigan/yozadigan singleton
/// [TimetableRepository] ni taqdim etadi.
final timetableRepositoryProvider = Provider<TimetableRepository>((_) => TimetableRepository());

/// Provides the singleton [AssignmentsRepository] that manages the
/// `assignments` Firestore collection.
///
/// UZ: `assignments` Firestore kolleksiyasini boshqaradigan singleton
/// [AssignmentsRepository] ni taqdim etadi.
final assignmentsRepositoryProvider = Provider<AssignmentsRepository>((_) => AssignmentsRepository());

/// Provides the singleton [ChatRepository] that proxies AI chat requests
/// through the `chatWithTutor` Cloud Function.
///
/// UZ: AI chat so'rovlarini `chatWithTutor` Cloud Function orqali proksilaydigan
/// singleton [ChatRepository] ni taqdim etadi.
final chatRepositoryProvider = Provider<ChatRepository>((_) => ChatRepository());

/// Provides the singleton [GroupsRepository] that manages `study_groups`
/// documents and the server-side `joinGroupByCode` Cloud Function.
///
/// UZ: `study_groups` hujjatlarini va server tomonidagi `joinGroupByCode`
/// Cloud Function'ini boshqaradigan singleton [GroupsRepository] ni taqdim etadi.
final groupsRepositoryProvider = Provider<GroupsRepository>((_) => GroupsRepository());

/// Provides the singleton [QuizRepository] that calls the `generateQuiz`
/// Cloud Function and returns typed [QuizQuestion] objects.
///
/// UZ: `generateQuiz` Cloud Function'ini chaqiradigan va tiplashtirilgan [QuizQuestion]
/// obyektlarini qaytaradigan singleton [QuizRepository] ni taqdim etadi.
final quizRepositoryProvider = Provider<QuizRepository>((_) => QuizRepository());

/// Provides the [SchoolRepository] that reads server-synced school timetables.
///
/// UZ: Server bilan sinxronlangan maktab dars jadvallarini o'qiydigan [SchoolRepository] ni taqdim etadi.
final schoolRepositoryProvider = Provider<SchoolRepository>((_) => SchoolRepository());
