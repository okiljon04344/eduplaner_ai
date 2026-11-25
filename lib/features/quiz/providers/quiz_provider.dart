import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../models/quiz_question.dart';

/// Remembers which subject was last used on the quiz screen so the dropdown
/// restores its value when the user navigates away and comes back.
///
/// UZ: Foydalanuvchi boshqa sahifaga o'tib qaytib kelganida ochiladigan ro'yxat o'z qiymatini tiklashi
/// uchun viktorina ekranida oxirgi marta qaysi fan ishlatilganini eslab qoladi.
final selectedQuizSubjectProvider = StateProvider<String?>((_) => null);

/// Manages AI quiz generation state.
///
/// State is the list of [QuizQuestion]s returned by the last successful
/// generation, or an empty list before the first call.
///
/// UZ: AI viktorina generatsiyasi holatini boshqaradi.
///
/// Holat oxirgi muvaffaqiyatli generatsiya tomonidan qaytarilgan [QuizQuestion]lar ro'yxati,
/// yoki birinchi chaqiruvdan oldin bo'sh ro'yxat hisoblanadi.
class QuizNotifier extends AsyncNotifier<List<QuizQuestion>> {
  int _generationCounter = 0;

  @override
  Future<List<QuizQuestion>> build() async => [];

  /// Cancels any ongoing quiz generation and resets state to empty.
  ///
  /// UZ: Davom etayotgan viktorina generatsiyasini bekor qiladi va holatni bo'sh holatga qaytaradi.
  void cancel() {
    _generationCounter++;
    state = const AsyncData([]);
  }

  /// Calls the `generateQuiz` Cloud Function and replaces state with the
  /// returned questions.
  ///
  /// [useSearch] enables Google Search grounding for up-to-date content.
  /// Generation uses a two-stage Gemini call (search + JSON formatting) with
  /// a 120-second server-side timeout to avoid the previous 45-second freeze.
  ///
  /// UZ: `generateQuiz` Cloud Function'ni chaqiradi va holatni qaytarilgan savollar bilan almashtiradi.
  ///
  /// [useSearch] eng so'nggi tarkib uchun Google Search grounding'ni yoqadi.
  /// Generatsiya oldingi 45 soniyalik qotib qolishning oldini olish uchun 120 soniyalik server tomonidagi
  /// timeout bilan ikki bosqichli Gemini chaqiruvidan (qidiruv + JSON formatlash) foydalanadi.
  Future<void> generate({
    required String subject,
    String topic = '',
    bool useSearch = false,
  }) async {
    final currentId = ++_generationCounter;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => ref.read(quizRepositoryProvider).generateQuiz(
        subject: subject,
        topic: topic,
        useSearch: useSearch,
      ),
    );
    if (_generationCounter == currentId) {
      state = result;
    }
  }

  /// Clears the current question list (e.g. when the subject changes).
  ///
  /// UZ: Joriy savollar ro'yxatini tozalaydi (masalan, fan o'zgarganda).
  void reset() => state = const AsyncData([]);
}

/// Global provider for [QuizNotifier].
///
/// UZ: [QuizNotifier] uchun global provider.
final quizNotifierProvider =
    AsyncNotifierProvider<QuizNotifier, List<QuizQuestion>>(QuizNotifier.new);
