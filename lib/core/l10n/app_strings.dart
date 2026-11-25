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
///
/// UZ: Barcha UI tarjimalari uchun xotiradagi statik satrlar keshi.
///
/// Ilova ishga tushganda (va har bir lokal o'zgarganda) `assets/l10n/<locale>.json` dan mos JSON
/// faylini [_strings] ga tahlil qilish uchun [load] ni chaqiring. Vidjetlar kalitni qidirish
/// uchun [t] ni chaqiradi; agar kalit topilmasa, ishlab chiqish jarayonida buzilgan tarjimalar
/// vizual ko'rinishi uchun kalitning o'zi qaytariladi.
///
/// Dizayn tanlovi: bu oddiy JSON aktivlarini yuklash foydasiga har bir satr o'zgarishida kod
/// generatsiyasini talab qiladigan Flutter'ning o'rnatilgan `intl`/`gen_l10n` vositalar zanjiridan
/// qochadi. Kamchiligi shundaki, satrlar xavfsizligi kompilyatsiya vaqtida emas, balki bajarilish
/// vaqtida (runtime) bo'ladi — QA jarayonida sezilarsiz zaxira variantlarga e'tibor bering.
class AppStrings {
  AppStrings._();

  static Map<String, String> _strings = {};
  static String _currentLocale = 'ja';

  /// The locale code that is currently loaded (e.g. `'ja'`, `'en'`, `'uz'`).
  ///
  /// UZ: Hozirda yuklangan lokal kodi (masalan, `'ja'`, `'en'`, `'uz'`).
  static String get currentLocale => _currentLocale;

  /// Loads `assets/l10n/<locale>.json` and caches all key/value pairs.
  ///
  /// If [locale] is not in [_supported] it falls back to `'ja'`.
  /// If the asset file fails to parse it silently retries with `'ja'`,
  /// so the app never crashes due to a missing or malformed translation file.
  ///
  /// UZ: `assets/l10n/<locale>.json` ni yuklaydi va barcha kalit/qiymat juftliklarini keshlaydi.
  ///
  /// Agar [locale] [_supported] ichida bo'lmasa, u `'ja'` ga qaytadi.
  /// Agar aktiv faylini tahlil qilish bajarilmasa, u bildirmasdan `'ja'` bilan qayta urinib ko'radi,
  /// shuning uchun tarjima fayli yo'qligi yoki noto'g'riligi sababli ilova hech qachon qulab tushmaydi.
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
  ///
  /// UZ: [key] uchun tarjima qilingan satrni qaytaradi.
  ///
  /// Satrdagi o'rinbosarlarni almashtirish uchun ixtiyoriy [args] map'idan foydalanish mumkin
  /// (masalan, `t('hello', {'name': 'User'})` tarjimadagi `{name}` ni almashtiradi).
  ///
  /// Kalit mavjud bo'lmaganda [key] ning o'ziga qaytadi — bu UI da xom kalitlar sifatida
  /// ko'rinadi va yangi tarjima faylidagi bo'shliqlarni QA paytida yaqqol ko'rsatadi.
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
  ///
  /// UZ: Ilova tomonidan qo'llab-quvvatlanadigan BCP-47 lokal kodlari.
  static const _supported = {
    'ja', 'en', 'zh', 'zh_TW', 'ko', 'vi', 'th', 'id', 'ms',
    'hi', 'ar', 'es', 'fr', 'de', 'pt', 'ru', 'it', 'tr', 'nl', 'uz', 'fil',
  };

  /// Display metadata for every supported locale.
  ///
  /// Each record is `(code, nativeName, flagEmoji)`.
  /// Used by the language picker in the settings screen.
  ///
  /// UZ: Qo'llab-quvvatlanadigan har bir lokal uchun ko'rsatish metama'lumotlari.
  ///
  /// Har bir yozuv `(code, nativeName, flagEmoji)` ko'rinishida.
  /// Sozlamalar ekranidagi til tanlagich tomonidan ishlatiladi.
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
