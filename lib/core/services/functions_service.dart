import 'package:cloud_functions/cloud_functions.dart';
import '../l10n/app_strings.dart';

/// Centralized entry point for every Cloud Functions call in the app.
///
/// All callables are deployed in `asia-northeast1` (see `functions/index.js`)
/// — this must match, or every call fails with `not-found`. `timeout` is
/// shared across all calls (AI analysis / quiz generation are the slowest,
/// so the whole surface uses the same generous budget rather than tuning
/// each call site separately).
///
/// UZ: Ilovadagi har bir Cloud Functions chaqiruvi uchun markazlashtirilgan kirish nuqtasi.
///
/// Barcha chaqiriluvchilar `asia-northeast1` hududida joylashtirilgan (`functions/index.js`ga qarang)
/// — bu mos kelishi kerak, aks holda har bir chaqiruv `not-found` bilan muvaffaqiyatsiz tugaydi.
/// `timeout` barcha chaqiruvlar bo'ylab taqsimlanadi (AI tahlili / viktorina generatsiyasi eng sekin,
/// shuning uchun har bir chaqiruv joyini alohida sozlashdan ko'ra butun tizim bir xil keng byudjetdan foydalanadi).
abstract class FunctionsService {
  static final FirebaseFunctions _instance = () {
    final f = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
    // Emulator-auth tokens are rejected by production functions anyway;
    // route to a (possibly absent) local functions emulator instead.
    // UZ: Emulator-auth tokenlari production funksiyalari tomonidan baribir rad etiladi;
    // buning o'rniga (ehtimol mavjud bo'lmagan) mahalliy funksiyalar emulatoriga yo'naltiring.
    if (const bool.fromEnvironment('USE_EMULATOR')) {
      const host = String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');
      f.useFunctionsEmulator(host, 5001);
    }
    return f;
  }();
  static const Duration timeout = Duration(seconds: 120);

  static HttpsCallable callable(String name) =>
      _instance.httpsCallable(name, options: HttpsCallableOptions(timeout: timeout));

  /// Extracts `details['reason']` from a [FirebaseFunctionsException] when present.
  static String? reasonOf(FirebaseFunctionsException e) {
    final details = e.details;
    return details is Map ? details['reason']?.toString() : null;
  }

  /// Maps the error codes and shared `details['reason']` tags any callable
  /// can raise (auth/timeout/offline/budget/unavailable/server) to a localized
  /// message. Call sites should check their own function-specific codes first
  /// and fall back to this for the rest.
  static String describeError(FirebaseFunctionsException e) {
    final reason = reasonOf(e);
    if (reason == 'ai_temporarily_unavailable') {
      return AppStrings.t('err_ai_temporarily_unavailable');
    }
    if (reason == 'ai_budget_exceeded') {
      return AppStrings.t('err_ai_budget_exceeded');
    }

    switch (e.code) {
      case 'unauthenticated':
        return AppStrings.t('err_login_required');
      case 'deadline-exceeded':
        return AppStrings.t('err_timeout');
      case 'resource-exhausted':
        return AppStrings.t('err_ai_limit_reached');
      case 'unavailable':
        return AppStrings.t('err_network');
      default:
        return AppStrings.t('err_server');
    }
  }
}
