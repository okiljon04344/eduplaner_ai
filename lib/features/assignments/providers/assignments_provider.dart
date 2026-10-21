import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/date_helper.dart';
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
  var synced = false;
  return ref.watch(assignmentsRepositoryProvider).watch(uid).map((assignments) {
    if (!synced) {
      synced = true;
      unawaited(NotificationService.syncAllReminders(assignments: assignments));
    }
    return assignments;
  });
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
  // Calendar arithmetic (not Duration): Monday 00:00 .. next Monday 00:00,
  // correct across DST changes.
  final start = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  final end = DateTime(start.year, start.month, start.day + 7);
  final weekAssignments = all.where((a) {
    final due = a.dueDate;
    return !due.isBefore(start) && due.isBefore(end);
  }).toList();
  final completed =
      weekAssignments.where((a) => a.status == AssignmentStatus.completed).length;
  return (completed: completed, total: weekAssignments.length);
});

/// The next 3 incomplete assignments — shown on the home screen quick-view.
///
/// Only items due within the last 7 days or later are considered, so ancient
/// overdue leftovers can't crowd out the real upcoming work.
final upcomingAssignmentsProvider = Provider<List<AssignmentModel>>((ref) {
  final all = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
  final now = DateTime.now();
  final upcoming = all
      .where((a) =>
          a.status != AssignmentStatus.completed &&
          DateHelper.daysBetween(a.dueDate, now) >= -7)
      .toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return upcoming.take(3).toList();
});

/// How many incomplete assignments are overdue or due within the next 3 days.
///
/// Used to show an urgent badge count in the nav bar.
final urgentAssignmentsCountProvider = Provider<int>((ref) {
  final all = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
  final now = DateTime.now();
  return all
      .where((a) =>
          a.status != AssignmentStatus.completed &&
          DateHelper.daysBetween(a.dueDate, now) <= 3)
      .length;
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

  /// Runs [write], returning `null` on success or the localized generic
  /// retry message on failure (after logging) — callers show the message in
  /// an error toast and keep their UI open.
  Future<String?> _guarded(Future<void> Function() write, String label) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(write);
    if (state.hasError) {
      debugPrint('$label error: ${state.error}');
      return AppStrings.t('err_generic_retry');
    }
    return null;
  }

  /// Creates a new assignment and schedules due-date reminders.
  ///
  /// Returns `null` on success, otherwise an error message to show.
  Future<String?> add(AssignmentModel model) async {
    final error = await _guarded(() => ref.read(assignmentsRepositoryProvider).add(model), 'Assignment add');
    if (error == null) {
      await _safeNotify(() => NotificationService.scheduleAssignmentReminders(model), 'Assignment reminder schedule');
    }
    return error;
  }

  /// Updates an existing assignment and reschedules its reminders.
  ///
  /// Returns `null` on success, otherwise an error message to show.
  Future<String?> updateAssignment(AssignmentModel model) async {
    final error = await _guarded(() => ref.read(assignmentsRepositoryProvider).update(model), 'Assignment update');
    if (error == null) {
      await _safeNotify(() => NotificationService.scheduleAssignmentReminders(model), 'Assignment reminder schedule');
    }
    return error;
  }

  /// Deletes an assignment and cancels its pending notifications.
  ///
  /// Returns `null` on success, otherwise an error message to show.
  Future<String?> delete(String id) async {
    final error = await _guarded(() => ref.read(assignmentsRepositoryProvider).delete(id), 'Assignment delete');
    if (error == null) {
      await _safeNotify(() => NotificationService.cancelAssignmentReminders(id), 'Assignment reminder cancel');
    }
    return error;
  }

  /// Sets [status] on [model] and writes it together with the progress that
  /// goes with it (see [AssignmentModel.withStatus]).
  ///
  /// Returns `null` on success, otherwise an error message to show.
  Future<String?> updateStatus(AssignmentModel model, AssignmentStatus status) =>
      _writeStatusProgress(model, model.withStatus(status));

  /// Sets the progress (0.0–1.0) of [model] and writes it together with the
  /// status derived from it (see [AssignmentModel.withProgress]).
  ///
  /// Returns `null` on success, otherwise an error message to show.
  Future<String?> updateProgress(AssignmentModel model, double progress) =>
      _writeStatusProgress(model, model.withProgress(progress));

  /// Persists [next]'s status + progress in one Firestore update and keeps
  /// reminders in step: cancelled when it becomes completed, rescheduled when
  /// it leaves completed.
  Future<String?> _writeStatusProgress(AssignmentModel previous, AssignmentModel next) async {
    try {
      await ref.read(assignmentsRepositoryProvider).updateStatusAndProgress(next.id, next.status, next.progress);
    } catch (e) {
      debugPrint('Assignment status/progress error: $e');
      return AppStrings.t('err_generic_retry');
    }
    if (next.status == AssignmentStatus.completed) {
      await _safeNotify(() => NotificationService.cancelAssignmentReminders(next.id), 'Assignment reminder cancel');
    } else if (previous.status == AssignmentStatus.completed) {
      await _safeNotify(() => NotificationService.scheduleAssignmentReminders(next), 'Assignment reminder schedule');
    }
    return null;
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
