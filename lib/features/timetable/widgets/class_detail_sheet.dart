import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import '../../../core/constants/subject_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../models/class_model.dart';
import '../providers/timetable_provider.dart';
import 'add_edit_class_sheet.dart';

Future<void> showClassDetailSheet(BuildContext context, WidgetRef ref, ClassModel classModel) {
  return showModalBottomSheet(
    context: context,
    // Inherits AppColors.bgLayer + rounded-top shape from bottomSheetTheme.
    builder: (_) => _ClassDetailSheet(classModel: classModel),
  );
}

class _ClassDetailSheet extends ConsumerWidget {
  final ClassModel classModel;
  const _ClassDetailSheet({required this.classModel});

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context);
    await showAddEditClassSheet(context, ref, existing: classModel);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(context, title: '授業を削除', message: '${classModel.subject}を削除しますか？');
    if (!ok) return;
    await ref.read(timetableNotifierProvider.notifier).deleteClass(classModel.id);
    if (!context.mounted) return;
    Navigator.pop(context);
    toastification.show(
      context: context,
      type: ToastificationType.success,
      style: ToastificationStyle.flat,
      title: const Text('授業を削除しました'),
      autoCloseDuration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = SubjectColors.of(classModel.subject);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: style.fill,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Text(classModel.subject, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: style.text)),
                const SizedBox(height: 6),
                Text('${classModel.teacher}先生', style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(classModel.room, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _InfoRow(icon: Icons.event, label: '${classModel.dayOfWeek}曜日 ${classModel.period}限'),
                const SizedBox(height: 10),
                _InfoRow(icon: Icons.person_outline, label: '${classModel.teacher}先生'),
                const SizedBox(height: 10),
                _InfoRow(icon: Icons.location_on_outlined, label: classModel.room),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(onPressed: () => _edit(context, ref), child: const Text('編集')),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _delete(context, ref),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.danger), foregroundColor: AppColors.danger),
                        child: const Text('削除'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
      ],
    );
  }
}
