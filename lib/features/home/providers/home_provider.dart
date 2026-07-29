import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/api_constants.dart';

const _fallbackTip = '今日も一歩ずつ頑張りましょう！';

/// Consecutive-day app-open streak, persisted locally. Backs the hero "🔥
/// Streak" stat pill with a real (if simple) number instead of a fake one.
final dailyStreakProvider = FutureProvider<int>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now();
  final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final lastOpen = prefs.getString('streak_last_open');
  var streak = prefs.getInt('streak_count') ?? 0;

  if (lastOpen == todayKey) return streak == 0 ? 1 : streak;

  if (lastOpen != null) {
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayKey = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    streak = (lastOpen == yesterdayKey) ? streak + 1 : 1;
  } else {
    streak = 1;
  }

  await prefs.setString('streak_last_open', todayKey);
  await prefs.setInt('streak_count', streak);
  return streak;
});

final aiStudyTipProvider = FutureProvider<String>((ref) async {
  final now = DateTime.now();
  final dateKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final prefs = await SharedPreferences.getInstance();
  final cacheKey = 'study_tip_$dateKey';
  final cached = prefs.getString(cacheKey);
  if (cached != null && cached.isNotEmpty) return cached;

  const storage = FlutterSecureStorage();
  final storedKey = await storage.read(key: ApiConstants.geminiApiKeyName);
  final apiKey = (storedKey != null && storedKey.trim().isNotEmpty) ? storedKey.trim() : ApiConstants.geminiDefaultApiKey;

  try {
    final model = GenerativeModel(model: ApiConstants.geminiModel, apiKey: apiKey);
    final response = await model.generateContent([
      Content.text('日本語で短い学習アドバイスを1つだけ教えてください（40文字以内）。返答はアドバイスの文章のみにしてください。'),
    ]);
    final tip = response.text?.trim();
    if (tip == null || tip.isEmpty) return _fallbackTip;
    await prefs.setString(cacheKey, tip);
    return tip;
  } catch (_) {
    return _fallbackTip;
  }
});
