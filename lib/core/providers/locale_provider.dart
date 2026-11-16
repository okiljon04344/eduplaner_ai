import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_strings.dart';

/// Manages the active UI locale and persists it across app restarts.
///
/// Uses a synchronous [Notifier] (not AsyncNotifier) so there is no
/// intermediate AsyncLoading state.  State changes directly from the old
/// locale to the new one after the JSON asset has been loaded, which means
/// the [ValueKey] in [EduPlannerApp] changes exactly once per language switch
/// and triggers a clean full-tree remount.
///
/// UZ: Faol UI tilini (locale) boshqaradi va uni ilova qayta ishga tushirilganda saqlab qoladi.
///
/// Sinxron [Notifier] dan foydalanadi (AsyncNotifier emas), shuning uchun oraliq AsyncLoading
/// holati mavjud emas. JSON asset yuklangandan so'ng holat to'g'ridan-to'g'ri eski tildan yangisiga
/// o'tadi, bu esa [EduPlannerApp] dagi [ValueKey] til almashganda aynan bir marta o'zgarishini va
/// butun daraxtning toza qayta o'rnatilishini ta'minlaydi.
class LocaleNotifier extends Notifier<String> {
  static const _key = 'app_locale';

  /// Returns the locale that was pre-loaded in [main] before runApp.
  /// Falls back to `'ja'` if nothing was loaded yet.
  ///
  /// UZ: runApp dan oldin [main] da oldindan yuklangan tilni qaytaradi.
  /// Agar hali hech narsa yuklanmagan bo'lsa, `'ja'` ga qaytadi.
  @override
  String build() => AppStrings.currentLocale;

  /// Loads the translation JSON for [locale], persists the choice, then
  /// updates [state].  State changes only once — after the load completes —
  /// so the widget tree rebuilds exactly once with the new strings in place.
  ///
  /// If the load fell back to another locale (unsupported code or an
  /// unreadable asset), nothing is persisted or changed and the previous
  /// locale's strings are restored, so state and loaded strings never diverge.
  ///
  /// UZ: [locale] uchun tarjima JSON faylini yuklaydi, tanlovni saqlaydi va keyin [state] ni
  /// yangilaydi. Holat faqat bir marta — yuklash tugagandan so'ng — o'zgaradi, shuning uchun vidjetlar
  /// daraxti yangi qatorlar joyida bo'lgan holda aynan bir marta qayta quriladi.
  ///
  /// Agar yuklash boshqa tilga qaytib qolsa (qo'llab-quvvatlanmaydigan kod yoki o'qib bo'lmaydigan
  /// asset), hech narsa saqlanmaydi yoki o'zgartirilmaydi hamda avvalgi til qatorlari qayta tiklanadi,
  /// shuning uchun holat va yuklangan qatorlar hech qachon farqlanib qolmaydi.
  Future<void> setLocale(String locale) async {
    final previous = state;
    await AppStrings.load(locale);
    if (AppStrings.currentLocale != locale) {
      await AppStrings.load(previous);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale);
    state = locale;
    await _syncPushLanguage(locale);
  }

  /// Server pushes use `users/{uid}.language`. `update`, not `set(merge)`, so a
  /// deleted account's doc is never recreated. Best effort: a failure only
  /// leaves pushes in the previous language until the next token refresh.
  ///
  /// UZ: Server push xabarlari `users/{uid}.language` dan foydalanadi. `set(merge)` emas, `update`,
  /// shuning uchun o'chirilgan hisob hujjati hech qachon qayta yaratilmaydi. Best effort: xatolik
  /// faqat keyingi token yangilanishigacha push xabarlarini oldingi tilda qoldiradi.
  static Future<void> _syncPushLanguage(String locale) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'language': locale});
    } catch (e) {
      debugPrint('Push language sync failed: $e');
    }
  }
}

/// Global provider for the current locale string (e.g. `'ja'`, `'en'`, `'uz'`).
///
/// Watch this in [EduPlannerApp] to rebuild on locale changes.
/// Use `ref.read(localeProvider.notifier).setLocale(code)` to change locale.
///
/// UZ: Joriy til qatori (masalan, `'ja'`, `'en'`, `'uz'`) uchun global provayder.
///
/// Til o'zgarganda qayta qurish uchun buni [EduPlannerApp] da kuzating (watch).
/// Tilni o'zgartirish uchun `ref.read(localeProvider.notifier).setLocale(code)` dan foydalaning.
final localeProvider = NotifierProvider<LocaleNotifier, String>(LocaleNotifier.new);
