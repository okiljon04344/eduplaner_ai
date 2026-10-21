import 'package:edu_planner_ai/features/assignments/models/assignment_model.dart';
import 'package:edu_planner_ai/features/assignments/providers/assignments_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

/// Noon, [offset] calendar days from today. Built with calendar arithmetic
/// (not `Duration`) so the tests are stable across DST changes.
DateTime _day(int offset) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + offset, 12);
}

Future<ProviderContainer> _hydrated(List<AssignmentModel> assignments) async {
  final container = ProviderContainer(
    overrides: [assignmentsStreamProvider.overrideWith((_) => Stream.value(assignments))],
  );
  addTearDown(container.dispose);
  await container.read(assignmentsStreamProvider.future);
  return container;
}

void main() {
  group('urgentAssignmentsCountProvider', () {
    test('counts overdue (any age) and items due within 3 days; skips later and completed', () async {
      final container = await _hydrated([
        buildAssignment(id: 'ancient', dueDate: _day(-90)),
        buildAssignment(id: 'yesterday', dueDate: _day(-1)),
        buildAssignment(id: 'today', dueDate: _day(0)),
        buildAssignment(id: 'in3', dueDate: _day(3)),
        buildAssignment(id: 'in4', dueDate: _day(4)),
        buildAssignment(id: 'doneOverdue', dueDate: _day(-2), status: AssignmentStatus.completed),
      ]);
      expect(container.read(urgentAssignmentsCountProvider), 4);
    });

    test('is 0 for an empty list', () async {
      final container = await _hydrated(const []);
      expect(container.read(urgentAssignmentsCountProvider), 0);
    });
  });

  group('upcomingAssignmentsProvider', () {
    test('keeps incomplete items due within the last 7 days or later, sorted, max 3', () async {
      final container = await _hydrated([
        buildAssignment(id: 'in20', dueDate: _day(20)),
        buildAssignment(id: 'in2', dueDate: _day(2)),
        buildAssignment(id: 'ago8', dueDate: _day(-8)),
        buildAssignment(id: 'ago7', dueDate: _day(-7)),
        buildAssignment(id: 'ago30', dueDate: _day(-30)),
        buildAssignment(id: 'in5', dueDate: _day(5)),
        buildAssignment(id: 'doneSoon', dueDate: _day(1), status: AssignmentStatus.completed),
      ]);
      expect(container.read(upcomingAssignmentsProvider).map((a) => a.id), ['ago7', 'in2', 'in5']);
    });

    test('ancient overdue items never crowd out real upcoming ones', () async {
      final container = await _hydrated([
        for (var i = 0; i < 5; i++) buildAssignment(id: 'old$i', dueDate: _day(-60 - i)),
        buildAssignment(id: 'soon', dueDate: _day(1)),
      ]);
      expect(container.read(upcomingAssignmentsProvider).map((a) => a.id), ['soon']);
    });

    test('is empty when nothing qualifies', () async {
      final container = await _hydrated(const []);
      expect(container.read(upcomingAssignmentsProvider), isEmpty);
    });
  });

  group('weeklyProgressProvider window', () {
    test('Monday 00:00 .. next Monday 00:00: last Sunday 23:59 out, this Monday 00:00 in, next Monday 00:00 out', () async {
      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
      final container = await _hydrated([
        buildAssignment(id: 'lastSunday', dueDate: DateTime(monday.year, monday.month, monday.day - 1, 23, 59)),
        buildAssignment(id: 'thisMonday', dueDate: monday),
        buildAssignment(id: 'nextMonday', dueDate: DateTime(monday.year, monday.month, monday.day + 7)),
      ]);
      expect(container.read(weeklyProgressProvider).total, 1);
    });
  });
}
