import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/notification_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/class_model.dart';
import '../repositories/timetable_repository.dart';

final timetableStreamProvider = StreamProvider<List<ClassModel>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(timetableRepositoryProvider).watch(uid);
});

final timetableGridProvider = Provider<Map<String, Map<int, ClassModel>>>((ref) {
  final classes = ref.watch(timetableStreamProvider).valueOrNull ?? [];
  final grid = <String, Map<int, ClassModel>>{};
  for (final c in classes) {
    grid.putIfAbsent(c.dayOfWeek, () => {})[c.period] = c;
  }
  return grid;
});

final todayClassesProvider = Provider<List<ClassModel>>((ref) {
  final all = ref.watch(timetableStreamProvider).valueOrNull ?? [];
  const days = ['月', '火', '水', '木', '金'];
  final wd = DateTime.now().weekday;
  if (wd > 5) return [];
  final today = days[wd - 1];
  return all.where((c) => c.dayOfWeek == today).toList()..sort((a, b) => a.period.compareTo(b.period));
});

class TimetableNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  TimetableRepository get _repo => ref.read(timetableRepositoryProvider);
  String get _uid => ref.read(currentUserProvider)?.uid ?? '';

  Future<String?> addClass(ClassModel model) async {
    final occupied = await _repo.slotOccupied(_uid, model.dayOfWeek, model.period);
    if (occupied) return '${model.dayOfWeek}曜日 ${model.period}限にはすでに授業が登録されています';
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.add(model));
    if (!state.hasError) {
      try {
        await NotificationService.scheduleClassReminder(model);
      } catch (e) {
        debugPrint('Class reminder schedule error: $e');
      }
    }
    return state.hasError ? '授業の保存に失敗しました' : null;
  }

  Future<String?> updateClass(ClassModel model) async {
    final occupied = await _repo.slotOccupied(_uid, model.dayOfWeek, model.period, excludeId: model.id);
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

  Future<void> deleteClass(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.delete(id));
  }
}

final timetableNotifierProvider = AsyncNotifierProvider<TimetableNotifier, void>(TimetableNotifier.new);
