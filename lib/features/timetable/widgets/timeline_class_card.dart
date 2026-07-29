import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/subject_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../models/class_model.dart';
import '../providers/timetable_provider.dart';
import 'add_edit_class_sheet.dart';
import 'class_detail_sheet.dart';

/// Display-only clock times per period. [ClassModel] only stores a period
/// index (1-6); the design shows real start/end times, so this is a local
/// lookup table of standard 90-minute class blocks — presentation only.
const Map<int, (String start, String end)> kPeriodTimes = {
  1: ('09:00', '10:30'),
  2: ('10:40', '12:10'),
  3: ('13:00', '14:30'),
  4: ('14:40', '16:10'),
  5: ('16:20', '17:50'),
  6: ('18:00', '19:30'),
};

/// One row of the schedule timeline: a time column (start time, gradient
/// connector line, end time) beside a glass class card with a colored left
/// border, subject name, room · teacher line, and a period tag pill.
class TimelineClassCard extends ConsumerWidget {
  final ClassModel classModel;
  const TimelineClassCard({super.key, required this.classModel});

  Future<void> _onLongPress(BuildContext context, WidgetRef ref, Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        overlay.size.width - globalPosition.dx,
        overlay.size.height - globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(value: 'edit', child: Text('編集')),
        PopupMenuItem(value: 'delete', child: Text('削除')),
      ],
    );
    if (!context.mounted) return;
    if (selected == 'edit') {
      showAddEditClassSheet(context, ref, existing: classModel);
    } else if (selected == 'delete') {
      final ok = await showConfirmDialog(context, title: '授業を削除', message: '${classModel.subject}を削除しますか？');
      if (ok) {
        await ref.read(timetableNotifierProvider.notifier).deleteClass(classModel.id);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = SubjectColors.of(classModel.subject);
    final times = kPeriodTimes[classModel.period] ?? ('--:--', '--:--');

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: () => showClassDetailSheet(context, ref, classModel),
        onLongPressStart: (details) => _onLongPress(context, ref, details.globalPosition),
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
                        times.$1,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryMid),
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
                              colors: [AppColors.primaryMid.withValues(alpha: 0.5), AppColors.primaryMid.withValues(alpha: 0)],
                            ),
                          ),
                        ),
                      ),
                      Text(
                        times.$2,
                        style: TextStyle(fontSize: 10, color: AppColors.primaryMid.withValues(alpha: 0.3)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVar,
                      border: Border(
                        top: const BorderSide(color: AppColors.border),
                        right: const BorderSide(color: AppColors.border),
                        bottom: const BorderSide(color: AppColors.border),
                        left: BorderSide(color: style.dot, width: 3),
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
                                  colors: [style.fill, style.fill.withValues(alpha: 0)],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                classModel.subject,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${classModel.room} · ${classModel.teacher}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: style.fill,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: style.dot.withValues(alpha: 0.25)),
                                ),
                                child: Text(
                                  '${classModel.period}限',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: style.text),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
