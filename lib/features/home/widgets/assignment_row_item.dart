import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/pressable.dart';
import '../../assignments/models/assignment_model.dart';
import '../../assignments/widgets/animated_assignment_check.dart';
import '../../assignments/widgets/assignment_actions.dart';
import '../../assignments/widgets/assignment_detail_sheet.dart';

/// One row in [UpcomingAssignmentsList]: a circular checkbox (tap toggles
/// completion directly) and title + colored deadline text.
class AssignmentRowItem extends ConsumerWidget {
  final AssignmentModel assignment;
  final bool showDivider;
  const AssignmentRowItem({super.key, required this.assignment, this.showDivider = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDone = assignment.status == AssignmentStatus.completed;
    return RepaintBoundary(
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Pressable(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => toggleAssignmentDone(context, ref, assignment),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: AnimatedAssignmentCheck(
                          isCompleted: isDone,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Pressable(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => showAssignmentDetailSheet(context, ref, assignment),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              assignment.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: isDone ? AppColors.textMuted : AppColors.textPrimary,
                                decoration: isDone ? TextDecoration.lineThrough : TextDecoration.none,
                                fontFamily: 'Plus Jakarta Sans',
                                fontFamilyFallback: const ['NotoSansJP'],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              assignment.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                fontFamily: 'Plus Jakarta Sans',
                                fontFamilyFallback: const ['NotoSansJP'],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    assignment.dueDateLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDone ? AppColors.textMuted : assignment.dueDateColor,
                      fontFamily: 'Plus Jakarta Sans',
                      fontFamilyFallback: const ['NotoSansJP'],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showDivider) Divider(height: 1, thickness: 1, color: AppColors.cardStroke),
        ],
      ),
    );
  }
}
