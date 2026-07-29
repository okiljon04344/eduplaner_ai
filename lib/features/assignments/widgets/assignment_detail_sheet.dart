import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/subject_pill.dart';
import '../models/assignment_model.dart';
import '../providers/assignments_provider.dart';
import 'add_edit_assignment_sheet.dart';

Future<void> showAssignmentDetailSheet(BuildContext context, WidgetRef ref, AssignmentModel assignment) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    // backgroundColor/shape inherited from the app's dark bottomSheetTheme.
    builder: (_) => _AssignmentDetailSheet(assignment: assignment),
  );
}

class _AssignmentDetailSheet extends ConsumerStatefulWidget {
  final AssignmentModel assignment;
  const _AssignmentDetailSheet({required this.assignment});

  @override
  ConsumerState<_AssignmentDetailSheet> createState() => _AssignmentDetailSheetState();
}

class _AssignmentDetailSheetState extends ConsumerState<_AssignmentDetailSheet> {
  late double _progress;
  late AssignmentStatus _status;

  @override
  void initState() {
    super.initState();
    _progress = widget.assignment.progress;
    _status = widget.assignment.status;
  }

  void _onProgressChanged(double value) {
    setState(() => _progress = value);
    ref.read(assignmentsNotifierProvider.notifier).updateProgress(widget.assignment.id, value);
  }

  void _onStatusChanged(AssignmentStatus status) {
    setState(() => _status = status);
    ref.read(assignmentsNotifierProvider.notifier).updateStatus(widget.assignment.id, status);
  }

  Future<void> _edit() async {
    Navigator.pop(context);
    await showAddEditAssignmentSheet(context, ref, existing: widget.assignment);
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(context, title: '課題を削除', message: '${widget.assignment.title}を削除しますか？');
    if (!ok) return;
    await ref.read(assignmentsNotifierProvider.notifier).delete(widget.assignment.id);
    if (!mounted) return;
    Navigator.pop(context);
    toastification.show(
      context: context,
      type: ToastificationType.success,
      style: ToastificationStyle.flat,
      title: const Text('課題を削除しました'),
      autoCloseDuration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assignment = widget.assignment;
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom + 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SubjectPill(subject: assignment.subject),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(color: AppColors.surfaceVar, shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 18, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Text(assignment.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('提出: ${assignment.dueDateLabel}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: assignment.dueDateBgColor, borderRadius: BorderRadius.circular(20)),
                      child: Text(assignment.dueDateLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: assignment.dueDateColor)),
                    ),
                  ],
                ),
                if (assignment.description != null && assignment.description!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(assignment.description ?? '', style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('進捗', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    Text('${(_progress * 100).round()}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ],
                ),
                Slider(value: _progress, min: 0, max: 1, divisions: 10, activeColor: AppColors.primary, onChanged: _onProgressChanged),
                const SizedBox(height: 12),
                const Text('ステータス', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                Row(
                  children: AssignmentStatus.values.map((s) {
                    final selected = s == _status;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s.label),
                        selected: selected,
                        onSelected: (_) => _onStatusChanged(s),
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w500),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: _edit, child: const Text('編集'))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _delete,
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
