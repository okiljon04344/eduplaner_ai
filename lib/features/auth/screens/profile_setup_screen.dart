import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:toastification/toastification.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_input_field.dart';
import '../models/school_type.dart';
import '../providers/auth_provider.dart';

/// School-profile step: school type first, then only the fields that type has
/// (program, grade, faculty, department, course; see [SchoolType]).
///
/// Reached two ways:
///  - Router redirect while `profileComplete` is false: blocking, no way out
///    until saved.
///  - Pushed from Settings to edit a complete profile: normal back button,
///    pops on save.
/// The mode is captured once in [initState] so the AppBar doesn't change
/// mid-edit when the save flips `profileComplete`.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _schoolNameCtrl = TextEditingController();
  final _facultyCtrl = TextEditingController();
  final _departmentCtrl = TextEditingController();
  final _courseCtrl = TextEditingController();

  late final bool _isEditing;
  SchoolType? _selectedType;
  String? _program;
  int? _grade;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _isEditing = user?.profileComplete ?? false;
    _selectedType = SchoolType.fromKey(user?.schoolType);
    _schoolNameCtrl.text = user?.school ?? '';
    final type = _selectedType;
    if (type != null) {
      _program = type.programs.contains(user?.program)
          ? user!.program
          : type.defaultProgram;
      final grade = SchoolType.parseGrade(user?.grade);
      _grade = (grade != null && grade >= 1 && grade <= type.maxGrade(_program))
          ? grade
          : null;
    }
    _facultyCtrl.text = user?.faculty ?? '';
    _departmentCtrl.text = user?.department ?? '';
    _courseCtrl.text = user?.course ?? '';
  }

  @override
  void dispose() {
    _schoolNameCtrl.dispose();
    _facultyCtrl.dispose();
    _departmentCtrl.dispose();
    _courseCtrl.dispose();
    super.dispose();
  }

  void _selectType(SchoolType t) {
    // Keep the current program when it is also valid for the new type.
    _program = t.programs.contains(_program) ? _program : t.defaultProgram;
    _selectedType = t;
    _clampGrade();
  }

  void _clampGrade() {
    if (_grade != null && _grade! > _selectedType!.maxGrade(_program)) {
      _grade = null;
    }
  }

  Widget _label(String key) => Text(
        AppStrings.t(key),
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary),
      );

  Widget _chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(onTap),
        selectedColor: AppColors.primary,
        checkmarkColor: AppColors.onPrimary,
        labelStyle: TextStyle(
            color: selected ? AppColors.onPrimary : AppColors.textPrimary,
            fontWeight: FontWeight.w500),
      );

  Future<void> _submit() async {
    void errorToast(String key) => toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flat,
          title: Text(AppStrings.t(key)),
          autoCloseDuration: const Duration(seconds: 3),
        );
    final type = _selectedType;
    if (type == null) return errorToast('school_type_required');
    if (type.maxGrade(_program) > 0 && _grade == null) {
      return errorToast('school_grade_required');
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref.read(authNotifierProvider.notifier).saveSchoolProfile(
          schoolType: type.key,
          schoolName: _schoolNameCtrl.text,
          // Hidden fields are saved as null so they never keep stale values.
          grade: _grade == null ? null : '$_grade',
          program: type.programs.isEmpty ? null : _program,
          faculty: type.hasFaculty ? _facultyCtrl.text : null,
          department: type.hasDepartment ? _departmentCtrl.text : null,
          course: type.hasCourse ? _courseCtrl.text : null,
        );

    final state = ref.read(authNotifierProvider);
    if (!mounted) return;
    if (state.hasError) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        style: ToastificationStyle.flat,
        title: Text(AppStrings.t('school_setup_error')),
        description: Text(state.error.toString().replaceAll('Exception: ', '')),
        autoCloseDuration: const Duration(seconds: 3),
      );
      return;
    }
    if (!mounted) return;
    // First-time setup leaves explicitly: the router is long-lived, so it no
    // longer re-runs from '/home' on auth changes to carry us there.
    // canPop: a web reload on /profile-setup leaves nothing to pop back to.
    _isEditing && context.canPop() ? context.pop() : context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authNotifierProvider).isLoading;
    final type = _selectedType;
    final maxGrade = type?.maxGrade(_program) ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        automaticallyImplyLeading: _isEditing,
        title: Text(
          AppStrings.t('school_setup_title'),
          style: const TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontFamilyFallback: ['NotoSansJP']),
        ),
      ),
      body: SafeArea(
        // Top-aligned (not centered) so toggling the faculty field never shifts the form.
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_isEditing) ...[
                      Text(
                        AppStrings.t('school_setup_subtitle'),
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontFamily: 'Plus Jakarta Sans',
                            fontFamilyFallback: const ['NotoSansJP']),
                      ),
                      const SizedBox(height: 24),
                    ],
                    _label('school_type_label'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: SchoolType.values
                          .map((t) =>
                              _chip(t.label, t == type, () => _selectType(t)))
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                    _label('school_name_label'),
                    const SizedBox(height: 8),
                    AppInputField(
                      controller: _schoolNameCtrl,
                      hintText: AppStrings.t('school_name_hint'),
                      textInputAction: TextInputAction.next,
                      validator: Validators.required,
                      maxLength: 100,
                    ),
                    if (type != null && type.programs.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _label('school_program_label'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: type.programs
                            .map((p) =>
                                _chip(AppStrings.t('program_$p'), p == _program,
                                    () {
                                  _program = p;
                                  _clampGrade();
                                }))
                            .toList(),
                      ),
                    ],
                    if (maxGrade > 0) ...[
                      const SizedBox(height: 16),
                      _label('school_grade_label'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 1; i <= maxGrade; i++)
                            _chip(AppStrings.t('school_grade_n', {'n': i}),
                                i == _grade, () => _grade = i),
                        ],
                      ),
                    ],
                    if (type != null && type.hasFaculty) ...[
                      const SizedBox(height: 16),
                      _label(type.facultyLabelKey),
                      const SizedBox(height: 8),
                      AppInputField(
                        controller: _facultyCtrl,
                        hintText: AppStrings.t(type.facultyHintKey),
                        textInputAction: TextInputAction.next,
                        maxLength: 100,
                      ),
                    ],
                    if (type != null && type.hasDepartment) ...[
                      const SizedBox(height: 16),
                      _label(type.departmentLabelKey),
                      const SizedBox(height: 8),
                      AppInputField(
                        controller: _departmentCtrl,
                        hintText: AppStrings.t(type.departmentHintKey),
                        textInputAction: type.hasCourse
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onSubmitted: type.hasCourse
                            ? null
                            : (_) => loading ? null : _submit(),
                        maxLength: 100,
                      ),
                    ],
                    if (type != null && type.hasCourse) ...[
                      const SizedBox(height: 16),
                      _label('school_course_label'),
                      const SizedBox(height: 8),
                      AppInputField(
                        controller: _courseCtrl,
                        hintText: AppStrings.t('school_course_hint'),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => loading ? null : _submit(),
                        maxLength: 100,
                      ),
                    ],
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: loading ? null : _submit,
                      child: loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: AppColors.onPrimary))
                          : Text(_isEditing
                              ? AppStrings.t('btn_save')
                              : AppStrings.t('school_setup_save_btn')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
