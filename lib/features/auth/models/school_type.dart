import '../../../core/l10n/app_strings.dart';

/// Canonical school-type keys stored in Firestore (`users/{uid}.schoolType`).
/// Never store the localized label — always this `key`, resolved to the
/// current locale via [label] at display time (same pattern as
/// `kWeekdayKanji`/`DateHelper.localizedWeekday`).
enum SchoolType {
  highSchool('high_school'),
  vocational('vocational'),
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

  /// Only university-level institutions in the Japanese system have a 学部
  /// (faculty) tier above 学科 (department) — high school/vocational/other
  /// go straight to department.
  bool get hasFaculty => this == SchoolType.university || this == SchoolType.graduate;
}
