import '../l10n/app_strings.dart';

abstract class Validators {
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? required(String? v) {
    if (v == null || v.trim().isEmpty) return AppStrings.t('val_required');
    return null;
  }

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return AppStrings.t('val_required');
    if (!_emailPattern.hasMatch(v.trim())) return AppStrings.t('val_email_invalid');
    return null;
  }

  static String? Function(String?) maxLength(int n) {
    return (String? v) {
      if (v != null && v.length > n) return AppStrings.t('val_max_length', {'n': n});
      return null;
    };
  }

  static String? Function(String?) minLength(int n) {
    return (String? v) {
      if (v == null || v.length < n) return AppStrings.t('val_min_length', {'n': n});
      return null;
    };
  }
}
