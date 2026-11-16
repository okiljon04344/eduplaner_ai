import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/functions_service.dart';
import '../models/quiz_question.dart';

/// Repository requesting AI-generated quiz questions by calling Cloud Functions
/// with subject, topic, and search parameters.
///
/// UZ: Fan, mavzu va qidiruv parametrlari bilan Cloud Functions ni chaqirish orqali
/// AI tomonidan yaratilgan test savollarini so'rovchi repozitoriy.
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
      // Show the server-provided Japanese message when available so users see
      // "quota reached" vs "invalid input" vs "server busy" instead of one
      // generic fallback. Empty/null falls back to a generic message.
      // UZ: Foydalanuvchilar bitta umumiy zaxira xabari o'rniga "quota reached" yoki "invalid input"
      // yoki "server busy" kabi aniq xabarlarni ko'rishlari uchun server bergan yaponcha xabarni
      // ko'rsatadi (mavjud bo'lganda). Bo'sh/null bo'lsa, umumiy xabarga tayanadi.
      final serverMsg = (e.message ?? '').trim();
      if (e.code == 'not-found') {
        throw Exception(AppStrings.t('err_quiz_unavailable'));
      }
      if (e.code == 'resource-exhausted') {
        throw Exception(AppStrings.t('err_ai_limit_reached'));
      }
      if (e.code == 'unauthenticated' || e.code == 'deadline-exceeded' || e.code == 'unavailable') {
        throw Exception(FunctionsService.describeError(e));
      }
      throw Exception(serverMsg.isNotEmpty ? serverMsg : AppStrings.t('err_quiz_generate_failed'));
    }
  }
}
