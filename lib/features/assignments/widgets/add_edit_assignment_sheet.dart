import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/subject_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_helper.dart';
import '../../../shared/widgets/app_input_field.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/star_rating.dart';
import '../../auth/providers/auth_provider.dart';
import '../../timetable/providers/timetable_provider.dart';
import '../models/assignment_model.dart';
import '../providers/assignments_provider.dart';
import 'assignment_actions.dart';

Future<void> showAddEditAssignmentSheet(BuildContext context, WidgetRef ref, {AssignmentModel? existing}) {
  // backgroundColor and shape come from bottomSheetTheme.
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
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
  final _subjectController = TextEditingController();

  DateTime? _selectedDate;
  double _progress = 0.0;
  AssignmentStatus _status = AssignmentStatus.notStarted;
  int _difficulty = 1;

  /// True while a save/delete write is in flight — disables the buttons and
  /// makes [_save] ignore re-entry so a double tap can't create two docs.
  bool _saving = false;

  /// Set on the first save attempt so the due-date field doesn't start out
  /// with an error border before the user has done anything.
  bool _triedSave = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _titleController.text = existing.title;
      _descriptionController.text = existing.description ?? '';
      _subjectController.text = existing.subject;
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
    _subjectController.dispose();
    super.dispose();
  }

  /// Autocomplete suggestions only; any typed subject is accepted. Combines the
  /// built-in subjects with those in the student's timetable.
  List<String> _subjectSuggestions() {
    final fromClasses = (ref.read(timetableStreamProvider).valueOrNull ?? []).map((c) => c.subject);
    return {...SubjectColors.all, ...fromClasses}.where((s) => s.trim().isNotEmpty).toList();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _selectedDate ?? now;
    // showDatePicker asserts unless the range contains initialDate, and an edited
    // assignment can be due outside the usual window.
    final firstDate = initial.isBefore(now.subtract(const Duration(days: 365))) ? initial : now.subtract(const Duration(days: 365));
    final lastDate = initial.isAfter(now.add(const Duration(days: 365 * 2))) ? initial : now.add(const Duration(days: 365 * 2));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    // Rebuild so the due-date border reflects the failed attempt even when
    // the text-field validators below are what stops the save.
    setState(() => _triedSave = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedDate == null) return;
    setState(() => _saving = true);
    final existing = widget.existing;
    final uid = existing?.userId ?? ref.read(currentUserProvider)?.uid ?? '';
    final model = AssignmentModel(
      id: existing?.id ?? const Uuid().v4(),
      userId: uid,
      title: _titleController.text.trim(),
      subject: _subjectController.text.trim(),
      description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      dueDate: _selectedDate ?? DateTime.now(),
      status: _status,
      difficulty: _difficulty,
      progress: _progress,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );
    final notifier = ref.read(assignmentsNotifierProvider.notifier);
    final error = existing != null ? await notifier.updateAssignment(model) : await notifier.add(model);
    if (!mounted) return;
    if (error != null) {
      setState(() => _saving = false);
      showAssignmentErrorToast(context, error);
      return;
    }
    Navigator.pop(context);
    toastification.show(
      context: context,
      type: ToastificationType.success,
      style: ToastificationStyle.flat,
      title: Text(existing != null ? AppStrings.t('as_updated') : AppStrings.t('as_added')),
      autoCloseDuration: const Duration(seconds: 2),
    );
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null || _saving) return;
    final ok = await showConfirmDialog(context, title: AppStrings.t('as_delete_title'), message: AppStrings.t('as_delete_confirm', {'title': existing.title}));
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    final error = await ref.read(assignmentsNotifierProvider.notifier).delete(existing.id);
    if (!mounted) return;
    if (error != null) {
      setState(() => _saving = false);
      showAssignmentErrorToast(context, error);
      return;
    }
    Navigator.pop(context);
    toastification.show(
      context: context,
      type: ToastificationType.success,
      style: ToastificationStyle.flat,
      title: Text(AppStrings.t('as_deleted')),
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
                decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    existing != null ? AppStrings.t('as_edit_title') : AppStrings.t('as_add_title'),
                    style: AppTextStyles.h2,
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: AppColors.surfaceVar, shape: BoxShape.circle),
                      child: Icon(Icons.close, size: 18, color: AppColors.textPrimary),
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
                  Text(AppStrings.t('fld_subject'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Autocomplete<String>(
                    // Seeded once; fieldViewBuilder must not reassign the text
                    // or every rebuild would move the cursor to the end.
                    initialValue: TextEditingValue(text: _subjectController.text),
                    optionsBuilder: (value) {
                      final suggestions = _subjectSuggestions();
                      if (value.text.isEmpty) return suggestions;
                      return suggestions.where((s) => s.contains(value.text));
                    },
                    onSelected: (value) => setState(() => _subjectController.text = value),
                    fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                      return AppInputField(
                        controller: controller,
                        focusNode: focusNode,
                        maxLength: 100,
                        hintText: AppStrings.t('fld_subject_hint_free'),
                        onChanged: (v) => _subjectController.text = v,
                        validator: (_) => _subjectController.text.trim().isEmpty ? AppStrings.t('val_subject_required') : null,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(AppStrings.t('fld_assign_title'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  AppInputField(
                    controller: _titleController,
                    hintText: AppStrings.t('fld_assign_title_hint'),
                    maxLength: 500,
                    validator: (v) => (v == null || v.trim().isEmpty) ? AppStrings.t('val_assign_title_required') : null,
                  ),
                  const SizedBox(height: 16),
                  Text(AppStrings.t('fld_memo'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  AppInputField(controller: _descriptionController, hintText: AppStrings.t('fld_memo_hint'), maxLines: 3),
                  const SizedBox(height: 16),
                  Text(AppStrings.t('fld_due'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        border: Border.all(color: _triedSave && _selectedDate == null ? AppColors.danger : AppColors.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.accentText),
                          const SizedBox(width: 10),
                          Text(
                            _selectedDate != null ? DateHelper.formatJapaneseDate(_selectedDate ?? DateTime.now()) : AppStrings.t('fld_pick_date'),
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
                        Text(AppStrings.t('fld_progress'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                        Text('${(_progress * 100).round()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accentText)),
                      ],
                    ),
                    Slider(
                      value: _progress,
                      min: 0,
                      max: 1,
                      divisions: 10,
                      activeColor: AppColors.primary,
                      onChanged: (v) => setState(() {
                        _progress = v;
                        _status = AssignmentModel.statusForProgress(v);
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text(AppStrings.t('fld_status'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    // Same chips as the detail sheet; SegmentedButton looked cramped here.
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: AssignmentStatus.values.map((st) {
                        final selected = st == _status;
                        return ChoiceChip(
                          label: Text(st.label),
                          selected: selected,
                          onSelected: (_) => setState(() {
                            _status = st;
                            _progress = AssignmentModel.progressForStatus(_status, _progress);
                          }),
                          selectedColor: AppColors.primary,
                          checkmarkColor: AppColors.onPrimary,
                          labelStyle: TextStyle(color: selected ? AppColors.onPrimary : AppColors.textPrimary, fontWeight: FontWeight.w500),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(AppStrings.t('fld_difficulty'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                      StarRating(initialRating: _difficulty, onChanged: (v) => setState(() => _difficulty = v)),
                    ],
                  ),
                  if (existing != null) ...[
                    const SizedBox(height: 20),
                    Center(
                      child: TextButton(
                        onPressed: _saving ? null : _delete,
                        child: Text(AppStrings.t('common_delete'), style: const TextStyle(color: AppColors.danger)),
                      ),
                    ),
                  ],
                  const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(height: 1)),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(existing != null ? AppStrings.t('btn_update') : AppStrings.t('btn_save')),
                    ),
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
