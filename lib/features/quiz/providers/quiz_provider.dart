import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../models/quiz_question.dart';

/// Remembers which subject was last used on the quiz screen so the dropdown
/// restores its value when the user navigates away and comes back.
final selectedQuizSubjectProvider = StateProvider<String?>((_) => null);

/// Manages AI quiz generation state.
///
/// State is the list of [QuizQuestion]s returned by the last successful
/// generation, or an empty list before the first call.
class QuizNotifier extends AsyncNotifier<List<QuizQuestion>> {
  @override
  Future<List<QuizQuestion>> build() async => [];

  /// Calls the `generateQuiz` Cloud Function and replaces state with the
  /// returned questions.
  ///
  /// [useSearch] enables Google Search grounding for up-to-date content.
  /// Generation uses a two-stage Gemini call (search + JSON formatting) with
  /// a 120-second server-side timeout to avoid the previous 45-second freeze.
  Future<void> generate({
    required String subject,
    String topic = '',
    bool useSearch = false,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(quizRepositoryProvider).generateQuiz(
        subject: subject,
        topic: topic,
        useSearch: useSearch,
      ),
    );
  }

  /// Clears the current question list (e.g. when the subject changes).
  void reset() => state = const AsyncData([]);
}

/// Global provider for [QuizNotifier].
final quizNotifierProvider =
    AsyncNotifierProvider<QuizNotifier, List<QuizQuestion>>(QuizNotifier.new);
