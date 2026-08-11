import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/subject_colors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/app_input_field.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/class_model.dart';
import '../providers/timetable_provider.dart';
import 'day_tab_row.dart';

Future<void> showAddEditClassSheet(BuildContext context, WidgetRef ref, {ClassModel? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    // Inherits AppColors.bgLayer + rounded-top shape from bottomSheetTheme.
    builder: (_) => _AddEditClassSheet(existing: existing),
  );
}

class _AddEditClassSheet extends ConsumerStatefulWidget {
  final ClassModel? existing;
  const _AddEditClassSheet({this.existing});

  @override
  ConsumerState<_AddEditClassSheet> createState() => _AddEditClassSheetState();
}

class _AddEditClassSheetState extends ConsumerState<_AddEditClassSheet> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _teacherController = TextEditingController();
  final _roomController = TextEditingController();

  String? _selectedDay;
  int _selectedPeriod = 1;
  Color _selectedColor = AppColors.primary;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _subjectController.text = existing.subject;
      _teacherController.text = existing.teacher;
      _roomController.text = existing.room;
      _selectedDay = existing.dayOfWeek;
      _selectedPeriod = existing.period;
      _selectedColor = Color(int.parse(existing.colorHex.replaceFirst('#', '0xFF')));
    } else {
      _selectedDay = kWeekdayKanji.first;
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _teacherController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  Future<void> _saveClass() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final existing = widget.existing;
    final uid = existing?.userId ?? ref.read(currentUserProvider)?.uid ?? '';
    final colorHex = '#${_selectedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    // Editing an existing class must preserve groupId/status/statusNote/statusDate
    // (shared-group membership + cancellation alerts) — only the form fields change.
    final model = existing != null
        ? existing.copyWith(
            subject: _subjectController.text.trim(),
            teacher: _teacherController.text.trim(),
            room: _roomController.text.trim(),
            dayOfWeek: _selectedDay ?? kWeekdayKanji.first,
            period: _selectedPeriod,
            colorHex: colorHex,
          )
        : ClassModel(
            id: const Uuid().v4(),
            userId: uid,
            subject: _subjectController.text.trim(),
            teacher: _teacherController.text.trim(),
            room: _roomController.text.trim(),
            dayOfWeek: _selectedDay ?? kWeekdayKanji.first,
            period: _selectedPeriod,
            colorHex: colorHex,
            createdAt: DateTime.now(),
          );
    final error = existing != null
        ? await ref.read(timetableNotifierProvider.notifier).updateClass(model)
        : await ref.read(timetableNotifierProvider.notifier).addClass(model);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.pop(context);
    toastification.show(
      context: context,
      type: ToastificationType.success,
      style: ToastificationStyle.flat,
      title: Text(existing != null ? '授業を更新しました' : '授業を追加しました'),
      autoCloseDuration: const Duration(seconds: 2),
    );
  }

  Future<void> _deleteClass() async {
    final existing = widget.existing;
    if (existing == null) return;
    final ok = await showConfirmDialog(context, title: '授業を削除', message: '${existing.subject}を削除しますか？');
    if (!ok) return;
    await ref.read(timetableNotifierProvider.notifier).deleteClass(existing.id);
    if (!mounted) return;
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
                  Text(existing != null ? '授業を編集' : '授業を追加', style: AppTextStyles.h2),
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
                  Text('科目名', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Autocomplete<String>(
                    optionsBuilder: (value) {
                      if (value.text.isEmpty) return SubjectColors.all;
                      return SubjectColors.all.where((s) => s.contains(value.text));
                    },
                    onSelected: (value) => setState(() => _subjectController.text = value),
                    fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                      controller.text = _subjectController.text;
                      controller.selection = TextSelection.collapsed(offset: controller.text.length);
                      return AppInputField(
                        controller: controller,
                        focusNode: focusNode,
                        hintText: '例：数学',
                        onChanged: (v) => _subjectController.text = v,
                        validator: (_) => _subjectController.text.trim().isEmpty ? '科目名を入力してください' : null,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('担当教員', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  AppInputField(controller: _teacherController, hintText: '例：田中先生'),
                  const SizedBox(height: 16),
                  Text('教室番号', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  AppInputField(controller: _roomController, hintText: '例：A-201'),
                  const SizedBox(height: 16),
                  Text('曜日', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Row(
                    children: List.generate(kWeekdayKanji.length, (i) {
                      // Stored/compared value stays the canonical kanji key;
                      // only the displayed label follows the app's locale.
                      final day = kWeekdayKanji[i];
                      final label = DayTabRow.days[i];
                      final selected = day == _selectedDay;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedDay = day),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: selected ? AppColors.primary : AppColors.surfaceVar,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: selected ? Colors.white : AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  Text('時限', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    initialValue: _selectedPeriod,
                    items: List.generate(6, (i) => i + 1)
                        .map((p) => DropdownMenuItem(value: p, child: Text('$p限')))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedPeriod = v ?? 1),
                    dropdownColor: AppColors.bgLayer,
                    style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.bgInput,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.borderPrimary, width: 1.5)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.borderPrimary, width: 1.5)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primaryMid, width: 2)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('カラー', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Row(
                    children: SubjectColors.colorOptions.map((c) {
                      final selected = c.toARGB32() == _selectedColor.toARGB32();
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedColor = c),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: selected ? Border.all(color: c, width: 3) : null,
                              boxShadow: selected ? [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 6)] : null,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (existing != null) ...[
                    const SizedBox(height: 20),
                    Center(
                      child: TextButton(
                        onPressed: _deleteClass,
                        child: const Text('削除', style: TextStyle(color: AppColors.danger)),
                      ),
                    ),
                  ],
                  const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(height: 1)),
                  ElevatedButton(
                    onPressed: _saveClass,
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
