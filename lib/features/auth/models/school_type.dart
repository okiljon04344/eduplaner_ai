import '../../../core/l10n/app_strings.dart';
import 'user_model.dart';

/// Canonical school-type keys stored in Firestore (`users/{uid}.schoolType`).
/// Never store the localized label — always this `key`, resolved to the
/// current locale via [label] at display time (same pattern as
/// `kWeekdayKanji`/`DateHelper.localizedWeekday`).
/// Declaration order is the chip order in the profile form.
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

  /// 課程 keys (stored in `users/{uid}.program`, localized as `program_$key`).
  /// Only 高校 (全日制/定時制/通信制) and 大学院 (修士/博士/専門職) have them.
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

  /// Number of selectable 学年 for this type (0 = no grade, e.g. その他).
  /// 定時制/通信制 high school run 4 years; 博士課程 is 4 (medical doctoral
  /// programs), 修士/専門職学位課程 are 2.
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

  /// Only university-level institutions in the Japanese system have a 学部
  /// (faculty) tier above 学科 (department) — 大学院 relabels them as
  /// 研究科/専攻 via [facultyLabelKey]/[departmentLabelKey].
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

/// One-line school summary for Settings, e.g. "大学 2年 · 工学部".
/// Null when the school type is unknown (profile not set up).
String? schoolSummary(UserModel? user) {
  final type = SchoolType.fromKey(user?.schoolType);
  if (type == null) return null;
  final grade = SchoolType.parseGrade(user?.grade);
  final faculty = user?.faculty;
  return type.label +
      (grade != null ? ' ${AppStrings.t('school_grade_n', {'n': grade})}' : '') +
      (faculty != null && faculty.isNotEmpty ? ' · $faculty' : '');
}
