import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/subject_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../models/assignment_model.dart';
import '../providers/assignments_provider.dart';
import 'assignment_detail_sheet.dart';
import 'progress_bar_row.dart';

class AssignmentCard extends ConsumerWidget {
  final AssignmentModel assignment;
  const AssignmentCard({super.key, required this.assignment});

  void _toggleDone(WidgetRef ref) {
    final next = assignment.status == AssignmentStatus.completed
        ? AssignmentStatus.notStarted
        : AssignmentStatus.completed;
    ref.read(assignmentsNotifierProvider.notifier).updateStatus(assignment.id, next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCompleted = assignment.status == AssignmentStatus.completed;
    final subjectStyle = SubjectColors.of(assignment.subject);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, (1 - value) * 14), child: child),
      ),
      child: GestureDetector(
        onTap: () => showAssignmentDetailSheet(context, ref, assignment),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: AppColors.isDark ? AppColors.surfaceVar : AppColors.surface,
            borderRadius: BorderRadius.circular(AppColors.isDark ? 22 : 20),
            border: Border.all(color: AppColors.isDark ? AppColors.border : AppColors.cardBorder),
            boxShadow: AppColors.isDark ? null : AppColors.cardShadow,
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [assignment.dueDateColor.withValues(alpha: 0.08), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => _toggleDone(ref),
                      child: Container(
                        width: 28,
                        height: 28,
                        margin: const EdgeInsets.only(top: 1),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isCompleted
                                ? AppColors.primaryMid
                                : (AppColors.isDark
                                    ? Colors.white.withValues(alpha: 0.15)
                                    : AppColors.checkboxUnchecked),
                            width: 2,
                          ),
                          gradient: isCompleted ? AppColors.gradientPrimary : null,
                          boxShadow: isCompleted && AppColors.isDark
                              ? const [BoxShadow(color: Color(0x99A855F7), blurRadius: 12)]
                              : null,
                        ),
                        child: isCompleted ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            assignment.title,
                            style: TextStyle(
                              fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
                              fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.2,
                              color: isCompleted ? AppColors.textMuted : AppColors.textPrimary,
                              decoration: isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            assignment.subject,
                            style: TextStyle(
                              fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
                              fontSize: 12, fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ProgressBarRow(progress: assignment.progress, color: subjectStyle.dot),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${(assignment.progress * 100).round()}% 完了',
                                style: TextStyle(
                                  fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
                                  fontSize: 10, fontWeight: FontWeight.w600,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              Text(
                                assignment.dueDateLabel,
                                style: TextStyle(
                                  fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
                                  fontSize: 10, fontWeight: FontWeight.w700, color: assignment.dueDateColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: assignment.status.bgColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: assignment.status.borderColor),
                      ),
                      child: Text(
                        assignment.status.label,
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
                          fontSize: 10, fontWeight: FontWeight.w700, color: assignment.status.textColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
