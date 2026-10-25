import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_strings.dart';

/// The active UI locale, persisted across restarts.
///
/// A synchronous [Notifier] so there is no AsyncLoading state: [state] changes
/// once, after the new strings are loaded, so the [ValueKey] in [EduPlannerApp]
/// triggers exactly one remount per language switch.
class LocaleNotifier extends Notifier<String> {
  static const _key = 'app_locale';

  /// Starts from the locale pre-loaded in [main] before `runApp`.
  @override
  String build() => AppStrings.currentLocale;

  /// Loads the strings for [locale], persists the choice, then updates [state].
  ///
  /// If the load fell back to another locale (unsupported code or unreadable
  /// asset), nothing is persisted and the previous strings are restored, so
  /// state and loaded strings never diverge.
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
  }
}

/// Current locale code (e.g. `'ja'`, `'en'`, `'uz'`); change it with
/// `ref.read(localeProvider.notifier).setLocale(code)`.
final localeProvider =
    NotifierProvider<LocaleNotifier, String>(LocaleNotifier.new);
