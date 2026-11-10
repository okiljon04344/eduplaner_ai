import 'package:edu_planner_ai/features/quiz/models/quiz_question.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuizQuestion.fromJson', () {
    test('parses full valid JSON correctly', () {
      final json = {
        'question': '日本の首都はどこですか？',
        'choices': ['大阪', '東京', '京都', '福岡'],
        'answerIndex': 1,
        'explanation': '日本の首都は東京です。',
      };

      final q = QuizQuestion.fromJson(json);

      expect(q.question, '日本の首都はどこですか？');
      expect(q.choices, ['大阪', '東京', '京都', '福岡']);
      expect(q.answerIndex, 1);
      expect(q.explanation, '日本の首都は東京です。');
    });

    test('handles empty map with default fallbacks', () {
      final q = QuizQuestion.fromJson({});

      expect(q.question, isEmpty);
      expect(q.choices, isEmpty);
      expect(q.answerIndex, 0);
      expect(q.explanation, isEmpty);
    });

    test('handles null fields safely', () {
      final json = <String, dynamic>{
        'question': null,
        'choices': null,
        'answerIndex': null,
        'explanation': null,
      };

      final q = QuizQuestion.fromJson(json);

      expect(q.question, isEmpty);
      expect(q.choices, isEmpty);
      expect(q.answerIndex, 0);
      expect(q.explanation, isEmpty);
    });

    test('converts non-string elements in choices to strings', () {
      final json = {
        'choices': [100, 200.5, true, '選択肢D'],
      };

      final q = QuizQuestion.fromJson(json);

      expect(q.choices, ['100', '200.5', 'true', '選択肢D']);
    });

    test('parses double answerIndex as int', () {
      final json = {
        'answerIndex': 3.0,
      };

      final q = QuizQuestion.fromJson(json);

      expect(q.answerIndex, 3);
    });
  });
}
