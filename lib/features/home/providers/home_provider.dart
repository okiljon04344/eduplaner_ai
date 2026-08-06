import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../assignments/models/assignment_model.dart';
import '../../assignments/providers/assignments_provider.dart';

const _fallbackTip = '今日も一歩ずつ頑張りましょう！';
const _fallbackWeakArea = '課題を登録すると、AIが苦手科目を分析します。';
const _noAssignmentsWeakArea = '課題を登録すると、苦手科目の分析が表示されます。';

/// Tracks consecutive-day app-open streak and persists it to [SharedPreferences].
///
/// Backs the "🔥 Streak" stat pill on the home screen with a real number.
/// The streak increments when the app is opened on the day immediately
/// following the last recorded open; it resets to 1 otherwise.
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

/// Fetches a short daily AI study tip from the `chatWithTutor` Cloud Function.
///
/// The tip is cached in [SharedPreferences] keyed by today's date so the
/// function is called at most once per calendar day.  Falls back to a static
/// motivational string if the call fails or returns empty.
final aiStudyTipProvider = FutureProvider<String>((ref) async {
  final now = DateTime.now();
  final dateKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final prefs = await SharedPreferences.getInstance();
  final cacheKey = 'study_tip_$dateKey';
  final cached = prefs.getString(cacheKey);
  if (cached != null && cached.isNotEmpty) return cached;

  try {
    final callable = FirebaseFunctions.instance.httpsCallable('chatWithTutor');
    final result = await callable.call<Map<String, dynamic>>({
      'botId': 'focus',
      'message': '日本語で短い学習アドバイスを1つだけ教えてください（40文字以内）。返答はアドバイスの文章のみにしてください。',
    });
    final tip = (result.data['reply'] as String?)?.trim();
    if (tip == null || tip.isEmpty) return _fallbackTip;
    await prefs.setString(cacheKey, tip);
    return tip;
  } catch (_) {
    return _fallbackTip;
  }
});

/// Per-subject assignment stat accumulator for [weakAreaProvider].
class _SubjectStat {
  int total = 0;
  int completed = 0;
  int overdue = 0;
  int difficultySum = 0;
}

/// 苦手分野の分析 — aggregates per-subject assignment stats locally (no AI
/// needed for the counting), then sends just the summary numbers to the
/// `analyzeWeakArea` Cloud Function so Gemini can name the weakest subject(s)
/// and produce a short actionable tip.
///
/// Result is cached per day in [SharedPreferences] — same pattern as
/// [aiStudyTipProvider].  Falls back to a static string on error or when the
/// user has no assignments yet.
final weakAreaProvider = FutureProvider<String>((ref) async {
  final assignments = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
  if (assignments.isEmpty) return _noAssignmentsWeakArea;

  final now = DateTime.now();
  final dateKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final prefs = await SharedPreferences.getInstance();
  final cacheKey = 'weak_area_$dateKey';
  final cached = prefs.getString(cacheKey);
  if (cached != null && cached.isNotEmpty) return cached;

  final today = DateTime(now.year, now.month, now.day);
  final statsBySubject = <String, _SubjectStat>{};
  for (final a in assignments) {
    final stat = statsBySubject.putIfAbsent(a.subject, () => _SubjectStat());
    stat.total++;
    if (a.status == AssignmentStatus.completed) stat.completed++;
    final due = DateTime(a.dueDate.year, a.dueDate.month, a.dueDate.day);
    if (a.status != AssignmentStatus.completed && due.isBefore(today)) stat.overdue++;
    stat.difficultySum += a.difficulty;
  }

  final stats = statsBySubject.entries.map((e) => {
        'subject': e.key,
        'totalCount': e.value.total,
        'completedCount': e.value.completed,
        'overdueCount': e.value.overdue,
        'avgDifficulty': e.value.total == 0 ? 0 : e.value.difficultySum / e.value.total,
      }).toList();

  try {
    final callable = FirebaseFunctions.instance.httpsCallable('analyzeWeakArea');
    final result = await callable.call<Map<String, dynamic>>({'stats': stats});
    final analysis = (result.data['analysis'] as String?)?.trim();
    if (analysis == null || analysis.isEmpty) return _fallbackWeakArea;
    await prefs.setString(cacheKey, analysis);
    return analysis;
  } catch (_) {
    return _fallbackWeakArea;
  }
});
