import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:toastification/toastification.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_input_field.dart';
import '../../../shared/widgets/pressable.dart';
import '../../school/school_providers.dart';
import '../models/school_type.dart';
import '../providers/auth_provider.dart';

/// Mandatory school-profile step: school type first, then only the fields
/// that type has in the Japanese system — 課程 (高校/大学院), 学年 chips,
/// 学部/研究科, 学科/専攻 and コース (see [SchoolType]).
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
  final _facultyCtrl = TextEditingController();
  final _departmentCtrl = TextEditingController();
  final _courseCtrl = TextEditingController();

  late final bool _isEditing;
  SchoolType? _selectedType;
  String? _program;
  int? _grade;
  bool _namePrefilled = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _isEditing = user?.profileComplete ?? false;
    _selectedType = SchoolType.fromKey(user?.schoolType);
    _schoolNameCtrl.text = user?.school ?? '';
    final type = _selectedType;
    if (type != null) {
      _program = type.programs.contains(user?.program) ? user!.program : type.defaultProgram;
      final grade = SchoolType.parseGrade(user?.grade);
      _grade = (grade != null && grade >= 1 && grade <= type.maxGrade(_program)) ? grade : null;
    }
    _facultyCtrl.text = user?.faculty ?? '';
    _departmentCtrl.text = user?.department ?? '';
    _courseCtrl.text = user?.course ?? '';
    // Prefill once from the synced school name, never over what the user typed.
    ref.listenManual(schoolInfoProvider, (_, next) {
      final name = next.valueOrNull?.name ?? '';
      if (_namePrefilled || name.isEmpty) return;
      _namePrefilled = true;
      if (_schoolNameCtrl.text.trim().isEmpty) _schoolNameCtrl.text = name;
    }, fireImmediately: true);
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
    // Keep the current 課程 when it is also valid for the new type.
    _program = t.programs.contains(_program) ? _program : t.defaultProgram;
    _selectedType = t;
    _clampGrade();
  }

  void _clampGrade() {
    if (_grade != null && _grade! > _selectedType!.maxGrade(_program)) _grade = null;
  }

  Widget _label(String key) => Text(
        AppStrings.t(key),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
      );

  /// A school-linked student's saved 学年/コース, locked unless the school
  /// admin allows changes (mirrors firestore.rules users/{uid} update).
  bool _classLocked() {
    final user = ref.read(currentUserProvider);
    final info = ref.read(schoolInfoProvider).valueOrNull;
    // Only a student already saved under this school is locked (same as the
    // rules); a first link, or a test account moving in, picks freely.
    if (user == null || info == null || user.schoolDomain != info.domain) return false;
    return info.locksStudentClass(grade: user.grade, course: user.course);
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {bool enabled = true}) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: enabled ? (_) => setState(onTap) : null,
        selectedColor: AppColors.primary,
        checkmarkColor: AppColors.onPrimary,
        labelStyle: TextStyle(color: selected ? AppColors.onPrimary : AppColors.textPrimary, fontWeight: FontWeight.w500),
      );

  List<String> _schoolCourses() =>
      ref.read(schoolInfoProvider).valueOrNull?.courses ?? const [];

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
    if (type.maxGrade(_program) > 0 && _grade == null) return errorToast('school_grade_required');
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final courses = _schoolCourses();
    // Locked: resend the stored strings untouched (a legacy "２年生" would
    // otherwise come back as "2" and be refused by the rules).
    final user = ref.read(currentUserProvider);
    final locked = _classLocked();

    await ref.read(authNotifierProvider.notifier).saveSchoolProfile(
          schoolType: type.key,
          schoolName: _schoolNameCtrl.text,
          // Hidden fields are saved as null so they never keep stale values.
          grade: locked ? user?.grade : (_grade == null ? null : '$_grade'),
          program: type.programs.isEmpty ? null : _program,
          faculty: type.hasFaculty ? _facultyCtrl.text : null,
          department: type.hasDepartment ? _departmentCtrl.text : null,
          // Synced school courses win: only a matching chip is saved.
          course: locked
              ? user?.course
              : courses.isNotEmpty
                  ? (courses.contains(_courseCtrl.text) ? _courseCtrl.text : null)
                  : (type.hasCourse ? _courseCtrl.text : null),
          schoolDomain: ref.read(schoolDomainProvider),
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
    final schoolInfo = ref.watch(schoolInfoProvider).valueOrNull;
    final schoolCourses = schoolInfo?.courses ?? const <String>[];
    final showCourseChips = schoolCourses.isNotEmpty;
    final showCourseField = type != null && type.hasCourse && !showCourseChips;
    ref.watch(currentUserProvider);
    final locked = _classLocked();
    // Warn before the first save too: once saved, the choice sticks.
    final showLockNote = locked || (schoolInfo != null && !schoolInfo.allowStudentEdit && schoolCourses.isNotEmpty);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: Text(
          AppStrings.t('school_setup_title'),
          style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP']),
        ),
      ),
      body: SafeArea(
        // Top-aligned (not centered) so toggling the 学部 field never shifts the form.
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
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP']),
                    ),
                    const SizedBox(height: 24),
                  ],
                  _label('school_type_label'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: SchoolType.values.map((t) => _chip(t.label, t == type, () => _selectType(t))).toList(),
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
                  // Fields depend on the school type: fade the new set in
                  // instead of letting it pop.
                  Animate(
                    key: ValueKey(type),
                    effects: const [FadeEffect(duration: AppMotion.fadeDuration)],
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  if (type != null && type.programs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _label('school_program_label'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: type.programs
                          .map((p) => _chip(AppStrings.t('program_$p'), p == _program, () {
                                _program = p;
                                _clampGrade();
                              }))
                          .toList(),
                    ),
                  ],
                  if (maxGrade > 0) ...[
                    const SizedBox(height: 16),
                    _label('school_grade_label'),
                    if (showLockNote) ...[
                      const SizedBox(height: 4),
                      Text(AppStrings.t('school_edit_locked'),
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 1; i <= maxGrade; i++)
                          _chip(AppStrings.t('school_grade_n', {'n': i}), i == _grade, () => _grade = i, enabled: !locked),
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
                      textInputAction: showCourseField ? TextInputAction.next : TextInputAction.done,
                      onSubmitted: showCourseField ? null : (_) => loading ? null : _submit(),
                      maxLength: 100,
                    ),
                  ],
                  if (showCourseChips) ...[
                    const SizedBox(height: 16),
                    _label('school_course_label'),
                    const SizedBox(height: 4),
                    Text(
                      AppStrings.t('school_course_from_school'),
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in schoolCourses)
                          _chip(c, c == _courseCtrl.text, () => _courseCtrl.text = c, enabled: !locked),
                      ],
                    ),
                  ],
                  if (showCourseField) ...[
                    const SizedBox(height: 16),
                    _label('school_course_label'),
                    const SizedBox(height: 8),
                    AppInputField(
                      controller: _courseCtrl,
                      readOnly: locked,
                      hintText: AppStrings.t('school_course_hint'),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => loading ? null : _submit(),
                      maxLength: 100,
                    ),
                  ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Pressable(
                    child: ElevatedButton(
                    onPressed: loading ? null : _submit,
                    child: loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPrimary))
                        : Text(_isEditing ? AppStrings.t('btn_save') : AppStrings.t('school_setup_save_btn')),
                    ),
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
