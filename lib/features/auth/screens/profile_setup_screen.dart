import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:toastification/toastification.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_input_field.dart';
import '../models/school_type.dart';
import '../providers/auth_provider.dart';

/// Mandatory school-profile step: school type, name, grade, and (depending
/// on type) faculty/department/course, matching how Japanese educational
/// institutions are actually structured (高校/専門学校 have 学科 directly,
/// 大学/大学院 have 学部 above 学科).
///
/// Reached two ways:
///  - Router redirect right after sign-up/onboarding, while
///    `currentUserProvider`'s `profileComplete` is still false — blocking,
///    no way to leave until saved (the router itself won't route anywhere
///    else while incomplete).
///  - Pushed from Settings to edit an already-complete profile — normal
///    back button, pops on save.
/// Which mode this is is captured once in [initState] from the *current*
/// `profileComplete` value, so the AppBar doesn't change mid-edit if the
/// save itself is what flips it.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _schoolNameCtrl = TextEditingController();
  final _gradeCtrl = TextEditingController();
  final _facultyCtrl = TextEditingController();
  final _departmentCtrl = TextEditingController();
  final _courseCtrl = TextEditingController();

  late final bool _isEditing;
  SchoolType? _selectedType;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _isEditing = user?.profileComplete ?? false;
    _selectedType = SchoolType.fromKey(user?.schoolType);
    _schoolNameCtrl.text = user?.school ?? '';
    _gradeCtrl.text = user?.grade ?? '';
    _facultyCtrl.text = user?.faculty ?? '';
    _departmentCtrl.text = user?.department ?? '';
    _courseCtrl.text = user?.course ?? '';
  }

  @override
  void dispose() {
    _schoolNameCtrl.dispose();
    _gradeCtrl.dispose();
    _facultyCtrl.dispose();
    _departmentCtrl.dispose();
    _courseCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedType == null) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        style: ToastificationStyle.flat,
        title: Text(AppStrings.t('school_type_required')),
        autoCloseDuration: const Duration(seconds: 3),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref.read(authNotifierProvider.notifier).saveSchoolProfile(
          schoolType: _selectedType!.key,
          schoolName: _schoolNameCtrl.text,
          grade: _gradeCtrl.text,
          faculty: _selectedType!.hasFaculty ? _facultyCtrl.text : null,
          department: _departmentCtrl.text,
          course: _courseCtrl.text,
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
    if (_isEditing && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authNotifierProvider).isLoading;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        automaticallyImplyLeading: _isEditing,
        title: Text(
          AppStrings.t('school_setup_title'),
          style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP']),
        ),
      ),
      body: SafeArea(
        child: ResponsiveBody(
          maxWidth: 480,
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
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP']),
                    ),
                    const SizedBox(height: 24),
                  ],
                  Text(
                    AppStrings.t('school_type_label'),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: SchoolType.values.map((t) {
                      final selected = t == _selectedType;
                      return ChoiceChip(
                        label: Text(t.label),
                        selected: selected,
                        onSelected: (_) => setState(() => _selectedType = t),
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w500),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    AppStrings.t('school_name_label'),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  AppInputField(
                    controller: _schoolNameCtrl,
                    hintText: AppStrings.t('school_name_hint'),
                    textInputAction: TextInputAction.next,
                    validator: Validators.required,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppStrings.t('school_grade_label'),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  AppInputField(
                    controller: _gradeCtrl,
                    hintText: AppStrings.t('school_grade_hint'),
                    textInputAction: TextInputAction.next,
                  ),
                  if (_selectedType?.hasFaculty ?? false) ...[
                    const SizedBox(height: 16),
                    Text(
                      AppStrings.t('school_faculty_label'),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    AppInputField(
                      controller: _facultyCtrl,
                      hintText: AppStrings.t('school_faculty_hint'),
                      textInputAction: TextInputAction.next,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    AppStrings.t('school_department_label'),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  AppInputField(
                    controller: _departmentCtrl,
                    hintText: AppStrings.t('school_department_hint'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppStrings.t('school_course_label'),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  AppInputField(
                    controller: _courseCtrl,
                    hintText: AppStrings.t('school_course_hint'),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => loading ? null : _submit(),
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    onPressed: loading ? null : _submit,
                    child: loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : Text(_isEditing ? AppStrings.t('btn_save') : AppStrings.t('school_setup_save_btn')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
