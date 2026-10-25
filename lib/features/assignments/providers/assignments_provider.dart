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

/// Mirrors `MAX_FILE_BYTES` in `analyzeAssignmentSubmission` (functions/index.js).
/// Checked here too so an oversized file is rejected before it is base64-encoded
/// and uploaded.
const _kMaxAssignmentFileBytes = 10 * 1024 * 1024;

/// The current user's assignments; empty when signed out.
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

/// Active status filter: `'all'`, `'notStarted'`, `'inProgress'` or `'completed'`.
/// Locale-independent ids; [FilterChipsRow] translates the labels, so switching
/// language never breaks an active filter.
final selectedFilterProvider = StateProvider<String>((_) => 'all');

/// Assignments after applying [selectedFilterProvider].
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

/// Assignments due this week and how many of them are completed.
final weeklyProgressProvider = Provider<({int completed, int total})>((ref) {
  final all = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
  final now = DateTime.now();
  // Calendar arithmetic (not Duration) keeps Monday 00:00 .. next Monday 00:00
  // correct across DST changes.
  final start = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  final end = DateTime(start.year, start.month, start.day + 7);
  final weekAssignments = all.where((a) {
    final due = a.dueDate;
    return !due.isBefore(start) && due.isBefore(end);
  }).toList();
  final completed = weekAssignments
      .where((a) => a.status == AssignmentStatus.completed)
      .length;
  return (completed: completed, total: weekAssignments.length);
});

/// The next 3 incomplete assignments for the home quick-view. Anything overdue
/// by more than 7 days is ignored so old leftovers don't crowd out upcoming work.
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

/// Incomplete assignments that are overdue or due within 3 days (nav badge).
final urgentAssignmentsCountProvider = Provider<int>((ref) {
  final all = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
  final now = DateTime.now();
  return all
      .where((a) =>
          a.status != AssignmentStatus.completed &&
          DateHelper.daysBetween(a.dueDate, now) <= 3)
      .length;
});

/// Assignment writes and the AI submission check.
class AssignmentsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Runs a [NotificationService] call, logging failures instead of rethrowing:
  /// reminders are best-effort and must not turn a successful write into an error.
  Future<void> _safeNotify(Future<void> Function() action, String label) async {
    try {
      await action();
    } catch (e) {
      debugPrint('$label error: $e');
    }
  }

  /// Runs [write]; returns null on success, else the generic retry message
  /// (callers show it in a toast and keep their UI open).
  Future<String?> _guarded(Future<void> Function() write, String label) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(write);
    if (state.hasError) {
      debugPrint('$label error: ${state.error}');
      return AppStrings.t('err_generic_retry');
    }
    return null;
  }

  /// Creates an assignment and schedules its reminders. Returns null on success,
  /// else an error message (same for the other write methods).
  Future<String?> add(AssignmentModel model) async {
    final error = await _guarded(
        () => ref.read(assignmentsRepositoryProvider).add(model),
        'Assignment add');
    if (error == null) {
      await _safeNotify(
          () => NotificationService.scheduleAssignmentReminders(model),
          'Assignment reminder schedule');
    }
    return error;
  }

  /// Updates an assignment and reschedules its reminders.
  Future<String?> updateAssignment(AssignmentModel model) async {
    final error = await _guarded(
        () => ref.read(assignmentsRepositoryProvider).update(model),
        'Assignment update');
    if (error == null) {
      await _safeNotify(
          () => NotificationService.scheduleAssignmentReminders(model),
          'Assignment reminder schedule');
    }
    return error;
  }

  /// Deletes an assignment and cancels its reminders.
  Future<String?> delete(String id) async {
    final error = await _guarded(
        () => ref.read(assignmentsRepositoryProvider).delete(id),
        'Assignment delete');
    if (error == null) {
      await _safeNotify(() => NotificationService.cancelAssignmentReminders(id),
          'Assignment reminder cancel');
    }
    return error;
  }

  /// Writes [status] together with its matching progress (see [AssignmentModel.withStatus]).
  Future<String?> updateStatus(
          AssignmentModel model, AssignmentStatus status) =>
      _writeStatusProgress(model, model.withStatus(status));

  /// Writes [progress] (0.0-1.0) together with its derived status (see
  /// [AssignmentModel.withProgress]).
  Future<String?> updateProgress(AssignmentModel model, double progress) =>
      _writeStatusProgress(model, model.withProgress(progress));

  /// Writes [next]'s status and progress in one update and keeps reminders in
  /// step: cancelled on completion, rescheduled when leaving completed.
  Future<String?> _writeStatusProgress(
      AssignmentModel previous, AssignmentModel next) async {
    try {
      await ref
          .read(assignmentsRepositoryProvider)
          .updateStatusAndProgress(next.id, next.status, next.progress);
    } catch (e) {
      debugPrint('Assignment status/progress error: $e');
      return AppStrings.t('err_generic_retry');
    }
    if (next.status == AssignmentStatus.completed) {
      await _safeNotify(
          () => NotificationService.cancelAssignmentReminders(next.id),
          'Assignment reminder cancel');
    } else if (previous.status == AssignmentStatus.completed) {
      await _safeNotify(
          () => NotificationService.scheduleAssignmentReminders(next),
          'Assignment reminder schedule');
    }
    return null;
  }

  /// AI check of a submitted file via `analyzeAssignmentSubmission`.
  ///
  /// Privacy: the file is never stored or logged; it only lives in the
  /// function's memory for that call. Only the derived result
  /// (`completionPercent`, `missingParts`, `advice`) is written to Firestore.
  ///
  /// Returns `(model: updated, error: null)` or `(model: null, error: message)`.
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

final assignmentsNotifierProvider =
    AsyncNotifierProvider<AssignmentsNotifier, void>(AssignmentsNotifier.new);
