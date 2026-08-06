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
    useRootNavigator: true,
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

  Future<void> _reportStatus(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<_StatusReport>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _StatusReportSheet(classModel: classModel),
    );
    if (result == null || !context.mounted) return;
    final error = await ref.read(timetableNotifierProvider.notifier).setStatus(
          classModel,
          status: result.status,
          statusNote: result.note,
        );
    if (!context.mounted) return;
    if (error != null) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        style: ToastificationStyle.flat,
        title: Text(error),
        autoCloseDuration: const Duration(seconds: 2),
      );
      return;
    }
    Navigator.pop(context);
    toastification.show(
      context: context,
      type: ToastificationType.success,
      style: ToastificationStyle.flat,
      title: Text(result.status == ClassStatus.cancelled ? '休講として通知しました' : '変更を通知しました'),
      autoCloseDuration: const Duration(seconds: 2),
    );
  }

  Future<void> _clearStatus(BuildContext context, WidgetRef ref) async {
    await ref.read(timetableNotifierProvider.notifier).setStatus(classModel, status: ClassStatus.normal);
    if (!context.mounted) return;
    Navigator.pop(context);
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
                Text('${classModel.teacher}先生', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(classModel.room, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (classModel.hasStatusAlertToday) ...[
                  _StatusBanner(classModel: classModel, onClear: () => _clearStatus(context, ref)),
                  const SizedBox(height: 16),
                ],
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
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () => _reportStatus(context, ref),
                    icon: const Icon(Icons.campaign_outlined, size: 18, color: AppColors.warning),
                    label: const Text('休講・変更を報告', style: TextStyle(color: AppColors.warning)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final ClassModel classModel;
  final VoidCallback onClear;
  const _StatusBanner({required this.classModel, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final cancelled = classModel.status == ClassStatus.cancelled;
    final color = cancelled ? AppColors.danger : AppColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(cancelled ? Icons.event_busy : Icons.info_outline, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('本日は${classModel.status.label}です', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                if (classModel.statusNote != null && classModel.statusNote!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(classModel.statusNote!, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: Text('取り消す', style: TextStyle(fontSize: 11, color: color, decoration: TextDecoration.underline)),
          ),
        ],
      ),
    );
  }
}

class _StatusReport {
  final ClassStatus status;
  final String? note;
  const _StatusReport(this.status, this.note);
}

class _StatusReportSheet extends StatefulWidget {
  final ClassModel classModel;
  const _StatusReportSheet({required this.classModel});

  @override
  State<_StatusReportSheet> createState() => _StatusReportSheetState();
}

class _StatusReportSheetState extends State<_StatusReportSheet> {
  ClassStatus _status = ClassStatus.cancelled;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.viewInsetsOf(context).bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.classModel.subject} — 本日の連絡', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatusChoiceChip(
                    label: '休講',
                    selected: _status == ClassStatus.cancelled,
                    color: AppColors.danger,
                    onTap: () => setState(() => _status = ClassStatus.cancelled),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatusChoiceChip(
                    label: '変更あり',
                    selected: _status == ClassStatus.changed,
                    color: AppColors.warning,
                    onTap: () => setState(() => _status = ClassStatus.changed),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              maxLines: 2,
              decoration: const InputDecoration(hintText: '例：教室がB-102に変更になりました', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, _StatusReport(_status, _noteController.text.trim().isEmpty ? null : _noteController.text.trim())),
                child: const Text('メンバーに通知する'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _StatusChoiceChip({required this.label, required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : AppColors.surfaceVar,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : AppColors.border),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? color : AppColors.textSecondary)),
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
        Text(label, style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
      ],
    );
  }
}
