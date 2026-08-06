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
class LocaleNotifier extends Notifier<String> {
  static const _key = 'app_locale';

  /// Returns the locale that was pre-loaded in [main] before runApp.
  /// Falls back to `'ja'` if nothing was loaded yet.
  @override
  String build() => AppStrings.currentLocale;

  /// Loads the translation JSON for [locale], persists the choice, then
  /// updates [state].  State changes only once — after the load completes —
  /// so the widget tree rebuilds exactly once with the new strings in place.
  Future<void> setLocale(String locale) async {
    await AppStrings.load(locale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale);
    state = locale;
  }
}

/// Global provider for the current locale string (e.g. `'ja'`, `'en'`, `'uz'`).
///
/// Watch this in [EduPlannerApp] to rebuild on locale changes.
/// Use `ref.read(localeProvider.notifier).setLocale(code)` to change locale.
final localeProvider = NotifierProvider<LocaleNotifier, String>(LocaleNotifier.new);
