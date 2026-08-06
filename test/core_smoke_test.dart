import 'package:edu_planner_ai/core/constants/subject_colors.dart';
import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/assignments/models/assignment_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('design tokens and status helpers are available', () {
    expect(AppColors.primary.toARGB32(), 0xFF7C3AED);
    expect(SubjectColors.of('数学').text, AppColors.mathText);
    expect(AssignmentStatus.inProgress.firestoreValue, 'inProgress');
    expect(AssignmentStatus.fromString('completed'), AssignmentStatus.completed);
  });
}
