import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import '../../../core/constants/periods.dart';
import '../../../core/constants/subject_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/class_model.dart';
import '../providers/timetable_provider.dart';
import 'add_edit_class_sheet.dart';
import 'class_detail_sheet.dart';

/// One row of the schedule timeline: a time column (start time, gradient
/// connector line, end time) beside a glass class card with a colored left
/// border, subject name, room · teacher line, and a period tag pill.
///
/// [date] is the calendar day this card is displayed for; the 休講/変更 badge
/// shows only when the class's status applies to that date.
class TimelineClassCard extends ConsumerWidget {
  final ClassModel classModel;
  final DateTime date;
  const TimelineClassCard({super.key, required this.classModel, required this.date});

  Future<void> _onLongPress(
      BuildContext context, WidgetRef ref, Offset globalPosition) async {
    // Only the creator may edit/delete a row (Firestore rules enforce it too).
    if (classModel.userId != ref.read(currentUserProvider)?.uid) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        overlay.size.width - globalPosition.dx,
        overlay.size.height - globalPosition.dy,
      ),
      items: [
        PopupMenuItem(value: 'edit', child: Text(AppStrings.t('common_edit'))),
        PopupMenuItem(value: 'delete', child: Text(AppStrings.t('common_delete'))),
      ],
    );
    if (!context.mounted) return;
    if (selected == 'edit') {
      unawaited(showAddEditClassSheet(context, ref, existing: classModel));
    } else if (selected == 'delete') {
      final ok = await showConfirmDialog(context,
          title: AppStrings.t('tt_delete_class'),
          message: AppStrings.t('tt_delete_confirm').replaceAll('{subject}', classModel.subject));
      if (ok) {
        final error = await ref
            .read(timetableNotifierProvider.notifier)
            .deleteClass(classModel.id);
        if (error != null && context.mounted) {
          toastification.show(
            context: context,
            type: ToastificationType.error,
            style: ToastificationStyle.flat,
            title: Text(error),
            autoCloseDuration: const Duration(seconds: 2),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = SubjectColors.of(classModel.subject);
    final times = periodTimeLabels(classModel.period);
    final statusAlert = classModel.statusAppliesTo(date);

    return RepaintBoundary(child: Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: () => showClassDetailSheet(context, ref, classModel),
        onLongPressStart: (details) =>
            _onLongPress(context, ref, details.globalPosition),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 44,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    children: [
                      Text(
                        times.start,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.isDark
                              ? AppColors.primaryMid
                              : AppColors.primaryDark,
                        ),
                      ),
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          constraints: const BoxConstraints(minHeight: 16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppColors.primaryMid.withValues(alpha: 0.5),
                                AppColors.primaryMid.withValues(alpha: 0)
                              ],
                            ),
                          ),
                        ),
                      ),
                      Text(
                        times.end,
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.primaryMid.withValues(alpha: 0.3)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(AppColors.isDark ? 20 : 18),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(AppColors.isDark ? 20 : 18),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        border: Border(
                          top: BorderSide(
                              color: AppColors.isDark
                                  ? AppColors.border
                                  : Colors.transparent),
                          right: BorderSide(
                              color: AppColors.isDark
                                  ? AppColors.border
                                  : Colors.transparent),
                          bottom: BorderSide(
                              color: AppColors.isDark
                                  ? AppColors.border
                                  : Colors.transparent),
                          left: BorderSide(
                              color: style.dot,
                              width: AppColors.isDark ? 3 : 4),
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            top: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    colors: [
                                      style.fill,
                                      style.fill.withValues(alpha: 0)
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        classModel.subject,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.2,
                                            color: AppColors.textPrimary),
                                      ),
                                    ),
                                    if (statusAlert) ...[
                                      const SizedBox(width: 6),
                                      _StatusDot(
                                          cancelled: classModel.status ==
                                              ClassStatus.cancelled),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${classModel.room} · ${classModel.teacher}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: style.fill,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                            color: style.dot
                                                .withValues(alpha: 0.25)),
                                      ),
                                      child: Text(
                                        AppStrings.t('tt_period').replaceAll('{n}', '${classModel.period}'),
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: style.text),
                                      ),
                                    ),
                                    if (statusAlert) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: (classModel.status ==
                                                      ClassStatus.cancelled
                                                  ? AppColors.danger
                                                  : AppColors.warning)
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          classModel.status.label,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: classModel.status ==
                                                    ClassStatus.cancelled
                                                ? AppColors.danger
                                                : AppColors.warning,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}

class _StatusDot extends StatelessWidget {
  final bool cancelled;
  const _StatusDot({required this.cancelled});

  @override
  Widget build(BuildContext context) {
    final color = cancelled ? AppColors.danger : AppColors.warning;
    return Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }
}
