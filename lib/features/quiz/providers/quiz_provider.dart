import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../models/quiz_question.dart';

/// Last subject used on the quiz screen, restored when the user returns.
final selectedQuizSubjectProvider = StateProvider<String?>((_) => null);

/// Holds the questions from the last successful generation (empty before the first).
class QuizNotifier extends AsyncNotifier<List<QuizQuestion>> {
  @override
  Future<List<QuizQuestion>> build() async => [];

  /// Calls the `generateQuiz` Cloud Function. [useSearch] enables Google Search
  /// grounding, which costs a second AI call and a longer server-side timeout.
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

  /// Clears the current questions.
  void reset() => state = const AsyncData([]);
}

final quizNotifierProvider =
    AsyncNotifierProvider<QuizNotifier, List<QuizQuestion>>(QuizNotifier.new);
