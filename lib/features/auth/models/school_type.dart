import '../../../core/l10n/app_strings.dart';
import 'user_model.dart';

/// School-type keys stored in `users/{uid}.schoolType`. Store the `key`, never
/// the localized [label]. Declaration order is the chip order in the profile form.
enum SchoolType {
  juniorHigh('junior_high'),
  highSchool('high_school'),
  kosen('kosen'),
  vocational('vocational'),
  juniorCollege('junior_college'),
  university('university'),
  graduate('graduate'),
  other('other');

  final String key;
  const SchoolType(this.key);

  static SchoolType? fromKey(String? key) {
    for (final t in values) {
      if (t.key == key) return t;
    }
    return null;
  }

  String get label => AppStrings.t('school_type_$key');

  /// Program (course track) keys, stored in `users/{uid}.program` and localized as
  /// `program_$key`. Only high school (full-time/part-time/correspondence) and
  /// graduate school (master/doctor/professional) have them.
  List<String> get programs => switch (this) {
        SchoolType.highSchool => const ['full_time', 'part_time', 'correspondence'],
        SchoolType.graduate => const ['master', 'doctor', 'professional'],
        _ => const [],
      };

  String? get defaultProgram => switch (this) {
        SchoolType.highSchool => 'full_time',
        SchoolType.graduate => 'master',
        _ => null,
      };

  /// Number of selectable grades (0 = none). Part-time/correspondence high school
  /// runs 4 years; doctoral programs are 4, master/professional programs 2.
  int maxGrade(String? program) => switch (this) {
        SchoolType.juniorHigh => 3,
        SchoolType.highSchool => (program == 'part_time' || program == 'correspondence') ? 4 : 3,
        SchoolType.kosen => 5,
        SchoolType.vocational => 4,
        SchoolType.juniorCollege => 3,
        SchoolType.university => 6,
        SchoolType.graduate => program == 'doctor' ? 4 : 2,
        SchoolType.other => 0,
      };

  /// Only university and graduate school have a faculty tier above department;
  /// graduate school relabels them via [facultyLabelKey]/[departmentLabelKey].
  bool get hasFaculty => this == SchoolType.university || this == SchoolType.graduate;

  bool get hasDepartment => this != SchoolType.juniorHigh && this != SchoolType.other;

  bool get hasCourse => this == SchoolType.highSchool || this == SchoolType.vocational;

  String get facultyLabelKey => this == SchoolType.graduate ? 'school_graduate_school_label' : 'school_faculty_label';
  String get facultyHintKey => this == SchoolType.graduate ? 'school_graduate_school_hint' : 'school_faculty_hint';
  String get departmentLabelKey => this == SchoolType.graduate ? 'school_major_label' : 'school_department_label';
  String get departmentHintKey => this == SchoolType.graduate ? 'school_major_hint' : 'school_department_hint';

  /// First run of digits (half- or full-width) in [raw]. Legacy `grade` data
  /// is free text like "2年生" or "２年"; new data is digits only.
  static int? parseGrade(String? raw) {
    final m = RegExp(r'[0-9０-９]+').firstMatch(raw ?? '');
    if (m == null) return null;
    final digits = m.group(0)!.runes.map((r) => r >= 0xFF10 ? r - 0xFF10 : r - 0x30).join();
    return int.tryParse(digits);
  }
}

/// One-line school summary for Settings, e.g. "大学 2年 · 工学部"; null if the
/// profile isn't set up.
String? schoolSummary(UserModel? user) {
  final type = SchoolType.fromKey(user?.schoolType);
  if (type == null) return null;
  final grade = SchoolType.parseGrade(user?.grade);
  final faculty = user?.faculty;
  return type.label +
      (grade != null ? ' ${AppStrings.t('school_grade_n', {'n': grade})}' : '') +
      (faculty != null && faculty.isNotEmpty ? ' · $faculty' : '');
}
