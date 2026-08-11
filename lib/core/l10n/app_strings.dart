import 'dart:convert';
import 'package:flutter/services.dart';

/// Static in-memory string cache for all UI translations.
///
/// At app startup (and on every locale change) call [load] to parse the
/// matching JSON file from `assets/l10n/<locale>.json` into [_strings].
/// Widgets call [t] to look up a key; if the key is missing the key itself
/// is returned so broken translations surface visually in development.
///
/// Design choice: this avoids Flutter's built-in `intl`/`gen_l10n` toolchain
/// (which requires code-gen on every string change) in favour of simple JSON
/// asset loading.  The trade-off is that string safety is runtime, not
/// compile-time — watch for silent fallbacks during QA.
class AppStrings {
  AppStrings._();

  static Map<String, String> _strings = {};
  static String _currentLocale = 'ja';

  /// The locale code that is currently loaded (e.g. `'ja'`, `'en'`, `'uz'`).
  static String get currentLocale => _currentLocale;

  /// Loads `assets/l10n/<locale>.json` and caches all key/value pairs.
  ///
  /// If [locale] is not in [_supported] it falls back to `'ja'`.
  /// If the asset file fails to parse it silently retries with `'ja'`,
  /// so the app never crashes due to a missing or malformed translation file.
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

  /// Returns the translated string for [key].
  ///
  /// Optional [args] map can be used to replace placeholders in the string
  /// (e.g. `t('hello', {'name': 'User'})` replaces `{name}` in the translation).
  ///
  /// Falls back to [key] itself when the key is absent — visible as raw keys
  /// in the UI, which makes gaps in a new translation file obvious during QA.
  static String t(String key, [Map<String, dynamic>? args]) {
    var value = _strings[key] ?? key;
    if (args != null) {
      args.forEach((k, v) {
        value = value.replaceAll('{$k}', v.toString());
      });
    }
    return value;
  }

  /// BCP-47 locale codes supported by the app.
  static const _supported = {
    'ja', 'en', 'zh', 'zh_TW', 'ko', 'vi', 'th', 'id', 'ms',
    'hi', 'ar', 'es', 'fr', 'de', 'pt', 'ru', 'it', 'tr', 'nl', 'uz', 'fil',
  };

  /// Display metadata for every supported locale.
  ///
  /// Each record is `(code, nativeName, flagEmoji)`.
  /// Used by the language picker in the settings screen.
  static const locales = [
    ('ja',    '日本語',           '🇯🇵'),
    ('en',    'English',         '🇺🇸'),
    ('zh',    '中文 (简体)',       '🇨🇳'),
    ('zh_TW', '中文 (繁體)',       '🇹🇼'),
    ('ko',    '한국어',           '🇰🇷'),
    ('vi',    'Tiếng Việt',      '🇻🇳'),
    ('th',    'ภาษาไทย',         '🇹🇭'),
    ('id',    'Bahasa Indonesia', '🇮🇩'),
    ('ms',    'Bahasa Melayu',   '🇲🇾'),
    ('hi',    'हिन्दी',           '🇮🇳'),
    ('ar',    'العربية',         '🇸🇦'),
    ('es',    'Español',         '🇪🇸'),
    ('fr',    'Français',        '🇫🇷'),
    ('de',    'Deutsch',         '🇩🇪'),
    ('pt',    'Português',       '🇧🇷'),
    ('ru',    'Русский',         '🇷🇺'),
    ('it',    'Italiano',        '🇮🇹'),
    ('tr',    'Türkçe',          '🇹🇷'),
    ('nl',    'Nederlands',      '🇳🇱'),
    ('uz',    "O'zbek",          '🇺🇿'),
    ('fil',   'Filipino',        '🇵🇭'),
  ];
}
