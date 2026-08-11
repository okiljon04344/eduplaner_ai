import 'package:edu_planner_ai/features/assignments/models/assignment_model.dart';
import 'package:edu_planner_ai/features/assignments/providers/assignments_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

/// Builds a fresh Riverpod container with `assignmentsStreamProvider`
/// short-circuited to [assignments]. Overriding the *stream* provider (rather
/// than the repository) skips having to route through `currentUserProvider`
/// and Firebase auth — the downstream selectors below only care about the
/// list, not where it came from.
ProviderContainer _containerWith(List<AssignmentModel> assignments) {
  final container = ProviderContainer(
    overrides: [
      assignmentsStreamProvider.overrideWith((_) => Stream.value(assignments)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

DateTime _atNoon(DateTime d) => DateTime(d.year, d.month, d.day, 12);

/// `Stream.value(x)` emits on the next microtask, so a plain synchronous read
/// right after container creation would still be in the loading state. Await
/// the stream's first value before reading derived providers.
Future<ProviderContainer> _hydrated(List<AssignmentModel> assignments) async {
  final container = _containerWith(assignments);
  await container.read(assignmentsStreamProvider.future);
  return container;
}

void main() {
  group('weeklyProgressProvider', () {
    test('counts only assignments whose dueDate falls inside the current Mon–Sun week', () async {
      final now = DateTime.now();
      // Monday of the current week at noon.
      final monday = _atNoon(now.subtract(Duration(days: now.weekday - 1)));
      final lastWeek = monday.subtract(const Duration(days: 3));
      final thisWeekMid = monday.add(const Duration(days: 2));
      final thisWeekEnd = monday.add(const Duration(days: 6));
      final nextWeek = monday.add(const Duration(days: 10));

      final container = await _hydrated([
        buildAssignment(id: 'a1', dueDate: thisWeekMid, status: AssignmentStatus.completed),
        buildAssignment(id: 'a2', dueDate: thisWeekEnd, status: AssignmentStatus.inProgress),
        buildAssignment(id: 'a3', dueDate: lastWeek, status: AssignmentStatus.completed),
        buildAssignment(id: 'a4', dueDate: nextWeek, status: AssignmentStatus.notStarted),
      ]);

      final result = container.read(weeklyProgressProvider);
      expect(result.total, 2, reason: 'lastWeek + nextWeek should be excluded');
      expect(result.completed, 1, reason: 'only the completed thisWeek assignment counts');
    });

    test('returns (completed: 0, total: 0) when there are no assignments this week', () async {
      final container = await _hydrated(const []);
      final result = container.read(weeklyProgressProvider);
      expect(result.completed, 0);
      expect(result.total, 0);
    });
  });

  group('urgentAssignmentsCountProvider', () {
    // Actual implementation flags anything not-completed with 0 <= daysLeft <= 3
    // (i.e. due today through 3 days out — overdue is *excluded*). Tests below
    // pin that behaviour so a future change is intentional, not accidental.
    test('includes items due today, tomorrow, and up to 3 days out; excludes overdue and completed', () async {
      final today = _atNoon(DateTime.now());
      final container = await _hydrated([
        buildAssignment(id: 'today', dueDate: today),
        buildAssignment(id: 'tomorrow', dueDate: today.add(const Duration(days: 1))),
        buildAssignment(id: 'in3', dueDate: today.add(const Duration(days: 3))),
        buildAssignment(id: 'in4', dueDate: today.add(const Duration(days: 4))),
        buildAssignment(id: 'overdue', dueDate: today.subtract(const Duration(days: 1))),
        buildAssignment(
          id: 'doneToday',
          dueDate: today,
          status: AssignmentStatus.completed,
        ),
      ]);

      expect(container.read(urgentAssignmentsCountProvider), 3);
    });

    test('returns 0 for an empty list', () async {
      final container = await _hydrated(const []);
      expect(container.read(urgentAssignmentsCountProvider), 0);
    });
  });

  group('filteredAssignmentsProvider', () {
    test('respects the current selectedFilterProvider state', () async {
      final today = _atNoon(DateTime.now());
      final container = await _hydrated([
        buildAssignment(id: 'ns', status: AssignmentStatus.notStarted, dueDate: today),
        buildAssignment(id: 'ip', status: AssignmentStatus.inProgress, dueDate: today),
        buildAssignment(id: 'done', status: AssignmentStatus.completed, dueDate: today),
      ]);

      expect(container.read(filteredAssignmentsProvider).length, 3, reason: 'all default');

      container.read(selectedFilterProvider.notifier).state = 'notStarted';
      final notStarted = container.read(filteredAssignmentsProvider);
      expect(notStarted.length, 1);
      expect(notStarted.first.id, 'ns');

      container.read(selectedFilterProvider.notifier).state = 'inProgress';
      expect(container.read(filteredAssignmentsProvider).single.id, 'ip');

      container.read(selectedFilterProvider.notifier).state = 'completed';
      expect(container.read(filteredAssignmentsProvider).single.id, 'done');
    });
  });
}
