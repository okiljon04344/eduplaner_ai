import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import '../models/assignment_model.dart';
import '../providers/assignments_provider.dart';

/// Shows a flat error toast — shared by every assignment write that can fail.
void showAssignmentErrorToast(BuildContext context, String message) {
  toastification.show(
    context: context,
    type: ToastificationType.error,
    style: ToastificationStyle.flat,
    title: Text(message),
    autoCloseDuration: const Duration(seconds: 3),
  );
}

/// Checkbox behaviour shared by the assignments list and the home quick-view:
/// completed → notStarted (progress 0), anything else → completed (progress 1).
/// Status and progress are written together; a failed write shows an error toast.
Future<void> toggleAssignmentDone(BuildContext context, WidgetRef ref, AssignmentModel assignment) async {
  final next = assignment.status == AssignmentStatus.completed
      ? AssignmentStatus.notStarted
      : AssignmentStatus.completed;
  final error = await ref.read(assignmentsNotifierProvider.notifier).updateStatus(assignment, next);
  if (error != null && context.mounted) showAssignmentErrorToast(context, error);
}
