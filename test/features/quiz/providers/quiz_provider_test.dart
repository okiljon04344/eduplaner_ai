import 'package:edu_planner_ai/core/providers/app_providers.dart';
import 'package:edu_planner_ai/features/quiz/models/quiz_question.dart';
import 'package:edu_planner_ai/features/quiz/providers/quiz_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

ProviderContainer _createContainer({required FakeQuizRepository repo}) {
  final container = ProviderContainer(
    overrides: [
      quizRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('selectedQuizSubjectProvider', () {
    test('defaults to null and can be updated', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(selectedQuizSubjectProvider), isNull);

      container.read(selectedQuizSubjectProvider.notifier).state = '数学';
      expect(container.read(selectedQuizSubjectProvider), '数学');
    });
  });

  group('QuizNotifier', () {
    test('initial state resolves to AsyncData with empty list', () async {
      final repo = FakeQuizRepository();
      final container = _createContainer(repo: repo);

      final initial = await container.read(quizNotifierProvider.future);
      expect(initial, isEmpty);
      expect(container.read(quizNotifierProvider), isA<AsyncData<List<QuizQuestion>>>());
    });

    test('generate maps success questions and passes parameters to repository', () async {
      final expectedQuestions = [
        buildQuizQuestion(question: 'Q1', choices: ['A', 'B'], answerIndex: 0),
        buildQuizQuestion(question: 'Q2', choices: ['C', 'D'], answerIndex: 1),
      ];
      final repo = FakeQuizRepository(questions: expectedQuestions);
      final container = _createContainer(repo: repo);

      await container.read(quizNotifierProvider.notifier).generate(
            subject: '英語',
            topic: '不定詞と動名詞',
            useSearch: true,
          );

      expect(repo.generateCalls, hasLength(1));
      expect(repo.generateCalls.single.subject, '英語');
      expect(repo.generateCalls.single.topic, '不定詞と動名詞');
      expect(repo.generateCalls.single.useSearch, isTrue);

      final state = container.read(quizNotifierProvider);
      expect(state, isA<AsyncData<List<QuizQuestion>>>());
      expect(state.value, hasLength(2));
      expect(state.value!.first.question, 'Q1');
      expect(state.value!.last.question, 'Q2');
    });

    test('generate maps repository exception to AsyncError', () async {
      final repo = FakeQuizRepository(
        error: Exception('利用制限に達しました。明日再度お試しください。'),
      );
      final container = _createContainer(repo: repo);

      await container.read(quizNotifierProvider.notifier).generate(
            subject: '物理',
            topic: '力学',
          );

      expect(repo.generateCalls, hasLength(1));
      final state = container.read(quizNotifierProvider);
      expect(state.hasError, isTrue);
      expect(state.error.toString(), contains('利用制限に達しました'));
    });

    test('reset clears the question list back to AsyncData([])', () async {
      final questions = [buildQuizQuestion(question: '問題')];
      final repo = FakeQuizRepository(questions: questions);
      final container = _createContainer(repo: repo);

      await container.read(quizNotifierProvider.notifier).generate(subject: '数学');
      expect(container.read(quizNotifierProvider).value, hasLength(1));

      container.read(quizNotifierProvider.notifier).reset();
      expect(container.read(quizNotifierProvider).value, isEmpty);
    });
  });
}
