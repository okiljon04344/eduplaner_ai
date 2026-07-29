import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/notification_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/assignment_model.dart';

final assignmentsStreamProvider = StreamProvider<List<AssignmentModel>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(assignmentsRepositoryProvider).watch(uid);
});

final selectedFilterProvider = StateProvider<String>((_) => 'すべて');

final filteredAssignmentsProvider = Provider<List<AssignmentModel>>((ref) {
  final all = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
  final filter = ref.watch(selectedFilterProvider);
  switch (filter) {
    case '未着手':
      return all.where((a) => a.status == AssignmentStatus.notStarted).toList();
    case '進行中':
      return all.where((a) => a.status == AssignmentStatus.inProgress).toList();
    case '完了':
      return all.where((a) => a.status == AssignmentStatus.completed).toList();
    default:
      return all;
  }
});

final weeklyProgressProvider = Provider<({int completed, int total})>((ref) {
  final all = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
  final now = DateTime.now();
  final startOfWeek = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
  final weekAssignments = all.where((a) {
    final due = a.dueDate;
    return due.isAfter(startOfWeek.subtract(const Duration(days: 1))) && due.isBefore(startOfWeek.add(const Duration(days: 7)));
  }).toList();
  final completed = weekAssignments.where((a) => a.status == AssignmentStatus.completed).length;
  return (completed: completed, total: weekAssignments.length);
});

final upcomingAssignmentsProvider = Provider<List<AssignmentModel>>((ref) {
  final all = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
  return all.where((a) => a.status != AssignmentStatus.completed).take(3).toList();
});

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

class AssignmentsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> add(AssignmentModel model) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(assignmentsRepositoryProvider).add(model));
    if (!state.hasError) {
      try {
        await NotificationService.scheduleAssignmentReminders(model);
      } catch (e) {
        debugPrint('Assignment reminder schedule error: $e');
      }
    }
  }

  Future<void> updateAssignment(AssignmentModel model) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(assignmentsRepositoryProvider).update(model));
    if (!state.hasError) {
      try {
        await NotificationService.scheduleAssignmentReminders(model);
      } catch (e) {
        debugPrint('Assignment reminder schedule error: $e');
      }
    }
  }

  Future<void> delete(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(assignmentsRepositoryProvider).delete(id));
    try {
      await NotificationService.cancelAssignmentReminders(id);
    } catch (e) {
      debugPrint('Assignment reminder cancel error: $e');
    }
  }

  Future<void> updateStatus(String id, AssignmentStatus status) async {
    await ref.read(assignmentsRepositoryProvider).updateStatus(id, status);
    if (status == AssignmentStatus.completed) {
      try {
        await NotificationService.cancelAssignmentReminders(id);
      } catch (e) {
        debugPrint('Assignment reminder cancel error: $e');
      }
    }
  }

  Future<void> updateProgress(String id, double progress) async {
    await ref.read(assignmentsRepositoryProvider).updateProgress(id, progress);
  }
}

final assignmentsNotifierProvider = AsyncNotifierProvider<AssignmentsNotifier, void>(AssignmentsNotifier.new);
