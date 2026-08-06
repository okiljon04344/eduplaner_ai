import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/notification_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../groups/providers/groups_provider.dart';
import '../models/class_model.dart';
import '../repositories/timetable_repository.dart';

/// Streams the current user's full timetable.
///
/// When the user belongs to a study group the stream switches to the
/// group's unified timetable (queried by `groupId`) instead of the user's
/// personal classes.  The switch is reactive — joining or leaving a group
/// automatically updates every listener of this provider.
final timetableStreamProvider = StreamProvider<List<ClassModel>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream.empty();
  final groupId = ref.watch(myGroupProvider).valueOrNull?.id;
  return ref.watch(timetableRepositoryProvider).watch(uid, groupId: groupId);
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
  const days = ['月', '火', '水', '木', '金'];
  final wd = DateTime.now().weekday;
  if (wd > 5) return [];
  final today = days[wd - 1];
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

  /// Adds a new class, auto-attaching the caller's current group id if present.
  ///
  /// Returns a localised error string if the target slot is already occupied,
  /// or `null` on success.
  Future<String?> addClass(ClassModel model) async {
    final groupId = _groupId;
    final occupied = await _repo.slotOccupied(_uid, model.dayOfWeek, model.period, groupId: groupId);
    if (occupied) return '${model.dayOfWeek}曜日 ${model.period}限にはすでに授業が登録されています';
    final toSave = groupId != null ? model.copyWith(groupId: groupId) : model;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.add(toSave));
    if (!state.hasError) {
      try {
        await NotificationService.scheduleClassReminder(toSave);
      } catch (e) {
        debugPrint('Class reminder schedule error: $e');
      }
    }
    return state.hasError ? '授業の保存に失敗しました' : null;
  }

  /// Updates an existing class, excluding its own id from the conflict check.
  ///
  /// Returns a localised error string on slot conflict or save failure,
  /// or `null` on success.
  Future<String?> updateClass(ClassModel model) async {
    final occupied = await _repo.slotOccupied(
      _uid, model.dayOfWeek, model.period,
      excludeId: model.id,
      groupId: model.groupId,
    );
    if (occupied) return '${model.dayOfWeek}曜日 ${model.period}限にはすでに授業が登録されています';
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.update(model));
    if (!state.hasError) {
      try {
        await NotificationService.scheduleClassReminder(model);
      } catch (e) {
        debugPrint('Class reminder schedule error: $e');
      }
    }
    return state.hasError ? '授業の更新に失敗しました' : null;
  }

  /// Deletes a class by [id].
  Future<void> deleteClass(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.delete(id));
  }

  /// 休講・変更のアラート — marks [model] as cancelled/changed for today and,
  /// if it's shared with a study group, triggers `onClassStatusChanged` in
  /// functions/index.js to push-notify the other members.
  Future<String?> setStatus(
    ClassModel model, {
    required ClassStatus status,
    String? statusNote,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repo.setStatus(
        model.id,
        status: status,
        statusNote: statusNote,
        statusDate: DateTime.now(),
      ),
    );
    return state.hasError ? '更新に失敗しました' : null;
  }
}

/// Global provider for [TimetableNotifier].
final timetableNotifierProvider =
    AsyncNotifierProvider<TimetableNotifier, void>(TimetableNotifier.new);
