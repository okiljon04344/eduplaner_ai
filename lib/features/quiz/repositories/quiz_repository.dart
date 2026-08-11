import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../../../core/l10n/app_strings.dart';
import '../models/quiz_question.dart';

class QuizRepository {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<List<QuizQuestion>> generateQuiz({
    required String subject,
    String topic = '',
    bool useSearch = false,
  }) async {
    try {
      final callable = _functions.httpsCallable(
        'generateQuiz',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
      );
      final result = await callable.call<Map<String, dynamic>>({
        'subject': subject,
        'topic': topic,
        'useSearch': useSearch,
      });
      final raw = result.data['questions'] as List<dynamic>? ?? [];
      return raw.map((e) => QuizQuestion.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } on FirebaseFunctionsException catch (e) {
      debugPrint('generateQuiz error: ${e.code} ${e.message}');
      // Show the server-provided Japanese message when available so users see
      // "quota reached" vs "invalid input" vs "server busy" instead of one
      // generic fallback. Empty/null falls back to a generic message.
      final serverMsg = (e.message ?? '').trim();
      if (e.code == 'unauthenticated') {
        throw Exception(AppStrings.t('err_login_required'));
      }
      if (e.code == 'deadline-exceeded') {
        throw Exception(AppStrings.t('err_timeout'));
      }
      if (e.code == 'not-found') {
        throw Exception(AppStrings.t('err_quiz_unavailable'));
      }
      if (e.code == 'resource-exhausted') {
        throw Exception(AppStrings.t('err_ai_limit_reached'));
      }
      if (e.code == 'unavailable' || e.code == 'internal') {
        throw Exception(AppStrings.t('err_server'));
      }
      throw Exception(serverMsg.isNotEmpty ? serverMsg : AppStrings.t('err_quiz_generate_failed'));
    }
  }
}
