import 'package:edu_planner_ai/features/assignments/models/assignment_model.dart';
import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../support/fakes.dart';

void main() {
  group('progressForStatus', () {
    test('completed → 1.0 regardless of progress', () {
      expect(AssignmentModel.progressForStatus(AssignmentStatus.completed, 0.0), 1.0);
      expect(AssignmentModel.progressForStatus(AssignmentStatus.completed, 0.4), 1.0);
    });

    test('notStarted → 0.0 regardless of progress', () {
      expect(AssignmentModel.progressForStatus(AssignmentStatus.notStarted, 0.7), 0.0);
      expect(AssignmentModel.progressForStatus(AssignmentStatus.notStarted, 1.0), 0.0);
    });

    test('inProgress keeps progress strictly inside (0, 1)', () {
      expect(AssignmentModel.progressForStatus(AssignmentStatus.inProgress, 0.4), 0.4);
      expect(AssignmentModel.progressForStatus(AssignmentStatus.inProgress, 0.0), 0.1);
      expect(AssignmentModel.progressForStatus(AssignmentStatus.inProgress, 1.0), 0.9);
    });
  });

  group('statusForProgress', () {
    test('0 → notStarted, (0,1) → inProgress, >= 1 → completed', () {
      expect(AssignmentModel.statusForProgress(0.0), AssignmentStatus.notStarted);
      expect(AssignmentModel.statusForProgress(0.1), AssignmentStatus.inProgress);
      expect(AssignmentModel.statusForProgress(0.99), AssignmentStatus.inProgress);
      expect(AssignmentModel.statusForProgress(1.0), AssignmentStatus.completed);
    });
  });

  group('withStatus / withProgress', () {
    test('unticking a completed item resets it to notStarted at 0', () {
      final done = buildAssignment(status: AssignmentStatus.completed, progress: 1.0);
      final undone = done.withStatus(AssignmentStatus.notStarted);
      expect(undone.status, AssignmentStatus.notStarted);
      expect(undone.progress, 0.0);
    });

    test('ticking an in-progress item completes it at 1.0', () {
      final item = buildAssignment(status: AssignmentStatus.inProgress, progress: 0.4);
      final done = item.withStatus(AssignmentStatus.completed);
      expect(done.status, AssignmentStatus.completed);
      expect(done.progress, 1.0);
    });

    test('moving a completed item to inProgress drops it to 0.9', () {
      final done = buildAssignment(status: AssignmentStatus.completed, progress: 1.0);
      final item = done.withStatus(AssignmentStatus.inProgress);
      expect(item.status, AssignmentStatus.inProgress);
      expect(item.progress, 0.9);
    });

    test('dragging progress derives the status', () {
      final item = buildAssignment(status: AssignmentStatus.notStarted);
      expect(item.withProgress(0.5).status, AssignmentStatus.inProgress);
      expect(item.withProgress(1.0).status, AssignmentStatus.completed);
      expect(item.withProgress(0.5).withProgress(0.0).status, AssignmentStatus.notStarted);
    });

    test('other fields are untouched', () {
      final item = buildAssignment(id: 'x', title: 'T', difficulty: 3);
      final next = item.withStatus(AssignmentStatus.completed);
      expect(next.id, 'x');
      expect(next.title, 'T');
      expect(next.difficulty, 3);
    });
  });

  group('due label', () {
    test('a finished overdue task is not flagged overdue', () async {
      await initializeDateFormatting(null);
      final due = DateTime.now().subtract(const Duration(days: 3));
      final open = buildAssignment(status: AssignmentStatus.notStarted, dueDate: due);
      final done = open.withStatus(AssignmentStatus.completed);
      expect(open.dueDateColor, AppColors.danger);
      expect(done.dueDateColor, AppColors.textMuted);
      expect(done.dueDateLabel, isNot(open.dueDateLabel));
    });
  });
}
