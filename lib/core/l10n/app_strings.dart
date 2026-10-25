import 'dart:convert';
import 'package:flutter/services.dart';

/// In-memory cache of the UI translations, loaded from `assets/l10n/<locale>.json`
/// at startup and on every locale change. Widgets look keys up with [t].
///
/// Plain JSON assets are used instead of `gen_l10n` to avoid code generation on
/// every string change. The trade-off is that missing keys are only caught at
/// runtime, where [t] returns the raw key so gaps are easy to spot.
class AppStrings {
  AppStrings._();

  static Map<String, String> _strings = {};
  static String _currentLocale = 'ja';

  /// The loaded locale code (e.g. `'ja'`, `'en'`, `'uz'`).
  static String get currentLocale => _currentLocale;

  /// Loads and caches the strings for [locale]. An unsupported locale or an
  /// unreadable file falls back to `'ja'`, so a bad translation never crashes the app.
  static Future<void> load(String locale) async {
    final target = _supported.contains(locale) ? locale : 'ja';
    try {
      final raw = await rootBundle.loadString('assets/l10n/$target.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _strings = map.map((k, v) => MapEntry(k, v.toString()));
      _currentLocale = target;
    } catch (_) {
      if (target != 'ja') await load('ja');
    }
  }

  /// The translation for [key], with `{name}` placeholders replaced from [args].
  /// Returns [key] itself when it is missing.
  static String t(String key, [Map<String, dynamic>? args]) {
    var value = _strings[key] ?? key;
    if (args != null) {
      args.forEach((k, v) {
        value = value.replaceAll('{$k}', v.toString());
      });
    }
    return value;
  }

  /// Supported locale codes.
  static const _supported = {
    'ja',
    'en',
    'zh',
    'zh_TW',
    'ko',
    'vi',
    'th',
    'id',
    'ms',
    'hi',
    'ar',
    'es',
    'fr',
    'de',
    'pt',
    'ru',
    'it',
    'tr',
    'nl',
    'uz',
    'fil',
  };

  /// `(code, nativeName, flagEmoji)` for every supported locale, used by the
  /// language picker.
  static const locales = [
    ('ja', '日本語', '🇯🇵'),
    ('en', 'English', '🇺🇸'),
    ('zh', '中文 (简体)', '🇨🇳'),
    ('zh_TW', '中文 (繁體)', '🇹🇼'),
    ('ko', '한국어', '🇰🇷'),
    ('vi', 'Tiếng Việt', '🇻🇳'),
    ('th', 'ภาษาไทย', '🇹🇭'),
    ('id', 'Bahasa Indonesia', '🇮🇩'),
    ('ms', 'Bahasa Melayu', '🇲🇾'),
    ('hi', 'हिन्दी', '🇮🇳'),
    ('ar', 'العربية', '🇸🇦'),
    ('es', 'Español', '🇪🇸'),
    ('fr', 'Français', '🇫🇷'),
    ('de', 'Deutsch', '🇩🇪'),
    ('pt', 'Português', '🇧🇷'),
    ('ru', 'Русский', '🇷🇺'),
    ('it', 'Italiano', '🇮🇹'),
    ('tr', 'Türkçe', '🇹🇷'),
    ('nl', 'Nederlands', '🇳🇱'),
    ('uz', "O'zbek", '🇺🇿'),
    ('fil', 'Filipino', '🇵🇭'),
  ];
}
