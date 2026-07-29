import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/subject_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_helper.dart';
import '../../../shared/widgets/app_input_field.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/star_rating.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/assignment_model.dart';
import '../providers/assignments_provider.dart';

Future<void> showAddEditAssignmentSheet(BuildContext context, WidgetRef ref, {AssignmentModel? existing}) {
  // backgroundColor/shape are inherited from the app's dark bottomSheetTheme.
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AddEditAssignmentSheet(existing: existing),
  );
}

class _AddEditAssignmentSheet extends ConsumerStatefulWidget {
  final AssignmentModel? existing;
  const _AddEditAssignmentSheet({this.existing});

  @override
  ConsumerState<_AddEditAssignmentSheet> createState() => _AddEditAssignmentSheetState();
}

class _AddEditAssignmentSheetState extends ConsumerState<_AddEditAssignmentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedSubject;
  DateTime? _selectedDate;
  double _progress = 0.0;
  AssignmentStatus _status = AssignmentStatus.notStarted;
  int _difficulty = 1;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _titleController.text = existing.title;
      _descriptionController.text = existing.description ?? '';
      _selectedSubject = existing.subject;
      _selectedDate = existing.dueDate;
      _progress = existing.progress;
      _status = existing.status;
      _difficulty = existing.difficulty;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      locale: const Locale('ja'),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedDate == null) {
      setState(() {});
      return;
    }
    final existing = widget.existing;
    final uid = existing?.userId ?? ref.read(currentUserProvider)?.uid ?? '';
    final model = AssignmentModel(
      id: existing?.id ?? const Uuid().v4(),
      userId: uid,
      title: _titleController.text.trim(),
      subject: _selectedSubject ?? SubjectColors.all.first,
      description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      dueDate: _selectedDate ?? DateTime.now(),
      status: _status,
      difficulty: _difficulty,
      progress: _progress,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );
    if (existing != null) {
      await ref.read(assignmentsNotifierProvider.notifier).updateAssignment(model);
    } else {
      await ref.read(assignmentsNotifierProvider.notifier).add(model);
    }
    if (!mounted) return;
    Navigator.pop(context);
    toastification.show(
      context: context,
      type: ToastificationType.success,
      style: ToastificationStyle.flat,
      title: Text(existing != null ? '課題を更新しました' : '課題を追加しました'),
      autoCloseDuration: const Duration(seconds: 2),
    );
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final ok = await showConfirmDialog(context, title: '課題を削除', message: '${existing.title}を削除しますか？');
    if (!ok) return;
    await ref.read(assignmentsNotifierProvider.notifier).delete(existing.id);
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
    final existing = widget.existing;
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom + 32),
      child: Form(
        key: _formKey,
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
                  Text(
                    existing != null ? '課題を編集' : '課題を追加',
                    style: AppTextStyles.h2,
                  ),
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
                  const SizedBox(height: 20),
                  const Text('科目名', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSubject,
                    validator: (v) => v == null ? '科目名を選択してください' : null,
                    items: SubjectColors.all.map((s) {
                      final style = SubjectColors.of(s);
                      return DropdownMenuItem(
                        value: s,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: style.dot, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Text(s),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedSubject = v),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('課題タイトル', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  AppInputField(
                    controller: _titleController,
                    hintText: '例：第3章 練習問題',
                    validator: (v) => (v == null || v.trim().isEmpty) ? '課題タイトルを入力してください' : null,
                  ),
                  const SizedBox(height: 16),
                  const Text('詳細メモ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  AppInputField(controller: _descriptionController, hintText: '補足メモを入力...', maxLines: 3),
                  const SizedBox(height: 16),
                  const Text('提出期限', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        border: Border.all(color: _selectedDate == null ? AppColors.danger : AppColors.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Text(
                            _selectedDate != null ? DateHelper.formatJapaneseDate(_selectedDate ?? DateTime.now()) : '日付を選択',
                            style: TextStyle(
                              fontSize: 14,
                              color: _selectedDate != null ? AppColors.textPrimary : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (existing != null) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('進捗', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                        Text('${(_progress * 100).round()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      ],
                    ),
                    Slider(
                      value: _progress,
                      min: 0,
                      max: 1,
                      divisions: 10,
                      activeColor: AppColors.primary,
                      onChanged: (v) => setState(() => _progress = v),
                    ),
                    const SizedBox(height: 8),
                    const Text('ステータス', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    SegmentedButton<AssignmentStatus>(
                      segments: const [
                        ButtonSegment(value: AssignmentStatus.notStarted, label: Text('未着手')),
                        ButtonSegment(value: AssignmentStatus.inProgress, label: Text('進行中')),
                        ButtonSegment(value: AssignmentStatus.completed, label: Text('完了')),
                      ],
                      selected: {_status},
                      onSelectionChanged: (s) => setState(() => _status = s.first),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('難易度', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                      StarRating(initialRating: _difficulty, onChanged: (v) => setState(() => _difficulty = v)),
                    ],
                  ),
                  if (existing != null) ...[
                    const SizedBox(height: 20),
                    Center(
                      child: TextButton(
                        onPressed: _delete,
                        child: const Text('削除', style: TextStyle(color: AppColors.danger)),
                      ),
                    ),
                  ],
                  const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(height: 1)),
                  ElevatedButton(
                    onPressed: _save,
                    child: Text(existing != null ? '更新する' : '保存する'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
