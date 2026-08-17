import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/notification_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/assignment_model.dart';

/// Mirrors the server-side cap in `functions/index.js`'s
/// `analyzeAssignmentSubmission` (`MAX_FILE_BYTES`). Checked here too so an
/// oversized file is rejected before it's base64-encoded (~4/3 size bloat)
/// and sent over the network, only to be rejected server-side anyway.
const _kMaxAssignmentFileBytes = 10 * 1024 * 1024;

/// Streams all assignments for the current user from Firestore.
///
/// Emits an empty stream when the user is not signed in.
final assignmentsStreamProvider = StreamProvider<List<AssignmentModel>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(assignmentsRepositoryProvider).watch(uid);
});

/// Currently active status filter on the assignments screen.
///
/// Values are locale-independent ids: `'all'`, `'notStarted'`,
/// `'inProgress'`, `'completed'` — display labels are looked up via
/// `AppStrings.t()` in [FilterChipsRow] so switching language never
/// breaks an active filter.
final selectedFilterProvider = StateProvider<String>((_) => 'all');

/// The assignment list after applying [selectedFilterProvider].
final filteredAssignmentsProvider = Provider<List<AssignmentModel>>((ref) {
  final all = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
  final filter = ref.watch(selectedFilterProvider);
  switch (filter) {
    case 'notStarted':
      return all.where((a) => a.status == AssignmentStatus.notStarted).toList();
    case 'inProgress':
      return all.where((a) => a.status == AssignmentStatus.inProgress).toList();
    case 'completed':
      return all.where((a) => a.status == AssignmentStatus.completed).toList();
    default:
      return all;
  }
});

/// How many assignments are due this week and how many are completed.
///
/// Used by the weekly progress ring on the home and assignments screens.
final weeklyProgressProvider = Provider<({int completed, int total})>((ref) {
  final all = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
  final now = DateTime.now();
  final startOfWeek = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
  final weekAssignments = all.where((a) {
    final due = a.dueDate;
    return due.isAfter(startOfWeek.subtract(const Duration(days: 1))) &&
        due.isBefore(startOfWeek.add(const Duration(days: 7)));
  }).toList();
  final completed =
      weekAssignments.where((a) => a.status == AssignmentStatus.completed).length;
  return (completed: completed, total: weekAssignments.length);
});

/// The next 3 incomplete assignments — shown on the home screen quick-view.
final upcomingAssignmentsProvider = Provider<List<AssignmentModel>>((ref) {
  final all = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
  return all.where((a) => a.status != AssignmentStatus.completed).take(3).toList();
});

/// How many incomplete assignments are due within the next 3 days.
///
/// Used to show an urgent badge count in the nav bar.
final urgentAssignmentsCountProvider = Provider<int>((ref) {
  final all = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return all.where((a) {
    if (a.status == AssignmentStatus.completed) return false;
    final due = DateTime(a.dueDate.year, a.dueDate.month, a.dueDate.day);
    final daysLeft = due.difference(today).inDays;
    return daysLeft >= 0 && daysLeft <= 3;
  }).length;
});

/// Handles all assignment write operations and AI-check integration.
class AssignmentsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Runs a [NotificationService] call, logging (not rethrowing) any
  /// failure — reminder scheduling is best-effort and must never surface
  /// as a user-facing error for what is otherwise a successful write.
  Future<void> _safeNotify(Future<void> Function() action, String label) async {
    try {
      await action();
    } catch (e) {
      debugPrint('$label error: $e');
    }
  }

  /// Creates a new assignment and schedules due-date reminders.
  Future<void> add(AssignmentModel model) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(assignmentsRepositoryProvider).add(model));
    if (!state.hasError) {
      await _safeNotify(() => NotificationService.scheduleAssignmentReminders(model), 'Assignment reminder schedule');
    }
  }

  /// Updates an existing assignment and reschedules its reminders.
  Future<void> updateAssignment(AssignmentModel model) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(assignmentsRepositoryProvider).update(model));
    if (!state.hasError) {
      await _safeNotify(() => NotificationService.scheduleAssignmentReminders(model), 'Assignment reminder schedule');
    }
  }

  /// Deletes an assignment and cancels its pending notifications.
  Future<void> delete(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(assignmentsRepositoryProvider).delete(id));
    await _safeNotify(() => NotificationService.cancelAssignmentReminders(id), 'Assignment reminder cancel');
  }

  /// Updates only the status field of an assignment.
  ///
  /// Cancels pending reminders when the assignment is marked completed.
  Future<void> updateStatus(String id, AssignmentStatus status) async {
    await ref.read(assignmentsRepositoryProvider).updateStatus(id, status);
    if (status == AssignmentStatus.completed) {
      await _safeNotify(() => NotificationService.cancelAssignmentReminders(id), 'Assignment reminder cancel');
    }
  }

  /// Updates only the progress percentage (0.0–1.0) of an assignment.
  Future<void> updateProgress(String id, double progress) async {
    await ref.read(assignmentsRepositoryProvider).updateProgress(id, progress);
  }

  /// 課題の自動チェック — base64-encodes a file picked by the user and sends it
  /// to the `analyzeAssignmentSubmission` Cloud Function for Gemini analysis.
  ///
  /// The file is never written to Storage or logged — it exists only in the
  /// Cloud Function's memory for that single invocation.  Only the derived
  /// result (`completionPercent`, `missingParts`, `advice`) is written back
  /// to Firestore and returned to the caller.
  ///
  /// Returns `(model: updated, error: null)` on success or
  /// `(model: null, error: message)` on failure.
  Future<({AssignmentModel? model, String? error})> checkWithAi(
    AssignmentModel assignment, {
    required Uint8List fileBytes,
    required String mimeType,
  }) async {
    if (fileBytes.length > _kMaxAssignmentFileBytes) {
      return (model: null, error: AppStrings.t('err_invalid_file'));
    }
    final repo = ref.read(assignmentsRepositoryProvider);
    try {
      final result = await repo.analyzeSubmission(
        subject: assignment.subject,
        title: assignment.title,
        description: assignment.description,
        fileBase64: base64Encode(fileBytes),
        mimeType: mimeType,
      );
      final completionPercent =
          (result['completionPercent'] as num?)?.toDouble() ?? 0.0;
      final missingParts = (result['missingParts'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      final advice = result['advice'] as String? ?? '';
      final analyzedAt = DateTime.now();
      await repo.saveAiAnalysis(
        assignment.id,
        completionPercent: completionPercent,
        missingParts: missingParts,
        advice: advice,
        analyzedAt: analyzedAt,
      );
      final updated = assignment.copyWith(
        aiCompletionPercent: completionPercent,
        aiMissingParts: missingParts,
        aiAdvice: advice,
        aiAnalyzedAt: analyzedAt,
      );
      return (model: updated, error: null);
    } catch (e) {
      debugPrint('checkWithAi error: $e');
      return (model: null, error: e.toString().replaceFirst('Exception: ', ''));
    }
  }
}

/// Global provider for [AssignmentsNotifier].
final assignmentsNotifierProvider =
    AsyncNotifierProvider<AssignmentsNotifier, void>(AssignmentsNotifier.new);
