import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/clock_provider.dart';
import '../../../core/services/notification_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../groups/providers/groups_provider.dart';
import '../models/class_model.dart';
import '../repositories/timetable_repository.dart';

/// Streams the current user's full timetable.
///
/// When the user belongs to a study group the stream is the union of the
/// group's shared classes (queried by `groupId`) and the user's own personal
/// classes, de-duplicated by id.  The switch is reactive — joining or leaving
/// a group automatically updates every listener of this provider.
final timetableStreamProvider = StreamProvider<List<ClassModel>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream.empty();
  final groupId = ref.watch(myGroupProvider).valueOrNull?.id;
  var synced = false;
  return ref.watch(timetableRepositoryProvider).watch(uid, groupId: groupId).map((classes) {
    if (!synced) {
      synced = true;
      unawaited(NotificationService.syncAllReminders(classes: classes));
    }
    return classes;
  });
});

/// Transforms the flat class list into a `{dayOfWeek: {period: ClassModel}}`
/// grid that the timetable widget can look up in O(1).
final timetableGridProvider = Provider<Map<String, Map<int, ClassModel>>>((ref) {
  final classes = ref.watch(timetableStreamProvider).valueOrNull ?? [];
  final grid = <String, Map<int, ClassModel>>{};
  for (final c in classes) {
    grid.putIfAbsent(c.dayOfWeek, () => {})[c.period] = c;
  }
  return grid;
});

/// Returns today's classes sorted by period.
///
/// Returns an empty list on Saturday/Sunday (weekday > 5).
final todayClassesProvider = Provider<List<ClassModel>>((ref) {
  final all = ref.watch(timetableStreamProvider).valueOrNull ?? [];
  // Watching the clock re-evaluates this at each local midnight.
  final wd = (ref.watch(todayProvider).valueOrNull ?? DateTime.now()).weekday;
  if (wd > 5) return [];
  final today = kWeekdayKanji[wd - 1];
  return all.where((c) => c.dayOfWeek == today).toList()
    ..sort((a, b) => a.period.compareTo(b.period));
});

/// Handles all write operations on the timetable (add, update, delete, status).
///
/// Each mutation checks for slot conflicts before writing and schedules (or
/// reschedules) push-notification reminders via [NotificationService].
class TimetableNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  TimetableRepository get _repo => ref.read(timetableRepositoryProvider);
  String get _uid => ref.read(currentUserProvider)?.uid ?? '';
  String? get _groupId => ref.read(myGroupProvider).valueOrNull?.id;

  /// Shared conflict-check + write + reminder-schedule sequence for
  /// [addClass]/[updateClass] — they differ only in the conflict-check
  /// params, the repository call, and the save-failure message.
  Future<String?> _saveClass({
    required ClassModel model,
    required String? excludeId,
    required String? groupId,
    required Future<void> Function() write,
    required String saveFailedKey,
  }) async {
    final bool occupied;
    try {
      occupied = await _repo.slotOccupied(
        _uid, model.dayOfWeek, model.period,
        excludeId: excludeId,
        groupId: groupId,
      );
    } catch (e) {
      debugPrint('Class slot check error: $e');
      return AppStrings.t(saveFailedKey);
    }
    if (occupied) {
      return AppStrings.t('err_slot_occupied', {'day': weekdayLabel(model.dayOfWeek), 'period': model.period});
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(write);
    if (!state.hasError) {
      try {
        await NotificationService.scheduleClassReminder(model);
      } catch (e) {
        debugPrint('Class reminder schedule error: $e');
      }
    }
    return state.hasError ? AppStrings.t(saveFailedKey) : null;
  }

  /// Adds a new class, auto-attaching the caller's current group id if present.
  ///
  /// Returns a localised error string if the target slot is already occupied,
  /// or `null` on success.
  Future<String?> addClass(ClassModel model) async {
    final groupId = _groupId;
    final toSave = groupId != null ? model.copyWith(groupId: groupId) : model;
    return _saveClass(
      model: toSave,
      excludeId: null,
      groupId: groupId,
      write: () => _repo.add(toSave),
      saveFailedKey: 'err_class_save_failed',
    );
  }

  /// Updates an existing class, excluding its own id from the conflict check.
  ///
  /// Returns a localised error string on slot conflict or save failure,
  /// or `null` on success.
  Future<String?> updateClass(ClassModel model) async {
    // Check against the group the user is in *now*. A class still tagged with
    // a group the user has since left is detached first: querying that group
    // would be rejected by the rules, and the row is theirs alone again.
    final groupId = _groupId;
    final toSave = model.groupId != null && model.groupId != groupId ? model.copyWith(groupId: null) : model;
    return _saveClass(
      model: toSave,
      excludeId: toSave.id,
      groupId: groupId,
      write: () => _repo.update(toSave),
      saveFailedKey: 'err_class_update_failed',
    );
  }

  /// Deletes a class by [id].
  ///
  /// Returns a localised error string on failure, or `null` on success.
  Future<String?> deleteClass(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.delete(id));
    if (state.hasError) return AppStrings.t('err_generic_retry');
    try {
      await NotificationService.cancelClassReminders(id);
    } catch (e) {
      debugPrint('Class reminder cancel error: $e');
    }
    return null;
  }

  /// 休講・変更のアラート — marks [model] as cancelled/changed for its next
  /// occurrence (see [nextClassDate]) and, if it's shared with a study group,
  /// triggers `onClassStatusChanged` in functions/index.js to push-notify the
  /// other members. Passing [ClassStatus.normal] clears the alert.
  Future<String?> setStatus(
    ClassModel model, {
    required ClassStatus status,
    String? statusNote,
  }) async {
    final statusDate = status == ClassStatus.normal
        ? null
        : nextClassDate(dayOfWeek: model.dayOfWeek, period: model.period);
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repo.setStatus(
        model.id,
        status: status,
        statusNote: statusNote,
        statusDate: statusDate,
        reportedBy: _uid.isEmpty ? null : _uid,
      ),
    );
    return state.hasError ? AppStrings.t('err_class_status_update_failed') : null;
  }
}

/// Global provider for [TimetableNotifier].
final timetableNotifierProvider =
    AsyncNotifierProvider<TimetableNotifier, void>(TimetableNotifier.new);
