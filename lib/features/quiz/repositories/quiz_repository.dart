import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/functions_service.dart';
import '../models/quiz_question.dart';

class QuizRepository {
  Future<List<QuizQuestion>> generateQuiz({
    required String subject,
    String topic = '',
    bool useSearch = false,
  }) async {
    try {
      final callable = FunctionsService.callable('generateQuiz');
      final result = await callable.call<Map<String, dynamic>>({
        'subject': subject,
        'topic': topic,
        'useSearch': useSearch,
        'language': AppStrings.currentLocale,
      });
      final raw = result.data['questions'] as List<dynamic>? ?? [];
      return raw.map((e) => QuizQuestion.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } on FirebaseFunctionsException catch (e) {
      debugPrint('generateQuiz error: ${e.code} ${e.message}');
      // Show the server-provided message or localized reason when available so
      // users see "budget exceeded" / "temporarily unavailable" / "quota reached"
      // instead of one generic fallback.
      final serverMsg = (e.message ?? '').trim();
      final reason = FunctionsService.reasonOf(e);
      if (e.code == 'not-found') {
        throw Exception(AppStrings.t('err_quiz_unavailable'));
      }
      if (reason == 'ai_temporarily_unavailable' ||
          reason == 'ai_budget_exceeded' ||
          e.code == 'unauthenticated' ||
          e.code == 'deadline-exceeded' ||
          e.code == 'unavailable' ||
          e.code == 'resource-exhausted') {
        throw Exception(FunctionsService.describeError(e));
      }
      throw Exception(serverMsg.isNotEmpty ? serverMsg : AppStrings.t('err_quiz_generate_failed'));
    }
  }
}
