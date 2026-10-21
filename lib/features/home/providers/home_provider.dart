import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/services/functions_service.dart';
import '../../../core/utils/date_helper.dart';
import '../../auth/providers/auth_provider.dart';
import '../../assignments/models/assignment_model.dart';
import '../../assignments/providers/assignments_provider.dart';

// Getters (not consts) so they always resolve in the currently loaded locale.
String get _fallbackTip => AppStrings.t('tip_fallback');
String get _fallbackWeakArea => AppStrings.t('weak_fallback');
String get _noAssignmentsWeakArea => AppStrings.t('weak_no_assignments');

// Cache keys are per locale and per day, so switching language re-fetches in
// the new language and a new day starts fresh.
String _studyTipCacheKey(String locale, DateTime day) => 'study_tip_${locale}_${DateHelper.dayKey(day)}';
String _weakAreaCacheKey(String locale, DateTime day) => 'weak_area_${locale}_${DateHelper.dayKey(day)}';

/// While set and in the future, [weakAreaProvider] makes no `analyzeWeakArea`
/// call: after a failure, every assignment change would otherwise retry the
/// function (and burn daily AI quota) while it is failing.
DateTime? _weakAreaBackoffUntil;
const _weakAreaBackoff = Duration(minutes: 10);

/// Removes today's cached study tip and weak-area analysis for [locale] (and
/// any weak-area failure backoff) so the next provider read hits the server.
/// Used by the home pull-to-refresh, which is an explicit user request.
Future<void> clearTodaysAiCache(String locale) async {
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now();
  await prefs.remove(_studyTipCacheKey(locale, now));
  await prefs.remove(_weakAreaCacheKey(locale, now));
  _weakAreaBackoffUntil = null;
}

/// Tracks consecutive-day app-open streak and persists it to [SharedPreferences].
///
/// Backs the "🔥 Streak" stat pill on the home screen with a real number.
/// The streak increments when the app is opened on the day immediately
/// following the last recorded open; it resets to 1 otherwise.
final dailyStreakProvider = FutureProvider<int>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now();
  final todayKey = DateHelper.dayKey(now);
  final lastOpen = prefs.getString('streak_last_open');
  var streak = prefs.getInt('streak_count') ?? 0;

  if (lastOpen == todayKey) return streak == 0 ? 1 : streak;

  if (lastOpen != null) {
    // Calendar arithmetic (not `subtract(Duration(days: 1))`, which is 24h and
    // lands on the wrong day just after a DST change).
    final yesterdayKey = DateHelper.dayKey(DateTime(now.year, now.month, now.day - 1));
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
  if (ref.watch(currentUserProvider) == null) return _fallbackTip;
  final locate = ref.watch(localeProvider);
  final prefs = await SharedPreferences.getInstance();
  final cacheKey = _studyTipCacheKey(locate, DateTime.now());
  final cached = prefs.getString(cacheKey);
  if (cached != null && cached.isNotEmpty) return cached;

  try {
    final callable = FunctionsService.callable('chatWithTutor');
    final result = await callable.call<Map<String, dynamic>>({
      'botId': 'focus',
      'message': AppStrings.t('ai_tip_prompt'),
      'language': locate,
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
/// The result is cached per locale and day as JSON `{sig, text}`, where `sig`
/// is a stable string of the computed stats: the function is only called when
/// the stats actually changed, not on every assignment-stream emission. After
/// a failed call no new call is made for 10 minutes; the cached text (even
/// from older stats) is returned if there is one, else the localized fallback.
final weakAreaProvider = FutureProvider<String>((ref) async {
  final locate = ref.watch(localeProvider);
  final assignments = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
  if (assignments.isEmpty) return _noAssignmentsWeakArea;

  final now = DateTime.now();
  final prefs = await SharedPreferences.getInstance();
  final cacheKey = _weakAreaCacheKey(locate, now);
  final cached = _decodeWeakAreaCache(prefs.getString(cacheKey));

  final statsBySubject = <String, _SubjectStat>{};
  for (final a in assignments) {
    final stat = statsBySubject.putIfAbsent(a.subject, () => _SubjectStat());
    stat.total++;
    if (a.status == AssignmentStatus.completed) stat.completed++;
    if (a.status != AssignmentStatus.completed && DateHelper.daysBetween(a.dueDate, now) < 0) stat.overdue++;
    stat.difficultySum += a.difficulty;
  }

  final subjects = statsBySubject.keys.toList()..sort();
  final stats = [
    for (final subject in subjects)
      {
        'subject': subject,
        'totalCount': statsBySubject[subject]!.total,
        'completedCount': statsBySubject[subject]!.completed,
        'overdueCount': statsBySubject[subject]!.overdue,
        'avgDifficulty': statsBySubject[subject]!.difficultySum / statsBySubject[subject]!.total,
      },
  ];
  final sig = jsonEncode(stats);

  if (cached != null && cached.sig == sig) return cached.text;

  final backoffUntil = _weakAreaBackoffUntil;
  if (backoffUntil != null && now.isBefore(backoffUntil)) return cached?.text ?? _fallbackWeakArea;

  String? analysis;
  try {
    final callable = FunctionsService.callable('analyzeWeakArea');
    final result = await callable.call<Map<String, dynamic>>({
      'stats': stats,
      'language': locate,
    });
    analysis = (result.data['analysis'] as String?)?.trim();
  } catch (_) {
    analysis = null;
  }
  if (analysis == null || analysis.isEmpty) {
    _weakAreaBackoffUntil = DateTime.now().add(_weakAreaBackoff);
    return cached?.text ?? _fallbackWeakArea;
  }
  await prefs.setString(cacheKey, jsonEncode({'sig': sig, 'text': analysis}));
  return analysis;
});

/// Parses the `{sig, text}` weak-area cache entry. A plain-text entry written
/// by an older app version is returned with an empty `sig` (never matches, so
/// it is refreshed once, but still usable as a fallback text).
({String sig, String text})? _decodeWeakAreaCache(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final json = jsonDecode(raw);
    if (json is Map && json['text'] is String && (json['text'] as String).isNotEmpty) {
      return (sig: json['sig'] as String? ?? '', text: json['text'] as String);
    }
    return null;
  } on FormatException {
    return (sig: '', text: raw);
  }
}
