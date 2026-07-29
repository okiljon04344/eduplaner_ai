abstract class Validators {
  static String? required(String? v) {
    if (v == null || v.trim().isEmpty) return 'この項目は必須です';
    return null;
  }

  static String? Function(String?) maxLength(int n) {
    return (String? v) {
      if (v != null && v.length > n) return '$n文字以内で入力してください';
      return null;
    };
  }

  static String? Function(String?) minLength(int n) {
    return (String? v) {
      if (v == null || v.length < n) return '$n文字以上で入力してください';
      return null;
    };
  }
}
