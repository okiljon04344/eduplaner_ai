import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../assignments/models/assignment_model.dart';
import '../../assignments/providers/assignments_provider.dart';
import '../../assignments/widgets/assignment_detail_sheet.dart';

/// One row in [UpcomingAssignmentsList]: a circular checkbox (tap toggles
/// completion directly) and title + colored deadline text.
class AssignmentRowItem extends ConsumerWidget {
  final AssignmentModel assignment;
  final bool showDivider;
  const AssignmentRowItem({super.key, required this.assignment, this.showDivider = true});

  void _toggleDone(WidgetRef ref) {
    final next = assignment.status == AssignmentStatus.completed ? AssignmentStatus.notStarted : AssignmentStatus.completed;
    ref.read(assignmentsNotifierProvider.notifier).updateStatus(assignment.id, next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDone = assignment.status == AssignmentStatus.completed;
    return Column(
      children: [
        GestureDetector(
          onTap: () => showAssignmentDetailSheet(context, ref, assignment),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _toggleDone(ref),
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: isDone ? AppColors.gradientPrimary : null,
                      border: Border.all(
                        color: isDone ? AppColors.primaryMid : AppColors.checkboxUnchecked,
                        width: 2,
                      ),
                      boxShadow: isDone ? [BoxShadow(color: AppColors.primaryMid.withValues(alpha: 0.6), blurRadius: 12)] : null,
                    ),
                    child: isDone ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        assignment.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: isDone ? AppColors.textMuted : AppColors.textPrimary,
                          decoration: isDone ? TextDecoration.lineThrough : TextDecoration.none,
                          fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${assignment.subject} · ${assignment.dueDateLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w500,
                          color: assignment.dueDateColor,
                          fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showDivider) Divider(height: 1, color: AppColors.dividerSubtle),
      ],
    );
  }
}
